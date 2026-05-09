import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/snippet.dart';
import '../models/processing_state.dart';
import '../models/transcription_result.dart';
import '../services/pipeline_service.dart';
import '../services/settings_service.dart';
import '../services/model_manager_service.dart';
import '../services/logging_service.dart';
import '../services/asr/pipeline_coordinator.dart';

/// Main app state provider
class AppProvider extends ChangeNotifier {
  final PipelineService _pipeline;
  final SettingsService _settings;
  final ModelManagerService _modelManager;
  final bool _whisperCppCompatible;
  final PipelineCoordinator _coordinator;

  ProcessingStage _stage = ProcessingStage.idle;
  TranscriptionResult? _lastResult;
  String? _errorMessage;
  bool _isInitialized = false;
  Duration _recordingDuration = Duration.zero;
  final Map<String, bool> _modelStatuses = {};
  final Set<String> _pausedModels = {}; // Track models that are manually paused

  String _partialText = '';
  StreamSubscription<String>? _partialSub;

  // Cloud Registry
  List<dynamic> _cloudCategories = [];
  final Set<String> _activeDownloadIds = {};
  final Map<String, DownloadProgressInfo> _downloadProgress = {};

  // Registry state
  bool _isRegistryLoading = false;
  String? _registryError;

  // Selection state
  final Map<String, String> _activeModels = {}; // categoryId -> modelId

  AppProvider({
    required PipelineService pipeline,
    required SettingsService settings,
    required ModelManagerService modelManager,
    required bool whisperCppCompatible,
    required PipelineCoordinator coordinator,
  }) : _pipeline = pipeline,
       _settings = settings,
       _modelManager = modelManager,
       _whisperCppCompatible = whisperCppCompatible,
       _coordinator = coordinator {
    // Sync initial active models from results of settings
    _syncActiveModelsFromSettings();
  }

  void _syncActiveModelsFromSettings() {
    final s = _settings.getSettings();
    _activeModels['stt'] = s.whisperModel;
    _activeModels['stt_realtime'] = s.realtimeModel;
    _activeModels['nlp'] = s.nlpModel;
    _activeModels['noise_cleaning'] = s.noiseCleaningModel;
  }

  // Getters
  ProcessingStage get stage => _stage;
  TranscriptionResult? get lastResult => _lastResult;
  String? get errorMessage => _errorMessage;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _stage == ProcessingStage.recording;
  bool get isProcessing =>
      _stage == ProcessingStage.noiseFiltering ||
      _stage == ProcessingStage.transcribing ||
      _stage == ProcessingStage.formatting;
  Duration get recordingDuration => _recordingDuration;
  Map<String, DownloadProgressInfo> get downloadProgress => _downloadProgress;
  Map<String, bool> get modelStatuses => _modelStatuses;
  bool get isDownloading => _activeDownloadIds.isNotEmpty;
  Set<String> get activeDownloadIds => _activeDownloadIds;
  bool isModelDownloading(String modelId) =>
      _activeDownloadIds.contains(modelId);
  Map<String, String> get activeModels => _activeModels;
  bool get isWhisperCppCompatible => _whisperCppCompatible;

  ProcessingMode get processingMode => _settings.getSettings().processingMode;
  bool get isToggleEnabled => !isRecording && !isProcessing;
  bool get isTfliteRealtimeBlocked =>
      processingMode == ProcessingMode.realtime;
  String get partialText => _partialText;

  /// Get active model names for display
  Map<String, String> getActiveModelNames() {
    final Map<String, String> names = {};
    for (final category in _cloudCategories) {
      final categoryId = category['id'] as String;
      final categoryName = category['name'] as String;
      final activeId = _activeModels[categoryId];

      if (activeId == null || activeId.isEmpty) {
        names[categoryName] = 'None';
        continue;
      }

      final models = category['models'] as List;
      final model = models.firstWhere(
        (m) => m['id'] == activeId,
        orElse: () => null,
      );
      names[categoryName] = model != null ? model['name'] as String : 'Unknown';
    }
    return names;
  }

