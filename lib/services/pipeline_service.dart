import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/processing_state.dart';
import '../models/transcription_result.dart';
import 'audio_recorder_service.dart';
import 'noise_filter_service.dart';
import 'transcription_service.dart';
import 'llm_service.dart';
import 'settings_service.dart';
import 'model_manager_service.dart';

/// Orchestrates the full transcription pipeline:
/// Record → Noise Filter → Transcribe → LLM Format → Output
class PipelineService {
  final AudioRecorderService audioRecorder;
  final NoiseFilterService noiseFilter;
  final TranscriptionService transcription;
  final LlmService llm;
  final SettingsService settings;
  final ModelManagerService modelManager;

  ProcessingStage _currentStage = ProcessingStage.idle;
  String? _errorMessage;

  ProcessingStage get currentStage => _currentStage;
  String? get errorMessage => _errorMessage;

  PipelineService({
    required this.audioRecorder,
    required this.noiseFilter,
    required this.transcription,
    required this.llm,
    required this.settings,
    required this.modelManager,
  });

  /// Initialize all services
  Future<bool> initialize() async {
    try {
      // Initialize noise filter (non-blocking, fallback available)
      await noiseFilter.initialize();

      // Initialize whisper with selected model
      final appSettings = settings.getSettings();
      final whisperModel = _mapWhisperModelKey(appSettings.whisperModel);

      // Check if whisper model is downloaded
      if (await modelManager.isModelDownloaded(whisperModel)) {
        await transcription.initialize(model: appSettings.whisperModel);
      }

      // Check if LLM model is downloaded
      if (await modelManager.isModelDownloaded('qwen2.5-1.5b')) {
        final llmPath = await modelManager.getModelPath('qwen2.5-1.5b');
        await llm.loadModel(llmPath);
      }

      debugPrint('Pipeline: All services initialized');
      return true;
    } catch (e) {
      debugPrint('Pipeline: Initialization error: $e');
      return false;
    }
  }

  /// Map settings whisper model name to model manager key
  String _mapWhisperModelKey(String model) {
    switch (model.toLowerCase()) {
      case 'large-v3-turbo':
        return 'whisper-large-v3-turbo';
      case 'medium':
        return 'whisper-medium';
      case 'small':
        return 'whisper-small';
      case 'base':
      default:
        return 'whisper-base';
    }
  }

  /// Check if models are ready for transcription
  Future<bool> areModelsReady() async {
    final appSettings = settings.getSettings();
    final whisperKey = _mapWhisperModelKey(appSettings.whisperModel);

    final whisperReady = await modelManager.isModelDownloaded(whisperKey);
    final llmReady = await modelManager.isModelDownloaded('qwen2.5-1.5b');

    // For raw mode, only whisper is needed
    if (appSettings.transcriptionStyle == TranscriptionStyle.raw) {
      return whisperReady;
    }
    return whisperReady && llmReady;
  }

  /// Start recording
  Future<void> startRecording() async {
    try {
      _currentStage = ProcessingStage.recording;
      _errorMessage = null;
      await audioRecorder.startRecording();
    } catch (e) {
      _currentStage = ProcessingStage.error;
      _errorMessage = 'Failed to start recording: $e';
      rethrow;
    }
  }

  /// Stop recording and process the audio through the full pipeline
  Future<TranscriptionResult> stopAndProcess({
    ValueChanged<ProcessingStage>? onStageChanged,
  }) async {
    final startTime = DateTime.now();

    try {
      // 1. Stop recording
      final recordingPath = await audioRecorder.stopRecording();
      if (recordingPath == null) {
        throw Exception('No recording file produced');
      }

      final appSettings = settings.getSettings();
      String audioPath = recordingPath;

      // 2. Noise filtering
      if (appSettings.noiseFilterEnabled) {
        _currentStage = ProcessingStage.noiseFiltering;
        onStageChanged?.call(_currentStage);
        debugPrint('Pipeline: Stage → Noise Filtering');

        audioPath = await noiseFilter.processAudioFile(recordingPath);
      }

      // 3. Transcribe
      _currentStage = ProcessingStage.transcribing;
      onStageChanged?.call(_currentStage);
      debugPrint('Pipeline: Stage → Transcribing');

      // If transcription isn't initialized yet, try to init now
      if (!transcription.isInitialized) {
        await transcription.initialize(model: appSettings.whisperModel);
      }

      final rawText = await transcription.transcribe(audioPath);

      if (rawText.isEmpty) {
        throw Exception('No speech detected in the recording');
      }

      // 4. LLM formatting (if smart mode)
      String formattedText = rawText;
      bool wasFormatted = false;

      if (appSettings.transcriptionStyle == TranscriptionStyle.smart &&
          llm.isModelLoaded) {
        _currentStage = ProcessingStage.formatting;
        onStageChanged?.call(_currentStage);
        debugPrint('Pipeline: Stage → Formatting');

        formattedText = await llm.formatText(
          rawText: rawText,
          style: appSettings.transcriptionStyle,
          tone: appSettings.transcriptionTone,
          dictionary: settings.getDictionaryForPrompt(),
          snippets: settings.getSnippetsForPrompt(),
        );
        wasFormatted = true;
      }

      // 5. Apply snippet replacements (even in raw mode for manual triggers)
      formattedText = _applySnippets(formattedText);

      final processingTime = DateTime.now().difference(startTime);

      // Calculate audio duration from file
      final audioDuration = audioRecorder.getRecordingDuration() ??
          Duration.zero;

      _currentStage = ProcessingStage.completed;
      onStageChanged?.call(_currentStage);

      // Clean up temp files
      _cleanupTempFiles(recordingPath, audioPath);

      return TranscriptionResult(
        rawText: rawText,
        formattedText: formattedText,
        language: 'auto',
        audioDuration: audioDuration,
        processingTime: processingTime,
        timestamp: DateTime.now(),
        wasNoiseFiltered: appSettings.noiseFilterEnabled,
        wasFormatted: wasFormatted,
      );
    } catch (e) {
      _currentStage = ProcessingStage.error;
      _errorMessage = e.toString();
      onStageChanged?.call(_currentStage);
      debugPrint('Pipeline: Error → $e');
      rethrow;
    }
  }

  /// Apply snippet replacements to text
  String _applySnippets(String text) {
    final snippets = settings.getSnippets();
    var result = text;
    for (final snippet in snippets) {
      result = result.replaceAll(snippet.triggerPhrase, snippet.templateContent);
    }
    return result;
  }

  /// Cleanup temporary audio files
  Future<void> _cleanupTempFiles(String recordingPath, String filteredPath) async {
    try {
      // Delete the original recording
      final recordingFile = File(recordingPath);
      if (await recordingFile.exists()) {
        await recordingFile.delete();
      }
      // Delete the filtered file if different from the original
      if (filteredPath != recordingPath) {
        final filteredFile = File(filteredPath);
        if (await filteredFile.exists()) {
          await filteredFile.delete();
        }
      }
    } catch (e) {
      debugPrint('Pipeline: Cleanup error: $e');
    }
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    await audioRecorder.cancelRecording();
    _currentStage = ProcessingStage.idle;
    _errorMessage = null;
  }

  /// Reset to idle state
  void reset() {
    _currentStage = ProcessingStage.idle;
    _errorMessage = null;
  }
}
