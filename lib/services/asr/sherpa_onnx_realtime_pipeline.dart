import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../models/processing_state.dart';
import '../../models/transcription_result.dart';
import '../streaming_audio_service.dart';
import 'asr_pipeline.dart';

/// Real-time ASR pipeline backed by sherpa-onnx Zipformer Transducer.
///
/// Processes every audio packet from [StreamingAudioService] inline —
/// no timer, no rolling buffer, no file I/O. Partials appear within
/// ~150-200ms of speech.
///
/// Model directory must contain:
///   encoder-epoch-99-avg-1.int8.onnx
///   decoder-epoch-99-avg-1.int8.onnx
///   joiner-epoch-99-avg-1.int8.onnx
///   tokens.txt
class SherpaOnnxRealtimePipeline implements AsrPipeline {
  final String _modelDir;
  final StreamingAudioService _audioService;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSub;

  final StreamController<String> _partialCtrl =
      StreamController<String>.broadcast();

  String _sessionText = '';
  final DateTime _startTime = DateTime.now();

  static const int _sampleRate = 16000;

  SherpaOnnxRealtimePipeline({
    required String modelDir,
    required StreamingAudioService audioService,
  })  : _modelDir = modelDir,
        _audioService = audioService;

  @override
  Stream<String> get partialResults => _partialCtrl.stream;

  @override
  Future<void> start() async {
    sherpa.initBindings();

    final dir = await _resolveModelDir(_modelDir);
    debugPrint('SherpaOnnxRealtimePipeline: Using model dir = $dir');

    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$dir/encoder-epoch-99-avg-1.onnx',
          decoder: '$dir/decoder-epoch-99-avg-1.onnx',
          joiner: '$dir/joiner-epoch-99-avg-1.onnx',
        ),
        tokens: '$dir/tokens.txt',
        numThreads: 4,
        provider: 'cpu',
        debug: false,
        // modelType: 'zipformer2',
      ),
      decodingMethod: 'greedy_search',
      maxActivePaths: 4,
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 300,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();

    debugPrint('SherpaOnnxRealtimePipeline: Recognizer created, starting mic');

    final rawStream = await _audioService.startStream();
    _audioSub = rawStream.listen(
      _onAudioChunk,
      onError: (Object e) =>
          debugPrint('SherpaOnnxRealtimePipeline: Audio stream error: $e'),
    );
  }

  void _onAudioChunk(Uint8List data) {
    if (_recognizer == null || _stream == null) return;

    final float32 = _int16BytesToFloat32(data);
    _stream!.acceptWaveform(samples: float32, sampleRate: _sampleRate);

    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }

    final partial = _recognizer!.getResult(_stream!).text.trim();

    final display = [
      if (_sessionText.isNotEmpty) _sessionText,
      if (partial.isNotEmpty) partial,
    ].join(' ');

    if (!_partialCtrl.isClosed && display.isNotEmpty) {
      _partialCtrl.add(display);
    }

    if (_recognizer!.isEndpoint(_stream!)) {
      if (partial.isNotEmpty) {
        _sessionText =
            [if (_sessionText.isNotEmpty) _sessionText, partial].join(' ');
      }
      _recognizer!.reset(_stream!);
    }
  }

  @override
  Future<TranscriptionResult> stop({
    ValueChanged<ProcessingStage>? onStageChanged,
  }) async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _audioService.stop();

    onStageChanged?.call(ProcessingStage.transcribing);

    if (_recognizer != null && _stream != null) {
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      final finalPartial = _recognizer!.getResult(_stream!).text.trim();
      if (finalPartial.isNotEmpty) {
        _sessionText = [
          if (_sessionText.isNotEmpty) _sessionText,
          finalPartial,
        ].join(' ');
      }

      _stream!.free();
      _stream = null;
      _recognizer!.free();
      _recognizer = null;
    }

    if (!_partialCtrl.isClosed) await _partialCtrl.close();

    debugPrint(
      'SherpaOnnxRealtimePipeline: Final text = "$_sessionText"',
    );

    final processingTime = DateTime.now().difference(_startTime);

    return TranscriptionResult(
      rawText: _sessionText,
      formattedText: _sessionText,
      language: 'en',
      audioDuration: Duration.zero,
      processingTime: processingTime,
      timestamp: DateTime.now(),
      wasNoiseFiltered: false,
      wasFormatted: false,
    );
  }

  @override
  Future<void> cancel() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _audioService.stop();
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    if (!_partialCtrl.isClosed) await _partialCtrl.close();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Float32List _int16BytesToFloat32(Uint8List bytes) {
    final samples = Float32List(bytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      final raw = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
      samples[i] = (raw >= 0x8000 ? raw - 0x10000 : raw) / 32768.0;
    }
    return samples;
  }

  /// Resolves the directory that directly contains the encoder ONNX file.
  ///
  /// Handles two common zip extraction layouts:
  ///   a) Files at root of [base]
  ///   b) Files inside a single sub-folder of [base] (common when the zip
  ///      was created by wrapping a top-level named folder)
  static Future<String> _resolveModelDir(String base) async {
    final encoder = File('$base/encoder-epoch-99-avg-1.onnx');
    if (encoder.existsSync()) return base;

    final dir = Directory(base);
    if (!dir.existsSync()) return base;

    for (final entry in dir.listSync()) {
      if (entry is Directory) {
        final nested = File('${entry.path}/encoder-epoch-99-avg-1.onnx');
        if (nested.existsSync()) return entry.path;
      }
    }
    return base;
  }
}