  /// Set a model as active for its category
  Future<void> activateModel(String category, String modelId) async {
    LoggingService().log(
      'Activating model',
      category: 'MODELS',
      details: {'category': category, 'modelId': modelId},
    );

    // 1. INSTANT UI UPDATE
    _activeModels[category] = modelId;
    notifyListeners();

    // 2. BACKGROUND WORK (Non-blocking)
    Future.microtask(() async {
      try {
        switch (category) {
          case 'stt':
            await _settings.updateWhisperModel(modelId);
            await _pipeline.initialize();
            break;
          case 'stt_realtime':
            await _settings.setRealtimeModel(modelId);
            break;
          case 'nlp':
            await _settings.updateNLPModel(modelId);
            break;
          case 'noise_cleaning':
            await _settings.updateNoiseCleaningModel(modelId);
            await _pipeline.initialize();
            break;
        }
        notifyListeners(); // Second update to reflect any internal state changes after init
      } catch (e) {
        debugPrint('AppProvider: Background activation failed: $e');
      }
    });
  }

  /// Clear the active model for a category
  Future<void> deactivateModel(String categoryId) async {
    LoggingService().log(
      'Deactivating model',
      category: 'MODELS',
      details: {'category': categoryId},
    );

    // 1. INSTANT UI UPDATE
    _activeModels[categoryId] = '';
    notifyListeners();

    // 2. BACKGROUND WORK (Non-blocking)
    Future.microtask(() async {
      try {
        switch (categoryId) {
          case 'stt':
            await _settings.updateWhisperModel('');
            await _pipeline.initialize();
            break;
          case 'stt_realtime':
            await _settings.setRealtimeModel('');
            break;
          case 'nlp':
            await _settings.updateNLPModel('');
            break;
          case 'noise_cleaning':
            await _settings.updateNoiseCleaningModel('');
            await _pipeline.initialize();
            break;
        }
        notifyListeners();
      } catch (e) {
        debugPrint('AppProvider: Background deactivation failed: $e');
      }
    });
  }

  bool isModelActive(String categoryId, String modelId) {
    if (modelId.isEmpty) return false;
    return _activeModels[categoryId] == modelId;
  }

  /// Check if required categories for the current mode have a model selected.
  ///
  /// Real-time mode requires `stt_realtime` (sherpa); batch requires `stt`.
  /// Both modes require `nlp` and `noise_cleaning`.
  bool get areAllModelsSelected {
    if (_cloudCategories.isEmpty) return false;
    final isRealtime = processingMode == ProcessingMode.realtime;
    for (final category in _cloudCategories) {
      final categoryId = category['id'] as String;
      // Skip the irrelevant STT category for the current mode
      if (isRealtime && categoryId == 'stt') continue;
      if (!isRealtime && categoryId == 'stt_realtime') continue;
      final activeId = _activeModels[categoryId];
      if (activeId == null || activeId.isEmpty) {
        return false;
      }
    }
    return true;
  }

  /// Get IDs of categories that don't have a model selected, for current mode.
  List<String> getMissingCategoryIds() {
    final List<String> missing = [];
    final isRealtime = processingMode == ProcessingMode.realtime;
    for (final category in _cloudCategories) {
      final categoryId = category['id'] as String;
      if (isRealtime && categoryId == 'stt') continue;
      if (!isRealtime && categoryId == 'stt_realtime') continue;
      final activeId = _activeModels[categoryId];
      if (activeId == null || activeId.isEmpty) {
        missing.add(categoryId);
      }
    }
    return missing;
  }

  AppSettings get appSettings =>
      _isInitialized ? _settings.getSettings() : AppSettings();
  List<DictionaryEntry> get dictionary =>
      _isInitialized ? _settings.getDictionary() : [];
  List<Snippet> get snippets => _isInitialized ? _settings.getSnippets() : [];

  List<dynamic> get cloudCategories => _cloudCategories;
  bool get isRegistryLoading => _isRegistryLoading;
  String? get registryError => _registryError;
  Set<String> get pausedModels => _pausedModels;

  /// Check if a model is currently paused
  bool isPaused(String modelId) => _pausedModels.contains(modelId);

  // Helper to check if a specific model is downloaded
  bool isModelDownloaded(String modelId) {
    // Check locally by looking for the filename in the path
    // For now, simpler check against modelManager's internal status
    // (Improved in v0.2 to look at actual file presence)
    return _modelStatuses[modelId] ?? false;
  }

  /// Initialize the app
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      if (!_settings.isInitialized) {
        await _settings.initialize();
      }

      if (!_whisperCppCompatible) {
        if (_settings.getSettings().useWhisperCppEngine) {
          await _settings.setUseWhisperCppEngine(false);
        }
        if (_settings.getSettings().processingMode == ProcessingMode.realtime) {
          await _settings.setProcessingMode(ProcessingMode.batch);
        }
      }

