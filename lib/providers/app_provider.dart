import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/snippet.dart';
import '../models/processing_state.dart';
import '../models/transcription_result.dart';
import '../services/pipeline_service.dart';
import '../services/settings_service.dart';
import '../services/model_manager_service.dart';

/// Main app state provider
class AppProvider extends ChangeNotifier {
  final PipelineService _pipeline;
  final SettingsService _settings;
  final ModelManagerService _modelManager;

  ProcessingStage _stage = ProcessingStage.idle;
  TranscriptionResult? _lastResult;
  String? _errorMessage;
  bool _isInitialized = false;
  Duration _recordingDuration = Duration.zero;
  final Map<String, bool> _modelStatuses = {};

  // Cloud Registry
  List<dynamic> _cloudCategories = [];
  bool _isDownloading = false;
  String? _currentlyDownloading;
  final Map<String, double> _downloadProgress = {};
  
  // Registry state
  bool _isRegistryLoading = false;
  String? _registryError;
  
  // Selection state
  final Map<String, String> _activeModels = {}; // categoryId -> modelId

  AppProvider({
    required PipelineService pipeline,
    required SettingsService settings,
    required ModelManagerService modelManager,
  })  : _pipeline = pipeline,
        _settings = settings,
        _modelManager = modelManager;

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
  Map<String, double> get downloadProgress => _downloadProgress;
  Map<String, bool> get modelStatuses => _modelStatuses;
  bool get isDownloading => _isDownloading;
  String? get currentlyDownloading => _currentlyDownloading;

  AppSettings get appSettings =>
      _isInitialized ? _settings.getSettings() : AppSettings();
  List<DictionaryEntry> get dictionary =>
      _isInitialized ? _settings.getDictionary() : [];
  List<Snippet> get snippets => _isInitialized ? _settings.getSnippets() : [];
  
  List<dynamic> get cloudCategories => _cloudCategories;
  bool get isRegistryLoading => _isRegistryLoading;
  String? get registryError => _registryError;
  Map<String, String> get activeModels => _activeModels;
  
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
      await _modelManager.validateModelFiles();
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

    final statuses = await _modelManager.getModelStatuses(dynamicModels: dynamicMeta);
    _modelStatuses.clear();
    _modelStatuses.addAll(statuses);
    notifyListeners();
  }

  /// Check if required models are downloaded
  Future<bool> areModelsReady() => _pipeline.areModelsReady();

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
      _stage = ProcessingStage.recording;
      _recordingDuration = Duration.zero;
      notifyListeners();

      await _pipeline.startRecording();
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
        _recordingDuration = _pipeline.audioRecorder.getRecordingDuration() ??
            _recordingDuration + const Duration(seconds: 1);
        notifyListeners();
        _updateRecordingDuration();
      }
    });
  }

  Future<void> _stopAndProcess() async {
    try {
      final result = await _pipeline.stopAndProcess(
        onStageChanged: (stage) {
          _stage = stage;
          notifyListeners();
        },
      );

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
    await _pipeline.cancelRecording();
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
    _recordingDuration = Duration.zero;
    notifyListeners();
  }

  /// Refresh cloud models from Drive
  Future<void> refreshCloudModels({bool force = false}) async {
    if (!force && _cloudCategories.isNotEmpty) return;
    if (_isRegistryLoading) return;

    _isRegistryLoading = true;
    _registryError = null;
    notifyListeners();

    try {
      final registry = await _modelManager.fetchCloudRegistry();
      _cloudCategories = registry['categories'] ?? [];
      await refreshModelStatuses();
    } catch (e) {
      _registryError = 'Failed to load models: $e';
      debugPrint('AppProvider: Cloud refresh failed: $e');
    } finally {
      _isRegistryLoading = false;
      notifyListeners();
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
    _isDownloading = true;
    _currentlyDownloading = modelId;
    notifyListeners();

    try {
      await _modelManager.downloadModel(
        modelId,
        driveId: driveId,
        isZip: isZip,
        expectedSize: expectedSize,
        filename: filename,
        onProgress: (progress) {
          _downloadProgress[modelId] = progress;
          notifyListeners();
        },
      );
      
      await refreshModelStatuses();
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      notifyListeners();
    } finally {
      _isDownloading = false;
      _currentlyDownloading = null;
      notifyListeners();
    }
  }

  /// Cancel model download
  void cancelDownload(String modelId) {
    _modelManager.cancelDownload(modelId);
    _isDownloading = false;
    _currentlyDownloading = null;
    notifyListeners();
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId, {String? filename, bool isZip = false}) async {
    await _modelManager.deleteModel(modelId, filename: filename, isZip: isZip);
    await refreshModelStatuses();
    notifyListeners();
  }

  /// Toggle active model in category
  void useModel(String categoryId, String modelId) {
    _activeModels[categoryId] = modelId;
    notifyListeners();
    // In a real app, we'd persist this and re-init services
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
    await _settings.setWhisperModel(model);
    notifyListeners();
  }

  Future<void> setNoiseFilterEnabled(bool enabled) async {
    await _settings.setNoiseFilterEnabled(enabled);
    notifyListeners();
  }

  // --- Dictionary ---

  Future<void> addDictionaryEntry(String misheard, String correct) async {
    await _settings.addDictionaryEntry(misheard, correct);
    notifyListeners();
  }

  Future<void> updateDictionaryEntry(
      String id, String misheard, String correct) async {
    await _settings.updateDictionaryEntry(id, misheard, correct);
    notifyListeners();
  }

  Future<void> deleteDictionaryEntry(String id) async {
    await _settings.deleteDictionaryEntry(id);
    notifyListeners();
  }

  // --- Snippets ---

  Future<void> addSnippet(String trigger, String template,
      {String? description}) async {
    await _settings.addSnippet(trigger, template, description: description);
    notifyListeners();
  }

  Future<void> updateSnippet(String id, String trigger, String template,
      {String? description}) async {
    await _settings.updateSnippet(id, trigger, template,
        description: description);
    notifyListeners();
  }

  Future<void> deleteSnippet(String id) async {
    await _settings.deleteSnippet(id);
    notifyListeners();
  }
}
