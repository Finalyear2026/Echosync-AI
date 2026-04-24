import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// Service for speech-to-text transcription using Whisper (whisper.cpp).
/// Supports English and Urdu with offline processing.
class TranscriptionService {
  static const _nativeChannel = MethodChannel('com.echosync.ai/deepfilternet');
  
  Whisper? _whisper;
  bool _isInitialized = false;
  String _currentModel = 'base';
  String? _activeModelPath;
  String? _activeModelName;
  bool _isNativeTflite = false;

  bool get isInitialized => _isInitialized;
  String get currentModel => _currentModel;
  String? get activeModelPath => _activeModelPath;
  String? get activeModelName => _activeModelName;
  bool get isNativeTflite => _isNativeTflite;


  /// Initialize Whisper with the specified model or path.
  /// Model names: 'tiny', 'base', 'small', 'medium', 'large-v3-turbo'
  Future<bool> initialize({String model = 'base', String? modelPath}) async {
    try {
      _activeModelPath = modelPath;
      _activeModelName = model;

      // 1. Determine engine type based on file extension
      if (modelPath != null && modelPath.toLowerCase().endsWith('.tflite')) {
        debugPrint('Whisper: Using Native TFLite Engine for $model');
        _isNativeTflite = true;
        _isInitialized = await _nativeChannel.invokeMethod<bool>('initialize', {
          'modelPath': modelPath,
          'engine': 'tflite',
        }) ?? false;
        return _isInitialized;
      }

      // 2. Fallback to whisper.cpp (GGML)
      _isNativeTflite = false;
      final mapped = _mapModelName(model);
      if (mapped == 'unsupported' && modelPath == null) {
        throw UnsupportedError('Whisper Large V3 and Turbo models are NOT supported by the default engine.');
      }
      _currentModel = mapped;

      _whisper = Whisper(
        model: _getWhisperModel(_currentModel),
        modelDir: modelPath != null ? File(modelPath).parent.path : null,
      );

      _isInitialized = true;
      debugPrint('Whisper: Initialized with GGML model=$_currentModel');
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
    if (!_isInitialized) {
      throw StateError('Whisper is not initialized. Call initialize() first.');
    }

    try {
      debugPrint('Whisper: Starting transcription via ${_isNativeTflite ? "Native TFLite" : "GGML"} engine');

      if (_isNativeTflite) {
        final result = await _nativeChannel.invokeMethod<String>('transcribe', {
          'audioPath': audioPath,
          'modelPath': _activeModelPath,
        });
        return result ?? '';
      }

      final response = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          isTranslate: translate,
          isNoTimestamps: true,
          splitOnWord: true,
          language: language ?? 'auto',
          threads: 4,
        ),
      );

      return response.text.trim();
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

  Future<void> dispose() async {
    _whisper = null;
    _isInitialized = false;
  }
}
