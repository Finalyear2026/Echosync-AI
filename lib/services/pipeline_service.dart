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
      final appSettings = settings.getSettings();

      // Initialize noise filter with selected model if available
      if (appSettings.noiseFilterEnabled &&
          appSettings.noiseCleaningModel.isNotEmpty) {
        final info = ModelManagerService.models[appSettings.noiseCleaningModel];
        final engine = (info?.format == ModelFormat.tflite)
            ? 'tflite'
            : 'deepfilternet';

        if (await modelManager.isModelDownloaded(
          appSettings.noiseCleaningModel,
        )) {
          final noisePath = await modelManager.getModelPath(
            appSettings.noiseCleaningModel,
          );
          await noiseFilter.initialize(modelPath: noisePath, engine: engine);
        } else {
          await noiseFilter.initialize();
        }
      } else {
        await noiseFilter.initialize();
      }

      // Initialize whisper with selected model
      final whisperKey = _mapWhisperModelKey(appSettings.whisperModel);

      // Check if whisper model is downloaded
      if (await modelManager.isModelDownloaded(whisperKey)) {
        final baseWhisperPath = await modelManager.getModelPath(whisperKey);
        final whisperPath = transcription.resolveModelPathForEngine(
          baseWhisperPath,
          useWhisperCpp: appSettings.useWhisperCppEngine,
        );
        await transcription.initialize(
          model: appSettings.whisperModel,
          modelPath: whisperPath,
          useWhisperCpp: appSettings.useWhisperCppEngine,
        );
      }

      // Check if LLM model is downloaded
      if (appSettings.nlpModel.isNotEmpty &&
          await modelManager.isModelDownloaded(appSettings.nlpModel)) {
        final llmPath = await modelManager.getModelPath(appSettings.nlpModel);
        await llm.loadModel(llmPath);
      }

      debugPrint('Pipeline: All services initialized');
      return true;
    } catch (e) {
      debugPrint('Pipeline: Initialization error: $e');
      return false;
    }
  }

  String _mapWhisperModelKey(String model) {
    final m = model.toLowerCase();

    // Exact folder names matching your list
    if (m.contains('base')) return 'whisper-base';
    if (m.contains('small')) return 'whisper-small';
    if (m.contains('medium')) return 'whisper-medium';
    if (m.contains('v3') || m.contains('turbo'))
      return 'whisper-large-v3-turbo';

    return 'whisper-base';
  }

  /// Check if models are ready for transcription
  Future<bool> areModelsReady() async {
    final appSettings = settings.getSettings();

    // 1. Check Whisper (STT)
    final whisperKey = _mapWhisperModelKey(appSettings.whisperModel);
    if (whisperKey == 'unsupported') return false;
    final whisperReady = await modelManager.isModelDownloaded(whisperKey);
    if (!whisperReady) return false;
    final baseWhisperPath = await modelManager.getModelPath(whisperKey);
    final resolvedWhisperPath = transcription.resolveModelPathForEngine(
      baseWhisperPath,
      useWhisperCpp: appSettings.useWhisperCppEngine,
    );
    if (resolvedWhisperPath == null) return false;

    // 2. Check Noise Cleaning (if enabled)
    if (appSettings.noiseFilterEnabled &&
        appSettings.noiseCleaningModel.isNotEmpty) {
      final noiseReady = await modelManager.isModelDownloaded(
        appSettings.noiseCleaningModel,
      );
      if (!noiseReady) return false;
    }

    // 3. Check NLP (if smart mode)
    if (appSettings.transcriptionStyle == TranscriptionStyle.smart) {
      if (appSettings.nlpModel.isEmpty) return false;
      final llmReady = await modelManager.isModelDownloaded(
        appSettings.nlpModel,
      );
      if (!llmReady) return false;
    }

    return true;
  }

  /// Start recording
  Future<void> startRecording() async {
    try {
      _currentStage = ProcessingStage.recording;
      _errorMessage = null;

      // Load models in background as soon as we start recording
      _loadModelsInBackground();

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
    String? recordingPath;
    String? filteredPath;
    String? resampledPath;

    try {
      // 1. Stop recording
      recordingPath = await audioRecorder.stopRecording();
      if (recordingPath == null) {
        throw Exception('No recording file produced');
      }

      final appSettings = settings.getSettings();
      String audioPath = recordingPath;

      // 2. Noise filtering
      if (appSettings.noiseFilterEnabled &&
          appSettings.noiseCleaningModel.isNotEmpty) {
        _currentStage = ProcessingStage.noiseFiltering;
        onStageChanged?.call(_currentStage);
        debugPrint('Pipeline: Stage → Noise Filtering');

        try {
          final info =
              ModelManagerService.models[appSettings.noiseCleaningModel];
          final engine = (info?.format == ModelFormat.tflite)
              ? 'tflite'
              : 'deepfilternet';
          final noiseModelPath = await modelManager.getModelPath(
            appSettings.noiseCleaningModel,
          );

          // Ensure correct noise model is initialized
          if (noiseFilter.loadedModelPath != noiseModelPath) {
            debugPrint(
              'Pipeline: Switching Noise model to ${appSettings.noiseCleaningModel} ($engine)',
            );
            await noiseFilter.initialize(
              modelPath: noiseModelPath,
              engine: engine,
            );
          }

          audioPath = await noiseFilter.processAudioFile(
            recordingPath,
            modelPath: noiseModelPath,
            engine: engine,
          );
        } catch (e) {
          debugPrint(
            'Pipeline: Noise filtering error: $e. Falling back to original audio.',
          );
          audioPath = recordingPath;
        }
      }

      // 3. Transcribe
      _currentStage = ProcessingStage.transcribing;
      onStageChanged?.call(_currentStage);
      debugPrint('Pipeline: Stage → Transcribing');

      // 3.1 Transcription Prep
      final file = File(audioPath);
      final stats = await file.stat();
      debugPrint('Whisper: Input audio size: ${stats.size} bytes');
      // No longer using noiseFilter.resampleTo16kHz because our native engine
      // now handles resampling and 32-bit float input internally with high quality.

      // Ensure the correct Whisper model is loaded
      final whisperKey = _mapWhisperModelKey(appSettings.whisperModel);
      final whisperPath = await modelManager.isModelDownloaded(whisperKey)
          ? transcription.resolveModelPathForEngine(
              await modelManager.getModelPath(whisperKey),
              useWhisperCpp: appSettings.useWhisperCppEngine,
            )
          : null;

      if (!transcription.isInitialized ||
          transcription.activeModelName != appSettings.whisperModel ||
          transcription.activeModelPath != whisperPath) {
        debugPrint(
          'Pipeline: Switching STT model to ${appSettings.whisperModel}',
        );
        await transcription.initialize(
          model: appSettings.whisperModel,
          modelPath: whisperPath,
          useWhisperCpp: appSettings.useWhisperCppEngine,
        );
      }

      final rawText = await transcription.transcribe(
        audioPath,
        language: 'en',
        threads: 6,
      );

      if (rawText.isEmpty) {
        throw Exception('No speech detected in the recording');
      }

      // 4. LLM formatting (if smart mode)
      String formattedText = rawText;
      bool wasFormatted = false;

      if (appSettings.transcriptionStyle == TranscriptionStyle.smart) {
        _currentStage = ProcessingStage.formatting;
        onStageChanged?.call(_currentStage);
        debugPrint('Pipeline: Stage → Formatting');

        // Ensure the correct LLM model is loaded
        if (appSettings.nlpModel.isNotEmpty) {
          final targetLlmPath = await modelManager.getModelPath(
            appSettings.nlpModel,
          );
          if (!llm.isModelLoaded || llm.loadedModelPath != targetLlmPath) {
            debugPrint(
              'Pipeline: Switching LLM model to ${appSettings.nlpModel}',
            );
            await llm.loadModel(targetLlmPath);
          }
        }

        if (llm.isModelLoaded) {
          formattedText = await llm.formatText(
            rawText: rawText,
            style: appSettings.transcriptionStyle,
            tone: appSettings.transcriptionTone,
            dictionary: settings.getDictionaryForPrompt(),
            snippets: settings.getSnippetsForPrompt(),
          );
          wasFormatted = true;
        }
      }

      // 5. Apply snippet replacements (even in raw mode for manual triggers)
      formattedText = _applySnippets(formattedText);

      final processingTime = DateTime.now().difference(startTime);

      // Calculate audio duration from file
      final audioDuration =
          audioRecorder.getRecordingDuration() ?? Duration.zero;

      _currentStage = ProcessingStage.completed;
      onStageChanged?.call(_currentStage);

      // Clean up temp files
      _cleanupTempFiles([
        recordingPath,
        filteredPath ?? '',
        resampledPath ?? '',
      ]);

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
    } finally {
      // UNLOAD MODELS as soon as processing is done to free RAM
      await _unloadAllModels();
    }
  }

  /// Load models in background
  Future<void> _loadModelsInBackground() async {
    debugPrint('Pipeline: Background model loading started...');
    await initialize();
  }

  /// Unload all models from memory
  Future<void> _unloadAllModels() async {
    debugPrint('Pipeline: Unloading all models to free RAM...');
    try {
      await transcription.dispose();
      await llm.dispose();
      await noiseFilter.dispose();
      debugPrint('Pipeline: All models unloaded successfully.');
    } catch (e) {
      debugPrint('Pipeline: Error during model unloading: $e');
    }
  }

  /// Apply snippet replacements to text
  String _applySnippets(String text) {
    final snippets = settings.getSnippets();
    var result = text;
    for (final snippet in snippets) {
      result = result.replaceAll(
        snippet.triggerPhrase,
        snippet.templateContent,
      );
    }
    return result;
  }

  /// Cleanup temporary audio files
  Future<void> _cleanupTempFiles(List<String> paths) async {
    for (final path in paths.toSet()) {
      // Use set to avoid double deletion
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Pipeline: Cleanup error for $path: $e');
      }
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
