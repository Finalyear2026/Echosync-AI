# 🚀 EchoSync AI — Whisper Latency Optimization Guide

## The Problem

| Model | Current Latency | Target (Competitive) |
|---|---|---|
| `whisper-base.tflite` | **18 sec** | **1–3 sec** |
| `whisper-small.tflite` | **60 sec** | **3–6 sec** |
| `whisper-medium.tflite` | **128 sec** | **8–15 sec** |

You need a **6–10× speedup** across the board to compete with WhisperFlow-tier apps. This is achievable — your current pipeline has several major bottlenecks that, once addressed, will compound into massive gains.

---

## Root Cause Analysis of Your Current Pipeline

Your transcription flow currently does:

```
[Record WAV] → [Read entire WAV file from disk] → [Kotlin Mel Spectrogram (3000 frames × 257-bin FFT)]
             → [Pack into ByteBuffer] → [TFLite interpreter.run()] → [Decode tokens]
```

### Where the time goes (estimated breakdown for `whisper-base`, 18s total):

| Stage | Estimated Time | Why It's Slow |
|---|---|---|
| Mel spectrogram (Kotlin) | **8–12 sec** ⚠️ | 3,000 × radix-2 FFT in JVM, no SIMD, no native math |
| TFLite `interpreter.run()` | **5–8 sec** ⚠️ | CPU-only, FP32, no GPU/NNAPI delegate, no XNNPack tuning |
| WAV read + resampling | **0.5–1 sec** | Linear interpolation resampling in Kotlin |
| Token decoding | **< 0.1 sec** | Fast, not a bottleneck |
| Model loading (if cold) | **1–3 sec** | Already pre-loaded during recording ✅ |

> [!CAUTION]
> **The #1 bottleneck is your Mel spectrogram computation in Kotlin.** Your hand-written FFT runs 3,000 iterations of a 512-point Cooley-Tukey in JVM bytecode with zero SIMD vectorization. This alone likely accounts for 50–60% of your total latency.

---

## Optimization Strategies (Prioritized by Impact)

### 🏆 Priority 1: Move Mel Spectrogram to Native C++ (JNI)
**Impact: 5–8× faster preprocessing | Difficulty: Medium-High**

