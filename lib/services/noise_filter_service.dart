import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Service for noise suppression using DeepFilterNet via platform channel.
/// Falls back to passthrough if DeepFilterNet is not available on the device.
class NoiseFilterService {
  static const _channel = MethodChannel('com.echosync.ai/deepfilternet');
  bool _isInitialized = false;
  bool _isAvailable = false;
  String? _loadedModelPath;

  bool get isAvailable => _isAvailable;
  String? get loadedModelPath => _loadedModelPath;


  /// Initialize the noise filter engine
  Future<bool> initialize({String? modelPath, String engine = 'auto'}) async {
    try {
      _isAvailable = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      final result = await _channel.invokeMethod<bool>('initialize', {
        'modelPath': modelPath,
        'engine': engine,
      }) ?? false;
      _isInitialized = result;
      _loadedModelPath = result ? modelPath : null;
      debugPrint('NoiseFilter: Initialized=$_isInitialized, Engine=$engine, Path=$modelPath');
      return _isInitialized;
    } on PlatformException catch (e) {
      debugPrint('NoiseFilter: Init error: ${e.message}');
      _isInitialized = true; // Allow passthrough
      _isAvailable = false;
      _loadedModelPath = null;
      return true;
    } catch (e) {
      debugPrint('NoiseFilter: Unexpected init error: $e');
      _isInitialized = true;
      _isAvailable = false;
      _loadedModelPath = null;
      return true;
    }
  }

  /// Process an audio file through noise suppression.
  /// Returns the path to the cleaned audio file.
  Future<String> processAudioFile(String inputPath, {String? modelPath, String engine = 'auto'}) async {
    if (!_isInitialized || (modelPath != null && _loadedModelPath != modelPath)) {
      await initialize(modelPath: modelPath, engine: engine);
    }

    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input audio file not found', inputPath);
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${dir.path}/filtered_$timestamp.wav';

    try {
      final result = await _channel.invokeMethod<bool>('processAudioFile', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'modelPath': modelPath,
        'engine': engine,
      });

      if (result == true && await File(outputPath).exists()) {
        debugPrint('NoiseFilter: Successfully filtered audio ($engine) → $outputPath');
        return outputPath;
      }
    } on PlatformException catch (e) {
      debugPrint('NoiseFilter: Processing error: ${e.message}');
    }

    // Fallback: return original file if filtering fails
    debugPrint('NoiseFilter: Falling back to original audio');
    return inputPath;
  }

  /// Resample a 48kHz WAV file to 16kHz for Whisper compatibility.
  /// This helps avoid SIGILL crashes in Whisper's native resampler on some CPUs.
  Future<String> resampleTo16kHz(String inputPath) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input audio file not found', inputPath);
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${dir.path}/resampled_$timestamp.wav';

    try {
      final success = await _channel.invokeMethod<bool>('resampleTo16kHz', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });

      if (success == true && await File(outputPath).exists()) {
        debugPrint('NoiseFilter: Successfully resampled audio to 16kHz → $outputPath');
        return outputPath;
      }
    } catch (e) {
      debugPrint('NoiseFilter: Resampling error: $e');
    }

    // If resampling fails, return input path and hope Whisper can handle it
    return inputPath;
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } catch (e) {
      debugPrint('NoiseFilter: Dispose error: $e');
    }
    _isInitialized = false;
  }
}
