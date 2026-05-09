import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../transcription_service.dart';
import 'asr_engine.dart';

/// GGML / whisper.cpp inference engine.
///
/// For batch use [transcribeFile] (file path passed directly to whisper).
/// For real-time use [transcribeWindow]: the WAV bytes are written to a single
/// reused temp file (no per-cycle inode allocation) then transcribed.
class GgmlAsrEngine implements AsrEngine {
  final TranscriptionService _transcription;
  String? _tempChunkPath;

  GgmlAsrEngine({required TranscriptionService transcription})
      : _transcription = transcription;

  @override
  Future<void> initialize(String modelPath, String modelName) async {
    await _transcription.initialize(
      model: modelName,
      modelPath: modelPath,
      useWhisperCpp: true,
    );
    debugPrint('GgmlAsrEngine: Initialized with model=$modelName @ $modelPath');
  }

  @override
  Future<String> transcribeFile(String filePath) async {
    return _transcription.transcribe(filePath, language: 'en', threads: 6);
  }

  @override
  Future<String> transcribeWindow(Uint8List pcm16kWav) async {
    final path = await _resolveTempPath();
    await File(path).writeAsBytes(pcm16kWav, flush: true);
    return _transcription.transcribe(
      path,
      language: 'en',
      speedUp: true,
      threads: 6,
    );
  }

  Future<String> _resolveTempPath() async {
    if (_tempChunkPath != null) return _tempChunkPath!;
    final dir = await getTemporaryDirectory();
    _tempChunkPath = '${dir.path}/echosync_realtime_chunk.wav';
    return _tempChunkPath!;
  }

  @override
  Future<void> dispose() async {
    await _transcription.dispose();
    if (_tempChunkPath != null) {
      try {
        final f = File(_tempChunkPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _tempChunkPath = null;
    }
  }
}
