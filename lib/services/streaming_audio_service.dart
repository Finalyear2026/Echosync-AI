import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Wraps the [record] package's stream API to deliver raw PCM-16 bytes
/// at 16 kHz mono — the format expected by both the RollingPcmBuffer
/// and the whisper.cpp engine.
class StreamingAudioService {
  AudioRecorder? _recorder;
  bool _isStreaming = false;

  bool get isStreaming => _isStreaming;

  Future<void> initialize() async {
    _recorder ??= AudioRecorder();
  }

  Future<bool> hasPermission() async {
    await initialize();
    return _recorder!.hasPermission();
  }

  /// Starts the microphone and returns raw PCM-16 bytes at 16 kHz mono.
  /// [record] v6+ returns a [Future<Stream<Uint8List>>], so this method is async.
  Future<Stream<Uint8List>> startStream() async {
    if (_isStreaming) {
      throw StateError('StreamingAudioService: already streaming');
    }

    _recorder ??= AudioRecorder();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );

    final rawStream = await _recorder!.startStream(config);
    _isStreaming = true;

    debugPrint('StreamingAudioService: Stream started at 16 kHz PCM-16 mono');

    return rawStream.handleError((Object e) {
      debugPrint('StreamingAudioService: Stream error: $e');
    });
  }

  Future<void> stop() async {
    if (_isStreaming) {
      await _recorder?.stop();
      _isStreaming = false;
      debugPrint('StreamingAudioService: Stopped');
    }
  }

  Future<void> dispose() async {
    await stop();
    _recorder?.dispose();
    _recorder = null;
  }
}
