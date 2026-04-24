package com.echosync.echosync_ai

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.*

/**
 * Full Whisper TFLite Inference Engine.
 *
 * Pipeline:
 *   WAV (16 kHz mono)
 *     -> PCM float samples
 *     -> Log-Mel Spectrogram  [1, 80, 3000]
 *     -> TFLite Interpreter
 *     -> Token IDs
 *     -> Decoded Text
 *
 * Supports both output formats:
 *   - int32  [1, N]            (direct token sequence)
 *   - float32 [1, N, vocab]   (logits -> argmax -> tokens)
 */
class WhisperTFLiteEngine(private val context: Context) {

    // ── Audio / Model Constants ────────────────────────────────────────────
    companion object {
        private const val TAG = "WhisperEngine"

        const val SAMPLE_RATE   = 16_000
        const val WINDOW_SIZE   = 400        // 25 ms window
        const val N_FFT         = 512        // FFT size (power of 2)
        const val HOP_LENGTH    = 160        // 10 ms hop
        const val N_MELS        = 80
        const val N_FRAMES      = 3_000     // 30 s * 100 frames/s
        const val CHUNK_SAMPLES = SAMPLE_RATE * 30  // 480 000 samples
    }

    // ── State ──────────────────────────────────────────────────────────────
    private var interpreter: Interpreter? = null
    private val tokenizer   = WhisperTokenizer()
    private var hannWindow  = buildHannWindow()
    private var melFilters  = buildMelFilterbank()

    // ── Public API ─────────────────────────────────────────────────────────

    /** Load a .tflite model file and optional vocab.json from the same folder. */
    fun initialize(modelPath: String) {
        val modelFile = File(modelPath)
        require(modelFile.exists()) { "Model not found: $modelPath" }

        val opts = Interpreter.Options().apply { setNumThreads(4) }
        interpreter?.close()
        interpreter = Interpreter(modelFile, opts)

        // Try to load vocabulary from same directory
        val vocabFile = File(modelFile.parent, "vocab.json")
        if (vocabFile.exists()) tokenizer.load(vocabFile)
        else Log.w(TAG, "vocab.json not found alongside model. Using byte-level decoding.")

        logTensorShapes()
    }

    /** Transcribe an audio file. Returns decoded text. */
    fun transcribe(audioPath: String): String {
        val interp = interpreter ?: throw IllegalStateException("Engine not initialized.")

        // 1. Read WAV
        val pcm = readWavMono16k(audioPath)
        Log.i(TAG, "PCM samples: ${pcm.size}  (${pcm.size / SAMPLE_RATE.toFloat()} s)")
        if (pcm.size < 1_600) return ""   // < 0.1 s → skip

        // 2. Mel spectrogram
        val mel = computeLogMelSpectrogram(pcm)

        // 3. Pack into ByteBuffer  [1, N_MELS, N_FRAMES]
        val inputBuf = melToByteBuffer(mel)

        // 4. Run model + decode
        return runAndDecode(interp, inputBuf)
    }

    fun release() {
        interpreter?.close()
        interpreter = null
    }

    // ── Inference ──────────────────────────────────────────────────────────

