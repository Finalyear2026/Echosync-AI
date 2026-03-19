import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Manages downloading and storage of AI model files.
/// Supports resumable downloads with progress tracking.
class ModelManagerService {
  final Dio _dio = Dio();
  final Map<String, double> _downloadProgress = {};
  final Map<String, CancelToken> _cancelTokens = {};

  static const String registryDriveId = '1sMAYeFQlzuya_ncuj0fz9XkypVd8J9S0';
  
  /// Get direct download link for Google Drive ID
  String _getDriveDownloadUrl(String fileId) => 
      'https://drive.google.com/uc?export=download&id=$fileId';

  /// Fetch the cloud registry from Google Drive
  Future<Map<String, dynamic>> fetchCloudRegistry() async {
    try {
      final response = await _dio.get(
        _getDriveDownloadUrl(registryDriveId),
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data;
        } else if (data is String) {
          return jsonDecode(data) as Map<String, dynamic>;
        }
        throw Exception('Unexpected response format: ${data.runtimeType}');
      }
      throw Exception('Failed to fetch registry: ${response.statusCode}');
    } catch (e) {
      debugPrint('ModelManager: Registry fetch error: $e');
      rethrow;
    }
  }

  /// Model definitions (Static fallbacks)
  static const Map<String, ModelInfo> models = {
    'whisper-base': ModelInfo(
      name: 'Whisper Base',
      filename: 'ggml-base.bin',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      sizeBytes: 150000000,
      description: 'Fast, lightweight speech-to-text (~150MB)',
    ),
    'whisper-small': ModelInfo(
      name: 'Whisper Small',
      filename: 'ggml-small.bin',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      sizeBytes: 250000000,
      description: 'Balanced accuracy and speed (~250MB)',
    ),
    'whisper-medium': ModelInfo(
      name: 'Whisper Medium',
      filename: 'ggml-medium.bin',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
      sizeBytes: 500000000,
      description: 'High accuracy speech-to-text (~500MB)',
    ),
    'whisper-large-v3-turbo': ModelInfo(
      name: 'Whisper Large V3 Turbo',
      filename: 'ggml-large-v3-turbo.bin',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin',
      sizeBytes: 850000000,
      description: 'Best accuracy, bilingual (EN/UR) (~850MB)',
    ),
    'qwen2.5-1.5b': ModelInfo(
      name: 'Qwen2.5 1.5B Instruct',
      filename: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeBytes: 950000000,
      description: 'Smart text formatting engine (~950MB)',
    ),
  };

  /// Get the model storage directory
  Future<String> get modelsDir async {
    // We use getExternalStorageDirectory so files are visible via PC (MTP)
    // On Android: Android/data/com.echosync.echosync_ai/files/models/
    var dir = await getExternalStorageDirectory();
    dir ??= await getApplicationDocumentsDirectory(); // Fallback to internal if needed
    
    final modelsPath = '${dir.path}/models';
    await Directory(modelsPath).create(recursive: true);
    return modelsPath;
  }

  /// Check if a model exists locally and is valid
  Future<bool> isModelDownloaded(String modelId, {int? expectedSize, String? filename, bool isZip = false}) async {
    final info = models[modelId];
    final actualFilename = filename ?? info?.filename;
    final actualExpectedSize = expectedSize ?? info?.sizeBytes ?? 0;

    if (actualFilename == null) return false;
    
    final modelsDirPath = await modelsDir;
    
    if (isZip) {
      // Check for extracted directory (e.g. DeepFilterNet3)
      final dirName = p.basenameWithoutExtension(actualFilename);
      final dir = Directory(p.join(modelsDirPath, dirName));
      if (dir.existsSync()) return true;
      
      // Also check for the ZIP file if not yet extracted
      final zipFile = File(p.join(modelsDirPath, actualFilename));
      if (zipFile.existsSync()) {
        final size = await zipFile.length();
        return size >= actualExpectedSize * 0.90;
      }
      return false;
    }

    final path = p.join(modelsDirPath, actualFilename);
    final file = File(path);
    if (!file.existsSync()) return false;

    // Check size (90% threshold for flexibility)
    final size = await file.length();
    final isValid = actualExpectedSize <= 0 || size >= actualExpectedSize * 0.90;
    
    if (!isValid) {
      debugPrint('ModelManager: $modelId found but INVALID size: $size vs $actualExpectedSize');
    }
    return isValid;
  }

  /// Delete corrupted or incomplete model files
  Future<void> validateModelFiles() async {
    for (final key in models.keys) {
      final info = models[key]!;
      final path = p.join(await modelsDir, info.filename);
      final file = File(path);
      if (file.existsSync()) {
        final size = await file.length();
        if (size < info.sizeBytes * 0.9) {
          debugPrint('ModelManager: Deleting corrupted model: $key');
          try {
            await file.delete();
          } catch (e) {
            debugPrint('ModelManager: Error deleting $key: $e');
          }
        }
      }
    }
  }

  /// Get the local path for a model
  Future<String> getModelPath(String modelKey) async {
    final info = models[modelKey];
    if (info == null) throw ArgumentError('Unknown model: $modelKey');
    return p.join(await modelsDir, info.filename);
  }

  /// Get download progress for a model (0.0 to 1.0)
  double getProgress(String modelKey) => _downloadProgress[modelKey] ?? 0.0;

  /// Download a model file with progress tracking and resume support
  Future<String> downloadModel(
    String modelKey, {
    String? driveId,
    bool isZip = false,
    int? expectedSize,
    String? filename,
    ValueChanged<DownloadProgressInfo>? onProgress,
  }) async {
    final info = models[modelKey];
    final actualFilename = filename ?? info?.filename ?? (isZip ? '$modelKey.zip' : '$modelKey.bin');
    final actualExpectedSize = expectedSize ?? info?.sizeBytes ?? 0;

    final modelsDirPath = await modelsDir;
    final filePath = p.join(modelsDirPath, actualFilename);
    final file = File(filePath);
    final tempPath = '$filePath.part';
    final tempFile = File(tempPath);

    // 1. Check if already downloaded and valid
    if (actualExpectedSize > 0 && file.existsSync()) {
      final size = await file.length();
      if (size >= actualExpectedSize * 0.95) {
        _downloadProgress[modelKey] = 1.0;
        onProgress?.call(DownloadProgressInfo(
          progress: 1.0,
          downloadedBytes: size,
          totalBytes: size,
          speedBytesPerSecond: 0,
        ));
        return filePath;
      }
      await file.delete();
    }

    // 2. Resume logic
    int existingLength = 0;
    if (tempFile.existsSync()) {
      existingLength = await tempFile.length();
    }

    final cancelToken = CancelToken();
    _cancelTokens[modelKey] = cancelToken;
    
    final startTime = DateTime.now();
    int lastReceived = 0;
    DateTime lastTime = startTime;
    final url = driveId != null ? _getDriveDownloadUrl(driveId) : (info?.url ?? '');

    try {
      await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final duration = now.difference(lastTime).inMilliseconds;
          
          double speed = 0;
          if (duration > 500) { // Update speed every 500ms for stability
            speed = (received - lastReceived) / (duration / 1000.0);
            lastReceived = received;
            lastTime = now;
          }

          final totalWithExisting = existingLength + total;
          final receivedWithExisting = existingLength + received;
          final progress = receivedWithExisting / totalWithExisting;
          
          _downloadProgress[modelKey] = progress;
          onProgress?.call(DownloadProgressInfo(
            progress: progress,
            downloadedBytes: receivedWithExisting,
            totalBytes: totalWithExisting,
            speedBytesPerSecond: speed,
          ));
        },
        options: Options(
          headers: existingLength > 0 ? {'range': 'bytes=$existingLength-'} : null,
          receiveTimeout: const Duration(hours: 2),
          responseType: ResponseType.stream,
        ),
        deleteOnError: false, 
      );

      // 3. Finalize file
      await tempFile.rename(filePath);
      
      // 4. Handle Zip extraction
      if (isZip) {
        await _extractZip(filePath, modelsDirPath);
      }

      _downloadProgress[modelKey] = 1.0;
      final finalSize = await File(filePath).length();
      onProgress?.call(DownloadProgressInfo(
        progress: 1.0,
        downloadedBytes: finalSize,
        totalBytes: finalSize,
        speedBytesPerSecond: 0,
      ));
      return filePath;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw Exception('Download cancelled');
      }
      rethrow;
    } finally {
      _cancelTokens.remove(modelKey);
    }
  }

  /// Extract zip file to directory
  Future<void> _extractZip(String zipPath, String targetDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File(p.join(targetDir, filename))
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory(p.join(targetDir, filename)).createSync(recursive: true);
      }
    }
    // Delete zip after extraction to save space
    await File(zipPath).delete();
  }

  /// Cancel a running download
  void cancelDownload(String modelKey) {
    _cancelTokens[modelKey]?.cancel('User cancelled download');
    _cancelTokens.remove(modelKey);
    _downloadProgress.remove(modelKey);
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId, {String? filename, bool isZip = false}) async {
    final info = models[modelId];
    final actualFilename = filename ?? info?.filename;
    if (actualFilename == null) return;
    
    final modelsDirPath = await modelsDir;
    
    try {
      if (isZip) {
        final dirName = p.basenameWithoutExtension(actualFilename);
        final dir = Directory(p.join(modelsDirPath, dirName));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          debugPrint('ModelManager: Deleted directory $dirName');
        }
        
        // Also delete the ZIP if it exists
        final zipFile = File(p.join(modelsDirPath, actualFilename));
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      } else {
        final path = p.join(modelsDirPath, actualFilename);
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('ModelManager: Deleted file $actualFilename');
        }
      }
    } catch (e) {
      debugPrint('ModelManager: ERROR during deletion: $e');
      // If we get an error, it's often due to a file lock on Android/MTP
      throw Exception('Could not delete model. It might be in use by the app or Windows File Explorer. Try restarting the app.');
    }
    
    _downloadProgress.remove(modelId);
  }
  /// Get status of all models
  /// Can take map of dynamic models to check: {modelId: {'filename': '...', 'sizeBytes': ...}}
  Future<Map<String, bool>> getModelStatuses({Map<String, dynamic>? dynamicModels}) async {
    final statuses = <String, bool>{};
    
    // Check static models
    for (final key in models.keys) {
      statuses[key] = await isModelDownloaded(key);
    }
    
    // Check dynamic models
    if (dynamicModels != null) {
      for (final entry in dynamicModels.entries) {
        final id = entry.key;
        final meta = entry.value as Map<String, dynamic>;
        statuses[id] = await isModelDownloaded(
          id, 
          filename: meta['filename'], 
          expectedSize: meta['size_bytes'],
          isZip: meta['is_zip'] ?? false,
        );
      }
    }
    return statuses;
  }

  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel('Service disposed');
    }
    _cancelTokens.clear();
    _downloadProgress.clear();
  }
}

/// Model information
class ModelInfo {
  final String name;
  final String filename;
  final String url;
  final int sizeBytes;
  final String description;

  const ModelInfo({
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeBytes,
    required this.description,
  });

  String get sizeMB => '${(sizeBytes / 1000000).round()} MB';
}

/// Detailed progress information for model downloads
class DownloadProgressInfo {
  final double progress; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;

  DownloadProgressInfo({
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
  });

  String get downloadedMB => (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
  String get totalMB => (totalBytes / (1024 * 1024)).toStringAsFixed(1);
  
  String get speedText {
    if (speedBytesPerSecond <= 0) return '0 KB/s';
    if (speedBytesPerSecond > 1024 * 1024) {
      return '${(speedBytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(speedBytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
  }

  String get percentageText => '${(progress * 100).toStringAsFixed(1)}%';
}
