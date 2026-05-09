import 'dart:typed_data';

/// Abstract interface for a speech-recognition inference engine.
///
/// [transcribeFile] is used by the Batch pipeline (complete audio file).
/// [transcribeWindow] is used by the Real-time pipeline (rolling PCM window,
/// GGML engine only — TFLite implementation throws [UnsupportedError]).
abstract class AsrEngine {
  Future<void> initialize(String modelPath, String modelName);
  Future<String> transcribeFile(String filePath);
  Future<String> transcribeWindow(Uint8List pcm16kWav);
  Future<void> dispose();
}