      await LoggingService().init();

      // Ensure local registry (models.json) exists at startup
      // Load local repository metadata
      final localRegistry = await _modelManager.loadLocalRegistry();
      _cloudCategories = localRegistry['categories'] ?? [];

      await _pipeline.initialize();
      await refreshModelStatuses();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Initialization failed: $e';
      notifyListeners();
    }
  }

  /// Refresh model download statuses
  Future<void> refreshModelStatuses() async {
    // Collect metadata for cloud models to check their file presence
    final Map<String, dynamic> dynamicMeta = {};
    for (final category in _cloudCategories) {
      final models = category['models'] as List;
      for (final m in models) {
        dynamicMeta[m['id']] = {
          'filename': m['filename'],
          'size_bytes': m['size_bytes'],
          'is_zip': m['is_zip'] ?? false,
        };
      }
    }

    final statuses = await _modelManager.getModelStatuses(
      dynamicModels: dynamicMeta,
    );
    _modelStatuses.clear();
    _modelStatuses.addAll(statuses);

    LoggingService().log(
      'Model statuses refreshed',
      category: 'MODELS',
      details: {
        'count': statuses.length,
        'downloaded_count': statuses.values.where((v) => v).length,
      },
    );

    // Also check for partial downloads to show "Resume" status
    for (final category in _cloudCategories) {
      final models = category['models'] as List;
      for (final m in models) {
        final id = m['id'];
        final pInfo = await _modelManager.getPartialDownloadInfo(
          id,
          filename: m['filename'],
          expectedSize: m['size_bytes'],
        );

        if (pInfo != null && !statuses[id]!) {
          _pausedModels.add(id);
          _downloadProgress[id] = pInfo;
        } else {
          _pausedModels.remove(id);
        }
      }
    }

    await _ensureDefaultModelsSelected();
    notifyListeners();
  }

  /// Ensure active models are still valid (downloaded)
  Future<void> _ensureDefaultModelsSelected() async {
    bool changed = false;

    for (final category in _cloudCategories) {
      final categoryId = category['id'] as String;
      String currentActive = _activeModels[categoryId] ?? '';

      // If a model is selected, verify it's still available
      if (currentActive.isNotEmpty) {
        bool isActiveDownloaded = _modelStatuses[currentActive] ?? false;

        if (!isActiveDownloaded) {
          LoggingService().log(
            'Active model no longer available, clearing selection',
            category: 'MODELS',
            details: {'category': categoryId, 'modelId': currentActive},
          );

          _activeModels[categoryId] = '';
          switch (categoryId) {
            case 'stt':
              await _settings.updateWhisperModel('');
              break;
            case 'stt_realtime':
              await _settings.setRealtimeModel('');
              break;
            case 'nlp':
              await _settings.updateNLPModel('');
              break;
            case 'noise_cleaning':
              await _settings.updateNoiseCleaningModel('');
              break;
          }
          changed = true;
        }
      }
    }

    if (changed) {
      // Re-initialize pipeline if an active model was cleared
      await _pipeline.initialize();
    }
  }

  /// Check if required models are downloaded for the current mode.
  Future<bool> areModelsReady() async {
    if (processingMode == ProcessingMode.realtime) {
      const sherpaKey = 'sherpa-onnx-streaming-en-20m';
      return _modelManager.isModelDownloaded(sherpaKey);
    }
    return _pipeline.areModelsReady();
  }

  /// Start/stop recording toggle
  Future<void> toggleRecording() async {
    if (isRecording) {
      await _stopAndProcess();
    } else if (_stage == ProcessingStage.idle ||
        _stage == ProcessingStage.completed ||
        _stage == ProcessingStage.error) {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      _errorMessage = null;
      _partialText = '';
      _stage = ProcessingStage.recording;
      _recordingDuration = Duration.zero;
      notifyListeners();

      await _coordinator.startRecording();
      await _partialSub?.cancel();
      _partialSub = _coordinator.partialStream.listen((text) {
        _partialText = text;
        notifyListeners();
      });
      _updateRecordingDuration();
    } catch (e) {
      _stage = ProcessingStage.error;
      _errorMessage = 'Recording failed: $e';
      notifyListeners();
    }
  }

  void _updateRecordingDuration() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_stage == ProcessingStage.recording) {
        _recordingDuration =
            _pipeline.audioRecorder.getRecordingDuration() ??
            _recordingDuration + const Duration(seconds: 1);
        notifyListeners();
        _updateRecordingDuration();
      }
    });
  }

  Future<void> _stopAndProcess() async {
    try {
      final result = await _coordinator.stopRecording(
        onStageChanged: (stage) {
          _stage = stage;
          notifyListeners();
        },
      );
      await _partialSub?.cancel();
      _partialSub = null;
      _partialText = '';
      _lastResult = result;
      _stage = ProcessingStage.completed;
      notifyListeners();
    } catch (e) {
      _stage = ProcessingStage.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    await _coordinator.cancelRecording();
    await _partialSub?.cancel();
    _partialSub = null;
    _partialText = '';
    _stage = ProcessingStage.idle;
    _errorMessage = null;
    _recordingDuration = Duration.zero;
    notifyListeners();
  }

  /// Reset to idle
  void reset() {
    _pipeline.reset();
    _stage = ProcessingStage.idle;
    _errorMessage = null;
    _lastResult = null;
    _partialText = '';
    _recordingDuration = Duration.zero;
    notifyListeners();
  }

  /// Refresh cloud models from GitHub with ETag support
  Future<void> refreshCloudModels({bool force = false}) async {
    if (!force && _cloudCategories.isNotEmpty && !_isRegistryLoading) {
      // Background sync if already have data
      _syncInBackground();
      return;
    }

    if (_isRegistryLoading) return;

    _isRegistryLoading = true;
    _registryError = null;
    notifyListeners();

    try {
      // 1. Load Local first for instant UI
      final localRegistry = await _modelManager.loadLocalRegistry();
      _cloudCategories = localRegistry['categories'] ?? [];
      await refreshModelStatuses();
      notifyListeners();

      // 2. Then Sync with Cloud (GitHub)
      final updatedRegistry = await _modelManager.syncRegistryWithCloud(
        _settings,
      );
      if (updatedRegistry != null) {
        _cloudCategories = updatedRegistry['categories'] ?? [];
        await refreshModelStatuses();
        LoggingService().log(
          'Cloud registry updated and applied',
          category: 'MODELS',
        );
      }
    } catch (e) {
      _registryError = 'Failed to load models: $e';
      LoggingService().log(
        'Registry fetch failed',
        category: 'MODELS_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _isRegistryLoading = false;
      notifyListeners();
    }
  }

  /// Perform a quiet background sync without showing loading spinners
  Future<void> _syncInBackground() async {
    try {
      final updatedRegistry = await _modelManager.syncRegistryWithCloud(
        _settings,
      );
      if (updatedRegistry != null) {
        _cloudCategories = updatedRegistry['categories'] ?? [];
        await refreshModelStatuses();
        notifyListeners();
        LoggingService().log(
          'Background registry sync completed',
          category: 'MODELS',
        );
      }
    } catch (e) {
      // Fail silently in background
      debugPrint('AppProvider: Background sync failed: $e');
    }
  }

  /// Clear the registry error
  void clearRegistryError() {
    _registryError = null;
    notifyListeners();
  }

  /// Download a model with resume support
  Future<void> downloadModel(
    String modelId, {
    String? driveId,
    bool isZip = false,
    int? expectedSize,
    String? filename,
  }) async {
    _activeDownloadIds.add(modelId);
    _pausedModels.remove(
      modelId,
    ); // Remove from paused if we are starting/resuming
    notifyListeners();

    try {
      LoggingService().log(
        'Starting model download',
        category: 'MODELS',
        details: {
          'model_id': modelId,
          'filename': filename,
          'is_zip': isZip,
          'expected_size': expectedSize,
        },
      );

      await _modelManager.downloadModel(
        modelId,
        driveId: driveId,
        isZip: isZip,
        expectedSize: expectedSize,
        filename: filename,
        onProgress: (progressInfo) {
          _downloadProgress[modelId] = progressInfo;
          notifyListeners();
        },
      );

      LoggingService().log(
        'Model download completed successfully',
        category: 'MODELS',
        details: {'model_id': modelId},
      );

      await refreshModelStatuses();
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      LoggingService().log(
        'Model download failed',
        category: 'MODELS_ERROR',
        details: {'model_id': modelId, 'error': e.toString()},
      );
      notifyListeners();
    } finally {
      _activeDownloadIds.remove(modelId);
      notifyListeners();
    }
  }

  /// Pause model download
  void pauseDownload(String modelId) {
    _modelManager.pauseDownload(modelId);
    _activeDownloadIds.remove(modelId);
    _pausedModels.add(modelId);

    // Reset speed to 0 so the UI shows 0 KB/s immediately upon pause
    final info = _downloadProgress[modelId];
    if (info != null) {
      _downloadProgress[modelId] = DownloadProgressInfo(
        progress: info.progress,
        downloadedBytes: info.downloadedBytes,
        totalBytes: info.totalBytes,
        speedBytesPerSecond: 0,
      );
    }

    LoggingService().log(
      'Model download paused by user',
      category: 'MODELS',
      details: {'model_id': modelId},
    );
    notifyListeners();
  }

  /// Cancel model download completely
  void cancelDownload(String modelId, {String? filename}) {
    _modelManager.cancelDownload(modelId, filename: filename);
    _activeDownloadIds.remove(modelId);
    _pausedModels.remove(modelId);
    _downloadProgress.remove(modelId);
    LoggingService().log(
      'Model download cancelled by user',
      category: 'MODELS',
      details: {'model_id': modelId},
    );
    notifyListeners();
  }

  /// Delete a downloaded model
  Future<void> deleteModel(
    String modelId, {
    String? filename,
    bool isZip = false,
  }) async {
    try {
      LoggingService().log(
        'Deleting model',
        category: 'MODELS',
        details: {'model_id': modelId, 'filename': filename, 'is_zip': isZip},
      );
      await _modelManager.deleteModel(
        modelId,
        filename: filename,
        isZip: isZip,
      );

      LoggingService().log(
        'Model deleted successfully',
        category: 'MODELS',
        details: {'model_id': modelId},
      );
      await refreshModelStatuses();
      await _ensureDefaultModelsSelected();
      notifyListeners();
    } catch (e) {
      LoggingService().log(
        'Model deletion failed',
        category: 'MODELS_ERROR',
        details: {'model_id': modelId, 'error': e.toString()},
      );
      rethrow;
    }
  }

  // --- Settings mutations ---

  Future<void> setTranscriptionStyle(TranscriptionStyle style) async {
    await _settings.setTranscriptionStyle(style);
    notifyListeners();
  }

  Future<void> setTranscriptionTone(TranscriptionTone tone) async {
    await _settings.setTranscriptionTone(tone);
    notifyListeners();
  }

  Future<void> setWhisperModel(String model) async {
    await _settings.updateWhisperModel(model);
    notifyListeners();
  }

  Future<void> setNoiseFilterEnabled(bool enabled) async {
    await _settings.setNoiseFilterEnabled(enabled);
    notifyListeners();
  }

  Future<void> setUseWhisperCppEngine(bool enabled) async {
    if (enabled && !_whisperCppCompatible) {
      notifyListeners();
      return;
    }
    await _settings.setUseWhisperCppEngine(enabled);
    await _pipeline.initialize();
    notifyListeners();
  }

  Future<void> setProcessingMode(ProcessingMode mode) async {
    if (mode == ProcessingMode.realtime &&
        !_settings.getSettings().useWhisperCppEngine) {
      await _settings.setUseWhisperCppEngine(true);
      await _pipeline.initialize();
    }
    await _settings.setProcessingMode(mode);
    notifyListeners();
  }

  // --- Dictionary ---

  Future<void> addDictionaryEntry(String misheard, String correct) async {
    await _settings.addDictionaryEntry(misheard, correct);
    notifyListeners();
  }

  Future<void> updateDictionaryEntry(
    String id,
    String misheard,
    String correct,
  ) async {
    await _settings.updateDictionaryEntry(id, misheard, correct);
    notifyListeners();
  }

  Future<void> deleteDictionaryEntry(String id) async {
    await _settings.deleteDictionaryEntry(id);
    notifyListeners();
  }

  // --- Snippets ---

  Future<void> addSnippet(
    String trigger,
    String template, {
    String? description,
  }) async {
    await _settings.addSnippet(trigger, template, description: description);
    notifyListeners();
  }

  Future<void> updateSnippet(
    String id,
    String trigger,
    String template, {
    String? description,
  }) async {
    await _settings.updateSnippet(
      id,
      trigger,
      template,
      description: description,
    );
    notifyListeners();
  }

  Future<void> deleteSnippet(String id) async {
    await _settings.deleteSnippet(id);
    notifyListeners();
  }

  /// Clear the general error message
  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }
}