    private fun runAndDecode(interp: Interpreter, inputBuf: ByteBuffer): String {
        val outTensor  = interp.getOutputTensor(0)
        val outShape   = outTensor.shape()
        val totalElems = outShape.fold(1) { acc, d -> acc * d }
        val outBuf     = ByteBuffer.allocateDirect(totalElems * 4).order(ByteOrder.nativeOrder())

        interp.run(inputBuf, outBuf)
        outBuf.rewind()

        val dtypeName = outTensor.dataType().name
        Log.i(TAG, "Output dtype=$dtypeName  shape=${outShape.contentToString()}")

        // ── Branch 1: integer output → direct token IDs ────────────────────
        return if (dtypeName.startsWith("INT")) {
            val tokens = IntArray(totalElems) { outBuf.int }
            Log.d(TAG, "Raw tokens (first 20): ${tokens.take(20)}")
            tokenizer.decode(tokens)
        }
        // ── Branch 2: float [1, seq, vocab] → argmax per position ─────────
        else if (outShape.size == 3) {
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
        // ── Branch 3: float [1, N] → treat values as token IDs ────────────
        else {
            val floats = FloatArray(totalElems) { outBuf.float }
            val tokens = IntArray(totalElems) { floats[it].roundToInt() }
            tokenizer.decode(tokens)
        }
    }

    // ── WAV Reader ─────────────────────────────────────────────────────────

    /**
     * Read a WAV file and return 16 kHz mono float PCM samples in [-1, 1].
     * Handles multi-channel files by averaging channels.
     * Resamples with linear interpolation if the file is not 16 kHz.
     */
    private fun readWavMono16k(path: String): FloatArray {
        val bytes = File(path).readBytes()
        if (bytes.size < 44) return FloatArray(0)

        // Parse RIFF header
        fun int16At(offset: Int) = ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
                                    (bytes[offset].toInt() and 0xFF)
        fun int32At(offset: Int) = ((bytes[offset + 3].toInt() and 0xFF) shl 24) or
                                   ((bytes[offset + 2].toInt() and 0xFF) shl 16) or
                                   ((bytes[offset + 1].toInt() and 0xFF) shl 8)  or
                                    (bytes[offset].toInt() and 0xFF)

        val numChannels   = int16At(22)
        val fileSampleRate = int32At(24)
        val bitsPerSample = int16At(34)
        val bytesPerSample = bitsPerSample / 8

        // Find 'data' chunk
        var dataStart = 44
        var dataSize  = bytes.size - 44
        var pos = 12
        while (pos + 8 <= bytes.size) {
            val id   = String(bytes, pos, 4, Charsets.US_ASCII)
            val size = int32At(pos + 4)
            if (id == "data") { dataStart = pos + 8; dataSize = size; break }
            pos += 8 + size.coerceAtLeast(0)
        }

        val numSamples = (dataSize / (numChannels * bytesPerSample))
            .coerceAtMost(CHUNK_SAMPLES)

        val mono = FloatArray(numSamples)
        for (s in 0 until numSamples) {
            var sum = 0f
            for (ch in 0 until numChannels) {
                val base = dataStart + (s * numChannels + ch) * bytesPerSample
                if (base + bytesPerSample > bytes.size) break
                val v = when (bytesPerSample) {
                    2 -> int16At(base).let { if (it >= 32768) it - 65536 else it }
                    1 -> (bytes[base].toInt() and 0xFF) - 128
                    else -> 0
                }
                sum += v / 32_768f
            }
            mono[s] = (sum / numChannels).coerceIn(-1f, 1f)
        }

        // Resample if needed (linear interpolation)
        if (fileSampleRate == SAMPLE_RATE) return mono
        Log.i(TAG, "Resampling from $fileSampleRate Hz to $SAMPLE_RATE Hz")
        val ratio  = fileSampleRate.toDouble() / SAMPLE_RATE
        val newLen = (mono.size / ratio).toInt()
        return FloatArray(newLen) { i ->
            val src = i * ratio
            val lo  = src.toInt().coerceIn(0, mono.size - 1)
            val hi  = (lo + 1).coerceIn(0, mono.size - 1)
            (mono[lo] + (mono[hi] - mono[lo]) * (src - lo)).toFloat()
        }
    }

    // ── Mel Spectrogram ────────────────────────────────────────────────────

    /**
     * Compute the log-mel spectrogram expected by Whisper.
     *
     * Steps:
     *  1. Pad / truncate PCM to 30 s
     *  2. For each frame: apply Hann window, run FFT, compute power spectrum
     *  3. Apply mel filterbank  (80 filters, 0–8 000 Hz)
     *  4. Log10 + clamp + normalize to ≈ [-1, 1]
     *
     * Returns Array<FloatArray> with shape [N_MELS][N_FRAMES].
     */
    private fun computeLogMelSpectrogram(pcm: FloatArray): Array<FloatArray> {
        // Pad to ensure we produce exactly N_FRAMES
        val paddedLen = (N_FRAMES - 1) * HOP_LENGTH + WINDOW_SIZE
        val padded = FloatArray(paddedLen)
        pcm.copyInto(padded, 0, 0, minOf(pcm.size, paddedLen))

        val nFreq  = N_FFT / 2 + 1
        val mel    = Array(N_MELS) { FloatArray(N_FRAMES) }
        val re     = DoubleArray(N_FFT)
        val im     = DoubleArray(N_FFT)

        for (frame in 0 until N_FRAMES) {
            val start = frame * HOP_LENGTH

            // Apply Hann window and pad to N_FFT
            for (n in 0 until N_FFT) {
                if (n < WINDOW_SIZE && (start + n) < paddedLen) {
                    re[n] = (padded[start + n] * hannWindow[n]).toDouble()
                } else {
                    re[n] = 0.0
                }
                im[n] = 0.0
            }

            // In-place FFT
            fft(re, im)

            // Power spectrum  |X[k]|²
            val power = FloatArray(nFreq) { k ->
                (re[k] * re[k] + im[k] * im[k]).toFloat()
            }

            // Apply mel filterbank
            for (m in 0 until N_MELS) {
                var e = 0f
                for (k in 0 until nFreq) e += melFilters[m][k] * power[k]
                mel[m][frame] = e
            }
        }

        // Log-mel + normalize (Whisper normalisation)
        //   log10(max(x, 1e-10))
        //   clamp to (max - 8) .. max
        //   scale to [-1, 1] by  (x + 4) / 4
        val logMel = Array(N_MELS) { m ->
            FloatArray(N_FRAMES) { t -> log10(mel[m][t].coerceAtLeast(1e-10f)) }
        }
        var globalMax = Float.NEGATIVE_INFINITY
        for (row in logMel) for (v in row) if (v > globalMax) globalMax = v

        for (m in 0 until N_MELS) {
            for (t in 0 until N_FRAMES) {
                logMel[m][t] = ((logMel[m][t].coerceAtLeast(globalMax - 8f)) + 4f) / 4f
            }
        }
        return logMel
    }

    /** Build the Hann window of length WINDOW_SIZE. */
    private fun buildHannWindow(): FloatArray =
        FloatArray(WINDOW_SIZE) { n -> (0.5 * (1.0 - cos(2.0 * PI * n / WINDOW_SIZE))).toFloat() }

    /**
     * Build the mel filterbank matrix [N_MELS × (N_FFT/2 + 1)].
     * Uses Hz→Mel conversion with triangular filters from 0 to 8 000 Hz.
     */
    private fun buildMelFilterbank(): Array<FloatArray> {
        fun hzToMel(hz: Double) = 2595.0 * log10(1.0 + hz / 700.0)
        fun melToHz(mel: Double) = 700.0 * (10.0.pow(mel / 2595.0) - 1.0)

        val fMin = 0.0; val fMax = 8_000.0
        val nFreq = N_FFT / 2 + 1

        val melMin = hzToMel(fMin)
        val melMax = hzToMel(fMax)

        // N_MELS + 2 equally-spaced mel points → Hz → FFT bin
        val melPts = DoubleArray(N_MELS + 2) { i -> melMin + i * (melMax - melMin) / (N_MELS + 1) }
        val bins   = IntArray(N_MELS + 2) { i ->
            floor(melToHz(melPts[i]) * nFreq / SAMPLE_RATE).toInt().coerceIn(0, nFreq - 1)
        }

        return Array(N_MELS) { m ->
            FloatArray(nFreq) { k ->
                val lo = bins[m]; val mid = bins[m + 1]; val hi = bins[m + 2]
                when {
                    k in lo until mid && mid > lo -> (k - lo).toFloat() / (mid - lo)
                    k in mid..hi    && hi  > mid  -> (hi - k).toFloat() / (hi  - mid)
                    else -> 0f
                }
            }
        }
    }

    /** Pack mel [N_MELS][N_FRAMES] into a float32 ByteBuffer with shape [1, N_MELS, N_FRAMES]. */
    private fun melToByteBuffer(mel: Array<FloatArray>): ByteBuffer {
        val buf = ByteBuffer.allocateDirect(N_MELS * N_FRAMES * 4).order(ByteOrder.nativeOrder())
        for (m in 0 until N_MELS) for (t in 0 until N_FRAMES) buf.putFloat(mel[m][t])
        buf.rewind()
        return buf
    }

    // ── FFT (Cooley-Tukey radix-2, in-place) ──────────────────────────────

    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        // Bit-reversal permutation
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i];     im[i] = im[j]; im[j] = t
            }
        }
        // Butterfly passes
        var len = 2
        while (len <= n) {
            val ang  = -2.0 * PI / len
            val wRe  = cos(ang);  val wIm = sin(ang)
            var i    = 0
            while (i < n) {
                var curRe = 1.0; var curIm = 0.0
                for (k in 0 until len / 2) {
                    val uRe = re[i + k];            val uIm = im[i + k]
                    val vRe = re[i+k+len/2]*curRe - im[i+k+len/2]*curIm
                    val vIm = re[i+k+len/2]*curIm + im[i+k+len/2]*curRe
                    re[i + k]         = uRe + vRe;  im[i + k]         = uIm + vIm
                    re[i + k + len/2] = uRe - vRe;  im[i + k + len/2] = uIm - vIm
                    val nRe = curRe*wRe - curIm*wIm
                    curIm = curRe*wIm + curIm*wRe;  curRe = nRe
                }
                i += len
            }
            len *= 2
        }
    }

    // ── Diagnostics ────────────────────────────────────────────────────────

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
