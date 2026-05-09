package com.echosync.echosync_ai

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.*

/**
 * Whisper TFLite Inference Engine — aligned with OpenAI audio.py exactly.
 *
 * Key constants (from whisper/audio.py):
 *   SAMPLE_RATE  = 16 000
 *   N_FFT        = 400   (25 ms window)  ← was wrongly 512
 *   HOP_LENGTH   = 160   (10 ms hop)
 *   N_MELS       = 80
 *   N_FRAMES     = 3000  (30 s)
 *
 * Normalisation (from whisper/audio.py log_mel_spectrogram):
 *   log_spec = log10(max(mel_filters @ |STFT|², 1e-10))
 *   log_spec = max(log_spec, log_spec.max() - 8.0)
 *   log_spec = (log_spec + 4.0) / 4.0
 */
class WhisperTFLiteEngine(private val context: Context) {

    // ── Constants — must match OpenAI audio.py exactly ─────────────────────
    companion object {
        private const val TAG = "WhisperEngine"

        const val SAMPLE_RATE   = 16_000
        const val WINDOW_SIZE   = 400        // 25 ms Hann window (OpenAI spec)
        const val N_FFT         = 512        // Zero-pad to power-of-2 for radix-2 FFT
        const val HOP_LENGTH    = 160        // 10 ms hop
        const val N_MELS        = 80
        const val N_FRAMES      = 3_000
        const val CHUNK_SAMPLES = SAMPLE_RATE * 30 // 480 000
    }

    // ── State ───────────────────────────────────────────────────────────────
    private var interpreter : Interpreter? = null
    private val tokenizer   = WhisperTokenizer()
    private val hannWindow  = buildHannWindow()
    private val melFilters  = buildMelFilterbank()

    // ── Public API ──────────────────────────────────────────────────────────

    fun initialize(modelPath: String) {
        val modelFile = File(modelPath)
        require(modelFile.exists()) { "Model not found: $modelPath" }

        val opts = Interpreter.Options().apply { setNumThreads(4) }
        interpreter?.close()
        interpreter = Interpreter(modelFile, opts)

        // Load vocab.json from same directory as model
        val vocabFile = File(modelFile.parent, "vocab.json")
        if (vocabFile.exists()) tokenizer.load(vocabFile)
        else Log.w(TAG, "vocab.json not found — byte-level decoding only")

        logTensorShapes()
    }

    fun transcribe(audioPath: String): String {
        val interp = interpreter ?: throw IllegalStateException("Engine not initialized")

        val pcm = readWavMono16k(audioPath)
        Log.i(TAG, "PCM samples: ${pcm.size}  (${String.format("%.2f", pcm.size / SAMPLE_RATE.toFloat())} s)")
        if (pcm.size < 1_600) return ""

        val logMel = computeLogMelSpectrogram(pcm)

        // Log stats so we can verify scaling is correct
        var minV = Float.MAX_VALUE; var maxV = Float.MIN_VALUE
        for (row in logMel) for (v in row) { if (v < minV) minV = v; if (v > maxV) maxV = v }
        Log.i(TAG, "Log-Mel after norm: min=$minV  max=$maxV  (expected ≈ -2.5 to 1.0)")

        val inputBuf = melToByteBuffer(logMel)
        return runAndDecode(interp, inputBuf)
    }

    fun release() { interpreter?.close(); interpreter = null }

    // ── Inference ───────────────────────────────────────────────────────────

