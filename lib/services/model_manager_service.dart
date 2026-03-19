import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'logging_service.dart';

/// Manages downloading and storage of AI model files.
/// Supports resumable downloads with progress tracking.
class ModelManagerService {
  final Dio _dio = Dio();
  final Map<String, double> _downloadProgress = {};
  final Map<String, CancelToken> _cancelTokens = {};

  static const String registryUrl = 'https://raw.githubusercontent.com/ahmadali8186105/echosync_ai_registry/refs/heads/main/models.json';
  
  /// Get direct download link for Google Drive ID
  String _getDriveDownloadUrl(String fileId) => 
      'https://drive.google.com/uc?export=download&id=$fileId';

  /// Fetch the cloud registry from GitHub
  Future<Map<String, dynamic>> fetchCloudRegistry() async {
    try {
      final response = await _dio.get(
        registryUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          // We add a timestamp or clear cache to ensure we get the latest file
          extra: {'_ts': DateTime.now().millisecondsSinceEpoch},
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
      throw Exception('Failed to fetch registry from GitHub: ${response.statusCode}');
    } catch (e) {
      debugPrint('ModelManager: GitHub registry fetch error: $e');
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
    
    LoggingService().log(
      'Checking model presence',
      category: 'MODELS_DEBUG',
      details: {
        'modelId': modelId,
        'isZip': isZip,
        'filename': actualFilename,
        'expectedSize': actualExpectedSize,
        'dirPath': modelsDirPath,
      },
    );

    // 1. Check for extracted directory (always check this first for robustness)
    final dirName = p.basenameWithoutExtension(actualFilename);
    final dir = Directory(p.join(modelsDirPath, dirName));
    if (dir.existsSync()) {
      LoggingService().log('Found exact extracted directory', category: 'MODELS_DEBUG', details: {'path': dir.path});
      return true;
    }

    // Try a few common variations or check the modelsDirPath for any common subfolders
    // If it's a zip and the zip file is missing but we've seen it before, 
    // we could check the models directory for non-zip entries
    try {
      if (isZip) {
        final dirEntries = Directory(modelsDirPath).listSync();
        for (final entry in dirEntries) {
          if (entry is Directory) {
            final entryName = p.basename(entry.path).toLowerCase();
            final targetName = dirName.toLowerCase();
            // Match if entry starts with or is similar to our targetName
            if (entryName == targetName || entryName.contains(targetName) || targetName.contains(entryName)) {
               LoggingService().log('Found similar extracted directory', category: 'MODELS_DEBUG', details: {'found': entryName, 'target': targetName});
               return true;
            }
          }
        }
      }
    } catch (e) {
      // Ignore list errors
    }

    // 2. Check for the file itself (either the model bin or the zip file)
    final file = File(p.join(modelsDirPath, actualFilename));
    if (file.existsSync()) {
      final size = await file.length();
      // Use a more relaxed size check for partial/compressed files (90% threshold)
      final isValid = actualExpectedSize <= 0 || size >= actualExpectedSize * 0.90;
      
      LoggingService().log(
        'Found file',
        category: 'MODELS_DEBUG',
        details: {'path': file.path, 'size': size, 'isValid': isValid},
      );
      return isValid;
    }

    LoggingService().log('No model folder or file found', category: 'MODELS_DEBUG', details: {'modelId': modelId});
    return false;
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
    if (await isModelDownloaded(modelKey, expectedSize: actualExpectedSize, filename: actualFilename, isZip: isZip)) {
      _downloadProgress[modelKey] = 1.0;
      onProgress?.call(DownloadProgressInfo(
        progress: 1.0,
        downloadedBytes: actualExpectedSize,
        totalBytes: actualExpectedSize,
        speedBytesPerSecond: 0,
      ));
      return filePath;
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
    double currentSpeed = 0;
    DateTime lastTime = startTime;
    final url = driveId != null ? _getDriveDownloadUrl(driveId) : (info?.url ?? '');

    try {
    final raf = await tempFile.open(mode: FileMode.append);
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: existingLength > 0 ? {'range': 'bytes=$existingLength-'} : null,
          receiveTimeout: const Duration(hours: 2),
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // Handle server responding with full content (200) instead of partial (206)
      // This happens if the server doesn't support the range header
      int currentExistingLength = existingLength;
      if (response.statusCode == 200) {
        currentExistingLength = 0;
        await raf.setPosition(0);
        await raf.truncate(0);
      } else if (response.statusCode != 206 && existingLength > 0) {
        // Some other status - if we expected partial but didn't get it, reset to be safe
        currentExistingLength = 0;
        await raf.setPosition(0);
        await raf.truncate(0);
      }

      final stream = response.data!.stream;
      int received = 0;
      final total = int.tryParse(response.headers.value('content-length') ?? '-1') ?? -1;

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) {
          throw DioException(requestOptions: response.requestOptions, type: DioExceptionType.cancel);
        }

        await raf.writeFrom(chunk);
        received += chunk.length;

        final now = DateTime.now();
        final duration = now.difference(lastTime).inMilliseconds;
        if (duration > 500) {
          currentSpeed = (received - lastReceived) / (duration / 1000.0);
          lastReceived = received;
          lastTime = now;
        }

        final absoluteReceived = currentExistingLength + received;
        final absoluteTotal = total > 0 ? (currentExistingLength + total) : (actualExpectedSize > 0 ? actualExpectedSize : -1);
        final progress = absoluteTotal > 0 ? (absoluteReceived / absoluteTotal) : 0.0;

        _downloadProgress[modelKey] = progress;
        onProgress?.call(DownloadProgressInfo(
          progress: progress,
          downloadedBytes: absoluteReceived,
          totalBytes: absoluteTotal > 0 ? absoluteTotal : absoluteReceived,
          speedBytesPerSecond: currentSpeed,
        ));
      }
    } finally {
      await raf.close();
    }

      // 3. Finalize file
      await tempFile.rename(filePath);
      
      final finalSize = await File(filePath).length();
      _downloadProgress[modelKey] = 1.0;
      onProgress?.call(DownloadProgressInfo(
        progress: 1.0,
        downloadedBytes: finalSize,
        totalBytes: finalSize,
        speedBytesPerSecond: 0,
      ));

      // 4. Handle Zip extraction
      if (isZip) {
        LoggingService().log('Extracting model zip', category: 'MODELS', details: {'path': filePath});
        try {
          await _extractZip(filePath, modelsDirPath);
          LoggingService().log('Extraction complete, zip deleted', category: 'MODELS');
        } catch (e) {
          LoggingService().log('Extraction failed', category: 'MODELS_ERROR', details: {'error': e.toString()});
          // If extraction fails, we still have the zip
          rethrow;
        }
      }

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

  /// Extract zip file to directory with optimal memory usage (uses streaming)
  Future<void> _extractZip(String zipPath, String modelsDirPath) async {
    // We use InputFileStream for large model files to avoid reading everything into memory (OOM)
    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        // Extract directly into the models directory (Extract Here)
        File(p.join(modelsDirPath, filename))
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory(p.join(modelsDirPath, filename)).createSync(recursive: true);
      }
    }
    
    // Explicitly close the stream before attempting to delete
    await inputStream.close();
    
    // Delete zip after extraction to save space
    final zipFile = File(zipPath);
    if (await zipFile.exists()) {
      await zipFile.delete();
    }
  }

