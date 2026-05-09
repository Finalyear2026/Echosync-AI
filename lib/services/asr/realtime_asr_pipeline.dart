import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/processing_state.dart';
import '../../models/transcription_result.dart';
import '../rolling_pcm_buffer.dart';
import '../streaming_audio_service.dart';
import 'asr_engine.dart';
import 'asr_pipeline.dart';

/// Real-time ASR pipeline using a sliding window over a [RollingPcmBuffer].
///
/// Audio Design:
///   - Rolling buffer grows up to 10 s (160 k samples)
///   - A periodic timer triggers inference every 2 s on the FULL buffer
///   - On eviction the committed hypothesis is appended to [_sessionText]
///
/// Backpressure (Fix 2):
///   - Only one inference runs at a time (_isEngineRunning flag)
///   - Audio continues accumulating while the engine is busy
///   - When the engine finishes it immediately re-runs if new audio arrived
///
/// Diff Algorithm (Fix 1 + Fix 2 of plan):
///   - Results are compared word-by-word on normalized text (no punct / lower)
///   - Only the confirmed new suffix is added to the display
///   - Words that have been stable for 2+ consecutive cycles are committed
class RealtimeAsrPipeline implements AsrPipeline {
  final AsrEngine _engine;
  final StreamingAudioService _audioService;

  final StreamController<String> _partialCtrl =
      StreamController<String>.broadcast();
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _inferenceTimer;

  final RollingPcmBuffer _buffer = RollingPcmBuffer();

  bool _isEngineRunning = false;
  bool _pendingInference = false;

  String _sessionText = '';
  String _prevHypothesis = '';
  int _stableCycles = 0;
  static const int _commitCycles = 2;

  static const Duration _triggerInterval = Duration(milliseconds: 1500);
  static const int _maxInferenceSamples = 64000; // 4 s at 16 kHz — keeps
  // per-cycle inference time predictable regardless of buffer age
  static const int _minSamplesBeforeInference = 8000; // 0.5 s

  RealtimeAsrPipeline({
    required AsrEngine engine,
    required StreamingAudioService audioService,
  }) : _engine = engine,
       _audioService = audioService;

  @override
  Stream<String> get partialResults => _partialCtrl.stream;

  @override
  Future<void> start() async {
    _sessionText = '';
    _prevHypothesis = '';
    _stableCycles = 0;
    _buffer.clear();
    _isEngineRunning = false;
    _pendingInference = false;

    final rawStream = await _audioService.startStream();
    _audioSub = rawStream.listen(
      (chunk) => _buffer.append(chunk),
      onError: (Object e) =>
          debugPrint('RealtimeAsrPipeline: Audio stream error: $e'),
    );

    _inferenceTimer =
        Timer.periodic(_triggerInterval, (_) => _triggerInference());

    debugPrint('RealtimeAsrPipeline: Started');
  }

  @override
  Future<TranscriptionResult> stop({
    ValueChanged<ProcessingStage>? onStageChanged,
  }) async {
    _inferenceTimer?.cancel();
    _inferenceTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _audioService.stop();

    onStageChanged?.call(ProcessingStage.transcribing);

    // Await any running inference
    if (_isEngineRunning) {
      await _waitForEngine();
    }

    // Final inference on remaining buffer
    if (!_buffer.isEmpty) {
      await _runInference(isFinal: true);
    }

    // Commit anything left in hypothesis
    _commitHypothesis(_prevHypothesis);

    if (!_partialCtrl.isClosed) await _partialCtrl.close();

    final finalText = _sessionText.trim();
    final startTime = DateTime.now();

    onStageChanged?.call(ProcessingStage.completed);

    return TranscriptionResult(
      rawText: finalText,
      formattedText: finalText,
      language: 'auto',
      audioDuration: _buffer.duration,
      processingTime: DateTime.now().difference(startTime),
      timestamp: DateTime.now(),
      wasNoiseFiltered: false,
      wasFormatted: false,
    );
  }

  @override
  Future<void> cancel() async {
    _inferenceTimer?.cancel();
    await _audioSub?.cancel();
    await _audioService.stop();
    if (!_partialCtrl.isClosed) await _partialCtrl.close();
    debugPrint('RealtimeAsrPipeline: Cancelled');
  }

  // ── Inference control ───────────────────────────────────────────────────

  void _triggerInference() {
    if (_isEngineRunning) {
      _pendingInference = true;
      return;
    }
    if (_buffer.length < _minSamplesBeforeInference) return;
    _runInference(); // intentionally unawaited — backpressure via _isEngineRunning
  }

  Future<void> _runInference({bool isFinal = false}) async {
    if (_buffer.isOverfull) {
      _commitHypothesis(_prevHypothesis);
      _buffer.evictOldest();
      _prevHypothesis = '';
      _stableCycles = 0;
    }

    _isEngineRunning = true;
    _pendingInference = false;

    final snapshot = _buffer.snapshotWindow(_maxInferenceSamples);
    try {
      final newResult = await _engine.transcribeWindow(snapshot);
      if (!_partialCtrl.isClosed) {
        _processResult(newResult, isFinal: isFinal);
      }
    } catch (e) {
      debugPrint('RealtimeAsrPipeline: Inference error: $e');
    } finally {
      _isEngineRunning = false;
      if (_pendingInference && !isFinal) {
        _pendingInference = false;
        await _runInference();
      }
    }
  }

  // ── Result processing ────────────────────────────────────────────────────

  void _processResult(String newResult, {bool isFinal = false}) {
    if (newResult.trim().isEmpty) return;

    final normPrev = _normalize(_prevHypothesis);
    final normNew = _normalize(newResult);

    if (normPrev == normNew) {
      _stableCycles++;
    } else {
      _stableCycles = 0;
    }

    if (isFinal || _stableCycles >= _commitCycles) {
      _commitHypothesis(newResult);
      _prevHypothesis = '';
      _stableCycles = 0;
    } else {
      _prevHypothesis = newResult;
    }

    final display = [_sessionText, if (!isFinal) newResult]
        .where((s) => s.isNotEmpty)
        .join(' ');
    _partialCtrl.add(display.trim());
  }

  void _commitHypothesis(String hypothesis) {
    if (hypothesis.trim().isEmpty) return;
    final suffix = _extractNewSuffix(_sessionText, hypothesis);
    if (suffix.isNotEmpty) {
      _sessionText =
          (_sessionText.isEmpty ? suffix : '$_sessionText $suffix').trim();
    }
  }

  // ── Diff helpers ─────────────────────────────────────────────────────────

  /// Extracts the portion of [newText] that is genuinely new compared to
  /// [existing], using a normalized word-level common-prefix check.
  static String _extractNewSuffix(String existing, String newText) {
    if (existing.isEmpty) return newText.trim();

    final normExisting =
        _normalize(existing).split(' ').where((w) => w.isNotEmpty).toList();
    final normNew =
        _normalize(newText).split(' ').where((w) => w.isNotEmpty).toList();
    final origNew =
        newText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    int stableLen = 0;
    final limit = min(normExisting.length, normNew.length);
    for (int i = 0; i < limit; i++) {
      if (normExisting[i] == normNew[i]) {
        stableLen = i + 1;
      } else {
        break;
      }
    }

    if (stableLen >= origNew.length) return '';
    return origNew.skip(stableLen).join(' ');
  }

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[^\w\s]"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ── Utilities ────────────────────────────────────────────────────────────

  Future<void> _waitForEngine() async {
    while (_isEngineRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