    private fun runAndDecode(interp: Interpreter, inputBuf: ByteBuffer): String {
        val outTensor  = interp.getOutputTensor(0)
        val outShape   = outTensor.shape()
        val totalElems = outShape.fold(1) { a, d -> a * d }
        val outBuf     = ByteBuffer.allocateDirect(totalElems * 4).order(ByteOrder.nativeOrder())

        interp.run(inputBuf, outBuf)
        outBuf.rewind()

        val dtypeName = outTensor.dataType().name
        Log.i(TAG, "Output dtype=$dtypeName  shape=${outShape.contentToString()}")

        return when {
            // INT32 output — direct token IDs
            dtypeName.startsWith("INT") -> {
                val tokens = IntArray(totalElems) { outBuf.int }
                Log.d(TAG, "Raw tokens (first 20): ${tokens.take(20)}")
                tokenizer.decode(tokens)
            }
            // FLOAT [1, seq, vocab] — argmax per step
            outShape.size == 3 -> {
                val seqLen    = outShape[1]
                val vocabSize = outShape[2]
                val logits    = FloatArray(totalElems) { outBuf.float }
                val tokens    = IntArray(seqLen) { pos ->
                    var bestIdx = 0; var bestVal = Float.NEGATIVE_INFINITY
                    for (v in 0 until vocabSize) {
                        val cur = logits[pos * vocabSize + v]
                        if (cur > bestVal) { bestVal = cur; bestIdx = v }
                    }
                    bestIdx
                }
                Log.d(TAG, "Argmax tokens (first 20): ${tokens.take(20)}")
                tokenizer.decode(tokens)
            }
            // FLOAT [1, N] — round to nearest int token
            else -> {
                val floats = FloatArray(totalElems) { outBuf.float }
                val tokens = IntArray(totalElems) { floats[it].roundToInt() }
                tokenizer.decode(tokens)
            }
        }
    }

    // ── WAV Reader ──────────────────────────────────────────────────────────

    private fun readWavMono16k(path: String): FloatArray {
        val bytes = File(path).readBytes()
        if (bytes.size < 44) return FloatArray(0)

        fun i16(o: Int) = ((bytes[o+1].toInt() and 0xFF) shl 8) or (bytes[o].toInt() and 0xFF)
        fun i32(o: Int) = ((bytes[o+3].toInt() and 0xFF) shl 24) or
                          ((bytes[o+2].toInt() and 0xFF) shl 16) or
                          ((bytes[o+1].toInt() and 0xFF) shl 8)  or
                           (bytes[o].toInt() and 0xFF)

        val numChannels    = i16(22)
        val fileSampleRate = i32(24)
        val bitsPerSample  = i16(34)
        val bytesPerSample = bitsPerSample / 8

        // Walk RIFF chunks to find 'data'
        var dataStart = 44; var dataSize = bytes.size - 44
        var pos = 12
        while (pos + 8 <= bytes.size) {
            val chunkId   = String(bytes, pos, 4, Charsets.US_ASCII)
            val chunkSize = i32(pos + 4)
            if (chunkId == "data") { dataStart = pos + 8; dataSize = chunkSize; break }
            pos += 8 + chunkSize.coerceAtLeast(0)
        }

        val numSamples = (dataSize / (numChannels * bytesPerSample)).coerceAtMost(CHUNK_SAMPLES)
        Log.i(TAG, "WAV: ${fileSampleRate}Hz  ${bitsPerSample}bit  ${numChannels}ch  $numSamples samples")

        val buf = ByteBuffer.wrap(bytes, dataStart, bytes.size - dataStart).order(ByteOrder.LITTLE_ENDIAN)
        val mono = FloatArray(numSamples)

        for (s in 0 until numSamples) {
            var sum = 0f
            repeat(numChannels) {
                sum += when (bytesPerSample) {
                    4 -> buf.float                                          // 32-bit float
                    3 -> { val b0 = buf.get().toInt() and 0xFF
                           val b1 = buf.get().toInt() and 0xFF
                           val b2 = buf.get().toInt()
                           ((b2 shl 16) or (b1 shl 8) or b0) / 8_388_608f }
                    2 -> buf.short / 32_768f                               // 16-bit PCM
                    1 -> ((buf.get().toInt() and 0xFF) - 128) / 128f      // 8-bit PCM
                    else -> { buf.get(); 0f }
                }
            }
            mono[s] = (sum / numChannels).coerceIn(-1f, 1f)
        }

        if (fileSampleRate == SAMPLE_RATE) return mono

        // High-quality linear resampling
        Log.i(TAG, "Resampling from $fileSampleRate to $SAMPLE_RATE Hz")
        val ratio  = fileSampleRate.toDouble() / SAMPLE_RATE
        val newLen = (mono.size / ratio).toInt()
        return FloatArray(newLen) { i ->
            val src = i * ratio
            val lo  = src.toInt().coerceIn(0, mono.size - 2)
            val hi  = lo + 1
            (mono[lo] + (mono[hi] - mono[lo]) * (src - lo)).toFloat()
        }
    }

