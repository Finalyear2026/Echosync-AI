# Whisper Latency Optimization — Implementation Tracker

## Phase 1: Quick Wins
- [x] **Change 1:** Enable GPU Delegate + XNNPack acceleration in TFLite
- [x] **Change 2:** Switch FFT from Double to Float + pre-allocate buffers
- [x] **Change 3:** Optimize thread count for device
- [x] **Change 4:** Keep models warm instead of unloading after every transcription

## Phase 2: Major Gains
- [x] **Change 5:** Move Mel spectrogram to C++ JNI with KISS FFT
- [x] **Change 6:** Quantize models to FP16
- [x] **Change 7:** Test distil-small.en as alternative model

## Phase 3: Competitive Edge
- [/] **Change 8:** Implement streaming chunked inference with VAD
- [ ] **Change 9:** Evaluate whisper.cpp migration
