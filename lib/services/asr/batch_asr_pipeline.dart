import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/processing_state.dart';
import '../../models/transcription_result.dart';
import '../pipeline_service.dart';
import 'asr_pipeline.dart';

/// Batch ASR pipeline — delegates entirely to the existing [PipelineService].
///
/// Emits one [partialResults] event when transcription is complete, carrying
/// the final text so the UI StreamBuilder updates once.
class BatchAsrPipeline implements AsrPipeline {
  final PipelineService _pipeline;
  final StreamController<String> _partialCtrl =
      StreamController<String>.broadcast();

  BatchAsrPipeline(this._pipeline);

  @override
  Stream<String> get partialResults => _partialCtrl.stream;

  @override
  Future<void> start() async {
    await _pipeline.startRecording();
  }

  @override
  Future<TranscriptionResult> stop({
    ValueChanged<ProcessingStage>? onStageChanged,
  }) async {
    final result = await _pipeline.stopAndProcess(
      onStageChanged: onStageChanged,
    );
    if (!_partialCtrl.isClosed) {
      _partialCtrl.add(result.displayText);
    }
    return result;
  }

  @override
  Future<void> cancel() async {
    await _pipeline.cancelRecording();
    if (!_partialCtrl.isClosed) await _partialCtrl.close();
  }
}