    // ── Log-Mel Spectrogram ─────────────────────────────────────────────────

    /**
     * Exact port of OpenAI whisper/audio.py  log_mel_spectrogram().
     *
     * STFT window = Hann, length = N_FFT = 400, hop = 160.
     * Power spectrum (no extra normalisation factor needed — same as PyTorch).
     * Mel filterbank with Slaney (area) normalisation.
     * log10 → clamp(max - 8) → (x + 4) / 4.
     */
    private fun computeLogMelSpectrogram(pcm: FloatArray): Array<FloatArray> {
        // Audio is padded so we produce exactly N_FRAMES frames
        val paddedLen = (N_FRAMES - 1) * HOP_LENGTH + WINDOW_SIZE
        val padded    = FloatArray(paddedLen)
        pcm.copyInto(padded, 0, 0, minOf(pcm.size, paddedLen))

        val nFreq = N_FFT / 2 + 1   // 257 bins for N_FFT=512
        val mel   = Array(N_MELS) { FloatArray(N_FRAMES) }
        // N_FFT=512 for the radix-2 FFT (zero-padded from 400-sample window)
        val re    = DoubleArray(N_FFT)
        val im    = DoubleArray(N_FFT)

        for (frame in 0 until N_FRAMES) {
            val start = frame * HOP_LENGTH

            // Apply 400-sample Hann window, then zero-pad to N_FFT=512
            for (n in 0 until N_FFT) {
                re[n] = if (n < WINDOW_SIZE && (start + n) < paddedLen)
                            (padded[start + n] * hannWindow[n]).toDouble()
                        else 0.0
                im[n] = 0.0
            }

            fft(re, im)   // in-place, size N_FFT=512

            // Power spectrum then mel filterbank
            for (m in 0 until N_MELS) {
                var e = 0f
                for (k in 0 until nFreq) {
                    val power = (re[k] * re[k] + im[k] * im[k]).toFloat()
                    e += melFilters[m][k] * power
                }
                mel[m][frame] = e
            }
        }

        // log10 with noise floor
        val logMel = Array(N_MELS) { m ->
            FloatArray(N_FRAMES) { t -> log10(mel[m][t].coerceAtLeast(1e-10f)) }
        }

        // ── OpenAI normalisation (audio.py lines 100-102) ──────────────────
        // log_spec = torch.maximum(log_spec, log_spec.max() - 8.0)
        // log_spec = (log_spec + 4.0) / 4.0
        var globalMax = Float.NEGATIVE_INFINITY
        for (row in logMel) for (v in row) if (v > globalMax) globalMax = v
        Log.i(TAG, "Log-Mel raw max=$globalMax  floor=${globalMax - 8f}")

        val floor = globalMax - 8f
        for (m in 0 until N_MELS) {
            for (t in 0 until N_FRAMES) {
                logMel[m][t] = (logMel[m][t].coerceAtLeast(floor) + 4f) / 4f
            }
        }

        return logMel
    }

    // ── Hann Window ─────────────────────────────────────────────────────────

    /** 400-point Hann window matching torch.hann_window(400) */
    private fun buildHannWindow(): FloatArray =
        FloatArray(WINDOW_SIZE) { n -> (0.5 * (1.0 - cos(2.0 * PI * n / WINDOW_SIZE))).toFloat() }

    // ── Mel Filterbank ──────────────────────────────────────────────────────

