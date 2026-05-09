import 'package:flutter/foundation.dart';
import '../transcription_service.dart';
import 'asr_engine.dart';

/// TFLite Whisper inference engine — Batch mode only.
///
/// [transcribeWindow] always throws [UnsupportedError] because the native
/// WhisperTFLiteEngine.kt is hardcoded to a fixed 30-second input window
/// (N_FRAMES = 3000). Use [GgmlAsrEngine] for real-time mode.
class TfliteAsrEngine implements AsrEngine {
  final TranscriptionService _transcription;

  TfliteAsrEngine({required TranscriptionService transcription})
      : _transcription = transcription;

  @override
  Future<void> initialize(String modelPath, String modelName) async {
    await _transcription.initialize(
      model: modelName,
      modelPath: modelPath,
      useWhisperCpp: false,
    );
    debugPrint('TfliteAsrEngine: Initialized with model=$modelName @ $modelPath');
  }

  @override
  Future<String> transcribeFile(String filePath) async {
    return _transcription.transcribe(filePath);
  }

  @override
  Future<String> transcribeWindow(Uint8List pcm16kWav) {
    throw UnsupportedError(
      'TfliteAsrEngine does not support real-time windowed transcription. '
      'Switch to GGML engine (whisper.cpp) for Real-time mode.',
    );
  }

  @override
  Future<void> dispose() async {
    await _transcription.dispose();
  }
}
