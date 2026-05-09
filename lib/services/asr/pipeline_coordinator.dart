import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/processing_state.dart';
import '../../models/transcription_result.dart';
import '../model_manager_service.dart';
import '../pipeline_service.dart';
import '../settings_service.dart';
import '../streaming_audio_service.dart';
import '../transcription_service.dart';
import 'asr_pipeline.dart';
import 'pipeline_factory.dart';

/// Owns the currently active [AsrPipeline] and wires it to [AppProvider].
///
/// On [startRecording] it reads current settings, creates the right pipeline
/// via [PipelineFactory], and pipes [partialResults] into [partialStream].
/// On [stopRecording] it tears down the pipeline and returns the final result.
class PipelineCoordinator {
  final PipelineService _batchPipeline;
  final SettingsService _settings;
  final ModelManagerService _modelManager;
  final StreamingAudioService _streamingAudio;

  AsrPipeline? _activePipeline;
  TranscriptionService? _realtimeTranscription;
  StreamSubscription<String>? _partialSub;
  final StreamController<String> _partialCtrl =
      StreamController<String>.broadcast();

  PipelineCoordinator({
    required PipelineService batchPipeline,
    required SettingsService settings,
    required ModelManagerService modelManager,
    required StreamingAudioService streamingAudio,
  }) : _batchPipeline = batchPipeline,
       _settings = settings,
       _modelManager = modelManager,
       _streamingAudio = streamingAudio;

  Stream<String> get partialStream => _partialCtrl.stream;

  Future<void> startRecording() async {
    final s = _settings.getSettings();
    final isRealtime = s.processingMode == ProcessingMode.realtime;
    final useGgml = s.useWhisperCppEngine;

    String modelPath = '';
    String modelName = s.whisperModel;
    String sherpaModelDir = '';

    if (isRealtime) {
      const sherpaKey = 'sherpa-onnx-streaming-en-20m';
      if (await _modelManager.isModelDownloaded(sherpaKey)) {
        sherpaModelDir = await _modelManager.getModelPath(sherpaKey);
      }
      debugPrint('PipelineCoordinator: Sherpa model dir = $sherpaModelDir');
    }

    _activePipeline = PipelineFactory.create(
      mode: s.processingMode,
      useGgml: useGgml,
      batchPipelineService: _batchPipeline,
      streamingAudio: _streamingAudio,
      realtimeTranscription: _realtimeTranscription ?? TranscriptionService(),
      modelPath: modelPath,
      modelName: modelName,
      sherpaModelDir: sherpaModelDir,
    );

    _partialSub = _activePipeline!.partialResults.listen(
      (text) {
        if (!_partialCtrl.isClosed) _partialCtrl.add(text);
      },
      onError: (Object e) =>
          debugPrint('PipelineCoordinator: Partial stream error: $e'),
    );

    await _activePipeline!.start();
    debugPrint(
      'PipelineCoordinator: Started '
      '${s.processingMode == ProcessingMode.realtime ? "Realtime/GGML" : "Batch"} pipeline',
    );
  }

  Future<TranscriptionResult> stopRecording({
    ValueChanged<ProcessingStage>? onStageChanged,
  }) async {
    if (_activePipeline == null) {
      throw StateError('PipelineCoordinator: No active pipeline to stop');
    }
    final result = await _activePipeline!.stop(onStageChanged: onStageChanged);
    await _cleanup();
    return result;
  }

  Future<void> cancelRecording() async {
    await _activePipeline?.cancel();
    await _cleanup();
  }

  Future<void> _cleanup() async {
    await _partialSub?.cancel();
    _partialSub = null;
    _activePipeline = null;
    await _realtimeTranscription?.dispose();
    _realtimeTranscription = null;
  }

  Future<void> dispose() async {
    await cancelRecording();
    await _partialCtrl.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _mapWhisperKey(String model) {
    final m = model.toLowerCase();
    if (m.contains('small')) return 'whisper-small';
    if (m.contains('medium')) return 'whisper-medium';
    if (m.contains('v3') || m.contains('turbo')) return 'whisper-large-v3-turbo';
    return 'whisper-base';
  }
}
