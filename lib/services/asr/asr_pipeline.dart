import 'package:flutter/foundation.dart';
import '../../models/processing_state.dart';
import '../../models/transcription_result.dart';

/// Abstract interface for an ASR pipeline session.
///
/// [partialResults] emits incremental transcript text in real-time mode and
/// a single final-text event in batch mode.
abstract class AsrPipeline {
  Stream<String> get partialResults;

  Future<void> start();

  Future<TranscriptionResult> stop({
    ValueChanged<ProcessingStage>? onStageChanged,
  });

  Future<void> cancel();
}
