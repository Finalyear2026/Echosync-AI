import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Service for speech-to-text transcription using Whisper (whisper.cpp).
/// Supports English and Urdu with offline processing.
class TranscriptionService {
  Whisper? _whisper;
  bool _isInitialized = false;
  String _currentModel = 'base';

  bool get isInitialized => _isInitialized;
  String get currentModel => _currentModel;

  /// Initialize Whisper with the specified model.
  /// Model names: 'tiny', 'base', 'small', 'medium', 'large-v3-turbo'
  Future<bool> initialize({String model = 'base'}) async {
    try {
      final mapped = _mapModelName(model);
      if (mapped == 'unsupported') {
        throw UnsupportedError('Whisper Large V3 and Turbo models are NOT supported by the current engine. Please use Base, Small, or Medium.');
      }
      _currentModel = mapped;

      _whisper = Whisper(
        model: _getWhisperModel(_currentModel),
        downloadHost: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main',
      );

      // Verify model is loadable
      final version = await _whisper!.getVersion();
      debugPrint('Whisper: Initialized with model=$_currentModel, version=$version');
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Whisper: Initialization error: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Transcribe an audio file.
  /// Returns the transcription text.
  Future<String> transcribe(
    String audioPath, {
    String? language,
    bool translate = false,
  }) async {
    if (!_isInitialized || _whisper == null) {
      throw StateError('Whisper is not initialized. Call initialize() first.');
    }

    try {
      debugPrint('Whisper: Starting transcription of $audioPath');

      final response = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          isTranslate: translate,
          isNoTimestamps: true,
          splitOnWord: true,
          language: language ?? 'auto',
        ),
      );

      // Parse the result - whisper_flutter_new returns WhisperTranscribeResponse
      final result = response.text.trim();
      debugPrint('Whisper: Transcription complete. Length=${result.length}');
      return result;
    } catch (e) {
      debugPrint('Whisper: Transcription error: $e');
      throw Exception('Transcription failed: $e');
    }
  }

  /// Map user-friendly model names to internal model names
  String _mapModelName(String model) {
    final m = model.toLowerCase();
    
    // Explicitly block V3/Turbo to avoid SIGILL crash
    if (m.contains('v3') || m.contains('turbo')) {
      return 'unsupported';
    }

    switch (m) {
      case 'large-v2':
      case 'large':
        return 'largeV2';
      case 'large-v1':
        return 'largeV1';
      case 'medium':
        return 'medium';
      case 'small':
        return 'small';
      case 'base':
        return 'base';
      case 'tiny':
        return 'tiny';
      default:
        return 'base';
    }
  }

  /// Get WhisperModel enum from model name
  WhisperModel _getWhisperModel(String modelName) {
    switch (modelName) {
      case 'largeV2':
        return WhisperModel.largeV2;
      case 'largeV1':
        return WhisperModel.largeV1;
      case 'medium':
        return WhisperModel.medium;
      case 'small':
        return WhisperModel.small;
      case 'base':
        return WhisperModel.base;
      case 'tiny':
        return WhisperModel.tiny;
      default:
        return WhisperModel.base;
    }
  }

  /// Get estimated model size in MB
  static int getModelSize(String model) {
    switch (model.toLowerCase()) {
      case 'large-v3-turbo':
      case 'large-v3':
        return 850;
      case 'medium':
        return 500;
      case 'small':
        return 250;
      case 'base':
        return 150;
      case 'tiny':
        return 75;
      default:
        return 150;
    }
  }

  void dispose() {
    _whisper = null;
    _isInitialized = false;
  }
}
