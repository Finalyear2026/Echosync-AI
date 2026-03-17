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

  bool get isAvailable => _isAvailable;

  /// Initialize the noise filter engine
  Future<bool> initialize() async {
    try {
      _isAvailable = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      final result = await _channel.invokeMethod<bool>('initialize') ?? false;
      _isInitialized = result;
      debugPrint('NoiseFilter: Initialized=$_isInitialized, Available=$_isAvailable');
      return _isInitialized;
    } on PlatformException catch (e) {
      debugPrint('NoiseFilter: Init error: ${e.message}');
      _isInitialized = true; // Allow passthrough
      _isAvailable = false;
      return true;
    } catch (e) {
      debugPrint('NoiseFilter: Unexpected init error: $e');
      _isInitialized = true;
      _isAvailable = false;
      return true;
    }
  }

  /// Process an audio file through noise suppression.
  /// Returns the path to the cleaned audio file.
  Future<String> processAudioFile(String inputPath) async {
    if (!_isInitialized) {
      await initialize();
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
      });

      if (result == true && await File(outputPath).exists()) {
        debugPrint('NoiseFilter: Successfully filtered audio → $outputPath');
        return outputPath;
      }
    } on PlatformException catch (e) {
      debugPrint('NoiseFilter: Processing error: ${e.message}');
    }

    // Fallback: return original file if filtering fails
    debugPrint('NoiseFilter: Falling back to original audio');
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