This is the single highest-impact change you can make. The Kotlin FFT in [WhisperTFLiteEngine.kt](file:///e:/current_work/project/echosync_ai/android/app/src/main/kotlin/com/echosync/echosync_ai/WhisperTFLiteEngine.kt#L205-L261) is your biggest bottleneck.

#### Why Kotlin/JVM is slow for this:
- **No SIMD:** ARM NEON intrinsics can process 4 floats simultaneously — the JVM cannot
- **No vectorized FFT:** Libraries like KISS FFT or pffft are 10–20× faster than hand-written radix-2
- **GC pressure:** Allocating `DoubleArray(512)` × 3000 frames creates GC churn
- **No compiler intrinsics:** JIT can't optimize trig functions the way a C++ compiler with `-O3 -march=armv8-a+simd` can

#### What to do:

1. **Create a C++ JNI library** (`whisper_preprocess.cpp`) that:
   - Takes raw PCM `float[]` as input (passed once across JNI)
   - Computes the full Mel spectrogram using **KISS FFT** or **pffft** (both are single-header, ~50KB)
   - Returns the packed `float[80][3000]` buffer directly as a `DirectByteBuffer`

2. **Estimated new preprocessing time:** 0.3–0.8 sec (down from 8–12 sec)

3. **Add to your `CMakeLists.txt`** (you already have CMake configured):
   ```cmake
   add_library(whisper_preprocess SHARED
       whisper_preprocess.cpp
       kiss_fft.c   # or pffft.c
   )
   target_compile_options(whisper_preprocess PRIVATE -O3 -march=armv8-a+simd)
   ```

4. **JNI interface:**
   ```kotlin
   // In WhisperTFLiteEngine.kt
   external fun nativeComputeMelSpectrogram(
       pcmData: FloatArray,
       pcmLength: Int
   ): ByteBuffer  // Returns [80 × 3000] float buffer, ready for TFLite

   companion object {
       init { System.loadLibrary("whisper_preprocess") }
   }
   ```

> [!TIP]
> If you don't want to write C++ from scratch, consider using **whisper.cpp**'s `log_mel_spectrogram()` function directly — it's already written, tested, and optimized with NEON intrinsics.

---

### 🏆 Priority 2: Enable TFLite Hardware Acceleration
**Impact: 2–4× faster inference | Difficulty: Low**

Your current code in [WhisperTFLiteEngine.kt line 53](file:///e:/current_work/project/echosync_ai/android/app/src/main/kotlin/com/echosync/echosync_ai/WhisperTFLiteEngine.kt#L53) uses bare CPU inference:

```kotlin
val opts = Interpreter.Options().apply { setNumThreads(4) }
```

You're leaving **massive** performance on the table.

#### Option A: GPU Delegate (Best for FP32/FP16 models)
```kotlin
// build.gradle.kts — add:
implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")
```

```kotlin
import org.tensorflow.lite.gpu.GpuDelegate

val opts = Interpreter.Options().apply {
    setNumThreads(4)
    addDelegate(GpuDelegate(GpuDelegate.Options().apply {
        setPrecisionLossAllowed(true)  // Allows FP16 — faster, minimal accuracy loss
        setInferencePreference(GpuDelegate.Options.INFERENCE_PREFERENCE_SUSTAINED_SPEED)
    }))
}
```

#### Option B: XNNPack (Best for quantized INT8 models)
```kotlin
// build.gradle.kts — add:
implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")
// XNNPack is built into TFLite but needs explicit opt-in for full acceleration:
```

```kotlin
val opts = Interpreter.Options().apply {
    setNumThreads(Runtime.getRuntime().availableProcessors().coerceIn(2, 8))
    setUseXNNPACK(true)  // Explicit enable
}
```

#### Option C: Fallback chain (Production-ready)
```kotlin
fun createInterpreterOptions(): Interpreter.Options {
    val opts = Interpreter.Options()
    val numCores = Runtime.getRuntime().availableProcessors().coerceIn(2, 8)
    opts.setNumThreads(numCores)

    // Try GPU first
    try {
        val gpuDelegate = GpuDelegate(GpuDelegate.Options().apply {
            setPrecisionLossAllowed(true)
        })
        opts.addDelegate(gpuDelegate)
        Log.i(TAG, "Using GPU delegate")
        return opts
    } catch (e: Exception) {
        Log.w(TAG, "GPU delegate unavailable: ${e.message}")
    }

    // Fallback to XNNPack CPU
    opts.setUseXNNPACK(true)
    Log.i(TAG, "Using XNNPack CPU with $numCores threads")
    return opts
}
```

> [!IMPORTANT]
> **Thread count matters a lot.** Android uses big.LITTLE architecture. Setting `setNumThreads(4)` on a device with 2 big + 6 little cores may schedule work on slow efficiency cores. Use `availableProcessors()` but cap it — too many threads causes thrashing.

---

### 🏆 Priority 3: Use Quantized Models (INT8 / FP16)
**Impact: 2–3× faster + 50–75% less RAM | Difficulty: Low**

Your current `.tflite` models are likely **FP32** (full precision). Quantized models run dramatically faster on mobile.

#### How to quantize your existing models:

```python
# Run once on your PC to convert FP32 → INT8 (dynamic range quantization)
import tensorflow as tf

converter = tf.lite.TFLiteConverter.from_saved_model("whisper-base")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
# For dynamic range quantization (easiest, no calibration data needed):
converter.target_spec.supported_types = [tf.float16]  # or tf.int8
tflite_model = converter.convert()

with open("whisper-base-fp16.tflite", "wb") as f:
    f.write(tflite_model)
```

| Quantization | Speed Gain | Accuracy Impact | Best Delegate |
|---|---|---|---|
| **FP16** (half-precision) | ~2× | Negligible | GPU Delegate |
| **INT8** (dynamic range) | ~2–3× | Very small (<1% WER) | XNNPack CPU |
| **INT8** (full integer, calibrated) | ~3–4× | Small (~1–2% WER) | XNNPack / NNAPI |

> [!TIP]
> **Quick win:** Even without re-converting models, just enabling the GPU delegate with `setPrecisionLossAllowed(true)` will internally use FP16 arithmetic for FP32 models.

---

### 🏆 Priority 4: Streaming Architecture with VAD
**Impact: Perceived 10× faster (real-time feel) | Difficulty: High**

Instead of recording → stop → process entire 30s audio, switch to **streaming chunked inference**:

```
[Mic] → [VAD: Is this speech?] → [Buffer speech chunks] → [Transcribe 3-5s segments]
                                                            → [Show partial results live]
```

#### Implementation outline:

1. **Add Silero VAD** (tiny, ~1MB TFLite model, <5ms per frame):
   - Detects speech vs silence in real-time
   - Skip processing silent segments entirely
   - Prevents Whisper hallucinations on silence ("music", "thanks for watching")

2. **Chunked inference:**
   ```
   While recording:
     - Accumulate PCM in a ring buffer
     - When VAD detects end-of-speech (or buffer hits ~5 seconds of speech):
       → Pad to 30s (Whisper expects fixed input)
       → Run inference on this chunk
       → Show partial result to user immediately
       → Continue recording
   ```

3. **Result merging:**
   - Maintain a rolling context of the last transcript segment
   - Pass it as a prompt to the next chunk for coherency

#### Why this is a game-changer:
- User sees text appearing **while still speaking** — feels instant
- Each chunk processes ~5s of audio instead of 30s → **6× less compute per inference**
- Silence is never processed → saves 30–70% of total compute for typical speech

---

### Priority 5: Consider Switching to whisper.cpp (Nuclear Option)
**Impact: 5–15× overall speedup | Difficulty: High**

If you want to truly compete with WhisperFlow, the industry standard for mobile Whisper is **NOT TFLite** — it's [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

#### Why whisper.cpp beats TFLite for Whisper specifically:

| Feature | Your TFLite Pipeline | whisper.cpp |
|---|---|---|
| Mel spectrogram | Kotlin (JVM, slow) | C++ with ARM NEON (blazing fast) |
| FFT | Hand-written radix-2 | Optimized pffft with SIMD |
| Model format | `.tflite` (generic) | `.gguf` (whisper-optimized) |
| Quantization | FP32 (your current) | q4_0, q5_0, q8_0 (native support) |
| GPU support | TFLite GPU delegate | Vulkan backend |
| Decoder | TFLite output → argmax | Beam search, greedy, with KV-cache |
| VAD | None | Built-in energy-based VAD |
| Streaming | Not supported | Supported via `whisper_full_with_state` |

#### Expected performance with whisper.cpp:

| Model | whisper.cpp (q5_0, 4 threads) | Your Current |
|---|---|---|
| `tiny` | ~0.5 sec | N/A |
| `base` | ~1.5 sec | 18 sec |
| `small` | ~4 sec | 60 sec |
| `medium` | ~12 sec | 128 sec |

#### Integration path:
- You already have `whisper_flutter_new` in your [pubspec.yaml](file:///e:/current_work/project/echosync_ai/pubspec.yaml#L37) — this wraps whisper.cpp!
- Your [TranscriptionService](file:///e:/current_work/project/echosync_ai/lib/services/transcription_service.dart#L63-L78) already has a GGML fallback path
- **You could use whisper.cpp for speed-critical transcription and keep TFLite as a fallback**

> [!WARNING]
> whisper.cpp uses `.gguf` model format, not `.tflite`. You'd need to download separate GGUF model files. However, quantized GGUF models are often **smaller** than their FP32 TFLite equivalents.

---

### Priority 6: Use Smaller, Distilled Models
**Impact: 2–5× faster (model dependent) | Difficulty: Low**

If accuracy on `whisper-base` is acceptable, you should also consider:

| Model | Params | vs. base Speed | vs. base Accuracy |
|---|---|---|---|
| `whisper-tiny` | 39M | **3× faster** | Slightly worse |
| `distil-small.en` | 166M | ~same as base | **Better** (distilled from large) |
| `whisper-base` | 74M | Baseline | Baseline |
| `whisper-small` | 244M | 3× slower | Better |

> [!TIP]
> **Distil-Whisper models** (from HuggingFace) are trained by distilling `whisper-large-v3` into smaller architectures. `distil-small.en` gives you near-large accuracy at base-model speed. This is what competitive apps use.

---

### Priority 7: Pipeline-Level Optimizations
**Impact: 1.5–2× cumulative | Difficulty: Low**

These are quick wins in your existing Kotlin code:

#### 7a. Don't re-read WAV from disk
Your current flow writes audio to a WAV file, then reads it back:
```
Record → save to WAV file → read WAV from disk → parse header → extract PCM
```

**Fix:** Keep the raw PCM `FloatArray` in memory from the recorder. Skip the file I/O entirely for transcription.

#### 7b. Pre-compute and cache constants
In [WhisperTFLiteEngine.kt](file:///e:/current_work/project/echosync_ai/android/app/src/main/kotlin/com/echosync/echosync_ai/WhisperTFLiteEngine.kt#L44-L46), you already initialize `hannWindow` and `melFilters` once — good. But you re-allocate `re` and `im` arrays every call:

```kotlin
// Current (line 214-215): allocates inside computeLogMelSpectrogram()
val re = DoubleArray(N_FFT)
val im = DoubleArray(N_FFT)
```

**Fix:** Make these class-level fields, reuse them:
```kotlin
private val fftRe = DoubleArray(N_FFT)
private val fftIm = DoubleArray(N_FFT)
```

#### 7c. Use Float instead of Double in FFT
Your FFT uses `DoubleArray` (64-bit) but TFLite only needs `Float` (32-bit). Using `FloatArray` halves memory bandwidth and can be ~30% faster on mobile:

```kotlin
// Change fft() to use FloatArray instead of DoubleArray
private fun fft(re: FloatArray, im: FloatArray) { ... }
```

#### 7d. Optimize thread count for the device
```kotlin
// Instead of hardcoded 4:
val opts = Interpreter.Options().apply {
    setNumThreads(Runtime.getRuntime().availableProcessors().coerceIn(2, 8))
}
```

#### 7e. Stop unloading models after every transcription
In your [pipeline_service.dart line 280](file:///e:/current_work/project/echosync_ai/lib/services/pipeline_service.dart#L279-L281):
```dart
finally {
    // UNLOAD MODELS as soon as processing is done to free RAM
    await _unloadAllModels();
}
```

This means every transcription requires a full model reload (1–3 sec penalty). Consider keeping the model warm for a configurable timeout (e.g., 30 seconds) instead of immediate unload.

---

## Recommended Implementation Roadmap

### Phase 1: Quick Wins (1–2 days) → Expected: **2–3× speedup**
- [ ] Add GPU delegate / XNNPack to TFLite options (Priority 2)
- [ ] Switch FFT from Double to Float (Priority 7c)
- [ ] Pre-allocate FFT buffers (Priority 7b)
- [ ] Optimize thread count (Priority 7d)
- [ ] Keep models warm instead of unloading (Priority 7e)

### Phase 2: Major Gains (3–5 days) → Expected: **5–8× total speedup**
- [ ] Move Mel spectrogram to C++ JNI with KISS FFT (Priority 1)
- [ ] Quantize models to FP16 (Priority 3)
- [ ] Test distil-small.en as an alternative model (Priority 6)

### Phase 3: Competitive Edge (1–2 weeks) → Expected: **10–15× total speedup**
- [ ] Implement streaming chunked inference with VAD (Priority 4)
- [ ] Evaluate full migration to whisper.cpp (Priority 5)
- [ ] Add Silero VAD for intelligent silence skipping

### Phase 4: Polish
- [ ] Benchmark on multiple devices (Snapdragon, MediaTek, Exynos)
- [ ] A/B test accuracy of quantized vs. full-precision models
- [ ] Implement adaptive model selection based on device capability

---

## Benchmark Targets After Full Optimization

| Model | Current | After Phase 1 | After Phase 2 | After Phase 3 |
|---|---|---|---|---|
| `whisper-base` | 18s | ~8s | ~2–3s | **~1–2s** |
| `whisper-small` | 60s | ~25s | ~6–10s | **~3–5s** |
| `whisper-medium` | 128s | ~55s | ~15–25s | **~8–12s** |

> [!IMPORTANT]
> **The combination of C++ Mel spectrogram + GPU delegate + FP16 quantization alone should get you to ~3s for base model** — which is competitive territory. Streaming VAD on top of that makes it *feel* instant.

---

## What WhisperFlow Likely Does

Based on competitive analysis, apps like WhisperFlow and Wispr Flow typically:

1. ✅ Use **whisper.cpp** (not TFLite) with GGUF quantized models
2. ✅ Run **q5_0 or q8_0 quantization** (not FP32)
3. ✅ Process audio in **streaming chunks** with VAD
4. ✅ Use **ARM NEON SIMD** for all preprocessing
5. ✅ Keep models **warm in memory** (no load/unload per transcription)
6. ✅ Use the **smallest model that meets accuracy requirements** (tiny/base for real-time, small for quality)
7. ✅ Show **partial transcription results** as they become available

You have the foundation — your transcription accuracy is already correct. Now it's purely an engineering optimization problem. 🎯