    /**
     * librosa-style mel filterbank with Slaney area normalisation.
     * Matches torchaudio.transforms.MelSpectrogram(norm='slaney').
     */
    private fun buildMelFilterbank(): Array<FloatArray> {
        fun hzToMel(hz: Double) = 2595.0 * log10(1.0 + hz / 700.0)
        fun melToHz(mel: Double) = 700.0 * (10.0.pow(mel / 2595.0) - 1.0)

        val fMin  = 0.0
        val fMax  = 8_000.0
        val nFreq = N_FFT / 2 + 1

        val melMin = hzToMel(fMin)
        val melMax = hzToMel(fMax)

        // N_MELS + 2 linearly-spaced mel points
        val melPts = DoubleArray(N_MELS + 2) { i -> melMin + i * (melMax - melMin) / (N_MELS + 1) }
        // Convert to FFT bin indices
        val bins = IntArray(N_MELS + 2) { i ->
            floor(melToHz(melPts[i]) * N_FFT / SAMPLE_RATE).toInt().coerceIn(0, nFreq - 1)
        }

        return Array(N_MELS) { m ->
            val lo = bins[m]; val mid = bins[m + 1]; val hi = bins[m + 2]
            // Slaney area normalisation
            val enorm = (2.0 / (melToHz(melPts[m + 2]) - melToHz(melPts[m]))).toFloat()

            FloatArray(nFreq) { k ->
                val w = when {
                    k in lo until mid && mid > lo -> (k - lo).toFloat() / (mid - lo)
                    k in mid..hi    && hi  > mid  -> (hi - k).toFloat() / (hi - mid)
                    else -> 0f
                }
                w * enorm
            }
        }
    }

    // ── ByteBuffer packing ──────────────────────────────────────────────────

    private fun melToByteBuffer(mel: Array<FloatArray>): ByteBuffer {
        val buf = ByteBuffer.allocateDirect(N_MELS * N_FRAMES * 4).order(ByteOrder.nativeOrder())
        for (m in 0 until N_MELS) for (t in 0 until N_FRAMES) buf.putFloat(mel[m][t])
        buf.rewind()
        return buf
    }

    // ── FFT (Cooley-Tukey radix-2, in-place) ────────────────────────────────

    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var tmp = re[i]; re[i] = re[j]; re[j] = tmp
                tmp = im[i];     im[i] = im[j]; im[j] = tmp
            }
        }
        var len = 2
        while (len <= n) {
            val ang = -2.0 * PI / len
            val wRe = cos(ang); val wIm = sin(ang)
            var i = 0
            while (i < n) {
                var curRe = 1.0; var curIm = 0.0
                for (k in 0 until len / 2) {
                    val uRe = re[i + k];               val uIm = im[i + k]
                    val vRe = re[i+k+len/2]*curRe - im[i+k+len/2]*curIm
                    val vIm = re[i+k+len/2]*curIm + im[i+k+len/2]*curRe
                    re[i + k]         = uRe + vRe;     im[i + k]         = uIm + vIm
                    re[i + k + len/2] = uRe - vRe;     im[i + k + len/2] = uIm - vIm
                    val nRe = curRe*wRe - curIm*wIm
                    curIm   = curRe*wIm + curIm*wRe;   curRe = nRe
                }
                i += len
            }
            len *= 2
        }
    }

    // ── Diagnostics ─────────────────────────────────────────────────────────

    private fun logTensorShapes() {
        val interp = interpreter ?: return
        repeat(interp.inputTensorCount) { i ->
            val t = interp.getInputTensor(i)
            Log.i(TAG, "INPUT[$i]  shape=${t.shape().contentToString()}  dtype=${t.dataType()}")
        }
        repeat(interp.outputTensorCount) { i ->
            val t = interp.getOutputTensor(i)
            Log.i(TAG, "OUTPUT[$i] shape=${t.shape().contentToString()}  dtype=${t.dataType()}")
        }
    }
}
