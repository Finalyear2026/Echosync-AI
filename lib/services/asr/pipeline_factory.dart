import '../../models/processing_state.dart';
import '../pipeline_service.dart';
import '../streaming_audio_service.dart';
import '../transcription_service.dart';
import 'asr_pipeline.dart';
import 'batch_asr_pipeline.dart';
import 'ggml_asr_engine.dart';
import 'realtime_asr_pipeline.dart';
import 'sherpa_onnx_realtime_pipeline.dart';

/// Assembles the correct [AsrPipeline] for a given [ProcessingMode] and
/// engine flag, enforcing the constraint that Real-time mode requires GGML.
///
/// Valid combinations:
///   batch   + GGML   → BatchAsrPipeline(GgmlAsrEngine)
///   batch   + TFLite → BatchAsrPipeline (delegates PipelineService directly)
///   realtime + GGML  → RealtimeAsrPipeline(GgmlAsrEngine)
///   realtime + TFLite → [ArgumentError] (blocked at UI layer; backstop here)
class PipelineFactory {
  static AsrPipeline create({
    required ProcessingMode mode,
    required bool useGgml,
    required PipelineService batchPipelineService,
    required StreamingAudioService streamingAudio,
    required TranscriptionService realtimeTranscription,
    required String modelPath,
    required String modelName,
    String sherpaModelDir = '',
  }) {
    if (mode == ProcessingMode.batch) {
      return BatchAsrPipeline(batchPipelineService);
    }

    // mode == realtime → always uses sherpa-onnx
    return SherpaOnnxRealtimePipeline(
      modelDir: sherpaModelDir,
      audioService: streamingAudio,
    );
  }
}

/// Internal helper that initialises the engine before the pipeline starts.
class _RealtimePipelineWithInit extends RealtimeAsrPipeline {
  final GgmlAsrEngine _initEngine;
  final String _modelPath;
  final String _modelName;

  _RealtimePipelineWithInit({
    required GgmlAsrEngine engine,
    required super.audioService,
    required String modelPath,
    required String modelName,
  }) : _initEngine = engine,
       _modelPath = modelPath,
       _modelName = modelName,
       super(engine: engine);

  @override
  Future<void> start() async {
    await _initEngine.initialize(_modelPath, _modelName);
    await super.start();
  }
}