  /// Get progress info for a partial download to restore UI state
  Future<DownloadProgressInfo?> getPartialDownloadInfo(String modelId, {String? filename, int? expectedSize}) async {
    final info = models[modelId];
    final actualFilename = filename ?? info?.filename;
    final actualSize = expectedSize ?? info?.sizeBytes ?? 0;
    if (actualFilename == null || actualSize <= 0) return null;
    
    final modelsDirPath = await modelsDir;
    final tempFile = File(p.join(modelsDirPath, '$actualFilename.part'));
    if (await tempFile.exists()) {
      final downloaded = await tempFile.length();
      return DownloadProgressInfo(
        progress: downloaded / actualSize,
        downloadedBytes: downloaded,
        totalBytes: actualSize,
        speedBytesPerSecond: 0,
      );
    }
    return null;
  }

  /// Check if a model has a partial download file
  Future<bool> isModelPartiallyDownloaded(String modelId, {String? filename}) async {
    final info = models[modelId];
    final actualFilename = filename ?? info?.filename;
    if (actualFilename == null) return false;
    
    final modelsDirPath = await modelsDir;
    final tempPath = p.join(modelsDirPath, '$actualFilename.part');
    return File(tempPath).exists();
  }

  /// Pause a running download (removes token but keeps progress)
  void pauseDownload(String modelKey) {
    _cancelTokens[modelKey]?.cancel('User paused download');
    _cancelTokens.remove(modelKey);
    // Note: We DON'T remove _downloadProgress[modelKey] so we can show it in UI
  }

  /// Cancel a running download and optionally delete the partial file
  Future<void> cancelDownload(String modelKey, {String? filename}) async {
    _cancelTokens[modelKey]?.cancel('User cancelled download');
    _cancelTokens.remove(modelKey);
    _downloadProgress.remove(modelKey);
    
    // Optionally delete the partial file
    final info = models[modelKey];
    final actualFilename = filename ?? info?.filename;
    if (actualFilename != null) {
      final modelsDirPath = await modelsDir;
      final tempPath = p.join(modelsDirPath, '$actualFilename.part');
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
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
