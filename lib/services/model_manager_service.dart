import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;
import 'logging_service.dart';
import 'settings_service.dart';

/// Manages downloading and storage of AI model files.
/// Supports resumable downloads with progress tracking.
class ModelManagerService {
  final Dio _dio = Dio();
  final Map<String, double> _downloadProgress = {};
  final Map<String, CancelToken> _cancelTokens = {};

  static const String registryUrl = 'https://raw.githubusercontent.com/ahmadali8186105/echosync_ai_registry/refs/heads/main/models.json';
  
  /// Get the local registry file path
  Future<File> get _localRegistryFile async {
    final mDir = await modelsDir;
    final path = p.join(mDir, 'models.json');
    return File(path);
  }

  /// Ensure the local registry exists (copies from assets on first run)
  Future<void> ensureLocalRegistryExists() async {
    final file = await _localRegistryFile;
    if (!file.existsSync()) {
      LoggingService().log('Local registry missing, copying from assets', category: 'MODELS');
      try {
        final data = await rootBundle.loadString('assets/models.json');
        await file.writeAsString(data);
        LoggingService().log('Asset registry copied successfully', category: 'MODELS');
      } catch (e) {
        LoggingService().log('Failed to copy asset registry', category: 'MODELS_ERROR', details: {'error': e.toString()});
      }
    }
  }

  /// Load the current local registry content
  Future<Map<String, dynamic>> loadLocalRegistry() async {
    await ensureLocalRegistryExists();
    final file = await _localRegistryFile;
    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      LoggingService().log('Failed to read local registry', category: 'MODELS_ERROR', details: {'error': e.toString()});
      return {'categories': []}; // Fallback
    }
  }

  /// Fetch the cloud registry with ETag support and atomic updates
  Future<Map<String, dynamic>?> syncRegistryWithCloud(SettingsService settings) async {
    try {
      final currentEtag = settings.getRegistryEtag();
      
      final response = await _dio.get(
        registryUrl,
        options: Options(
          headers: currentEtag != null ? {'If-None-Match': currentEtag} : null,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          validateStatus: (status) => status != null && (status == 200 || status == 304),
        ),
      );

      if (response.statusCode == 304) {
        LoggingService().log('Registry not modified (304)', category: 'MODELS');
        return null; // No update needed
      }

      if (response.statusCode == 200) {
        final data = response.data;
        final newEtag = response.headers.value('etag');
        
        LoggingService().log('New registry version found', category: 'MODELS', details: {'etag': newEtag});

        // Atomic Swap: Write to temp file first
        final file = await _localRegistryFile;
        final tempFile = File(p.join(file.parent.path, 'models_temp.json'));
        
        String content;
        if (data is Map) {
          content = jsonEncode(data);
        } else {
          content = data.toString();
        }

        await tempFile.writeAsString(content);
        
        // Finalize: Rename temp to original
        if (file.existsSync()) await file.delete();
        await tempFile.rename(file.path);

        if (newEtag != null) {
          await settings.setRegistryEtag(newEtag);
        }

        return data is Map<String, dynamic> ? data : jsonDecode(content);
      }
      
      return null;
    } catch (e) {
      LoggingService().log('Registry sync error', category: 'MODELS_ERROR', details: {'error': e.toString()});
      return null;
    }
  }

  /// Fetch the cloud registry from GitHub (load local first)
  Future<Map<String, dynamic>> fetchCloudRegistry() async {
    return loadLocalRegistry();
  }

  /// Get direct download link for Google Drive ID
  String _getDriveDownloadUrl(String fileId) => 
      'https://drive.google.com/uc?export=download&id=$fileId';

  /// Model definitions (Static fallbacks matching models.json IDs)
  static const Map<String, ModelInfo> models = {
    'whisper_base': ModelInfo(
      name: 'Whisper Base',
      filename: 'whisper_base.zip',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      sizeBytes: 133064207,
      description: 'Fast, lightweight speech-to-text (~150MB)',
    ),
    'whisper_small': ModelInfo(
      name: 'Whisper Small',
      filename: 'whisper_small.zip',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      sizeBytes: 446077769,
      description: 'Balanced accuracy and speed (~250MB)',
    ),
    'whisper_medium': ModelInfo(
      name: 'Whisper Medium',
      filename: 'whisper_medium.zip',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
      sizeBytes: 1412421232,
      description: 'High accuracy speech-to-text (~1.4GB)',
    ),
    'whisper_large_turbo': ModelInfo(
      name: 'Whisper Large Turbo V3',
      filename: 'whisper_large_turbo_v3.zip',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin',
      sizeBytes: 1492498810,
      description: 'Best accuracy, bilingual (EN/UR) (~1.5GB)',
    ),
    'qwen_2_5_1_5b': ModelInfo(
      name: 'Qwen2.5 1.5B Instruct',
      filename: 'qwen2_5__1_5b_instruct_q4_k_m.zip',
      url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeBytes: 1091276760,
      description: 'Smart text formatting engine (~1.1GB)',
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

  /// Get the local path for a model binary
  Future<String> getModelPath(String modelKey) async {
    final info = models[modelKey];
    if (info == null) throw ArgumentError('Unknown model: $modelKey');
    
    final modelsDirPath = await modelsDir;
    
    // 1. Check for extracted directory (Zipped models)
    final dirName = p.basenameWithoutExtension(info.filename);
    final dir = Directory(p.join(modelsDirPath, dirName));
    if (dir.existsSync()) {
      try {
        // Recursive search for the actual binary/checkpoint
        final entries = dir.listSync(recursive: true);
        for (final entry in entries) {
           if (entry is File) {
             final ext = p.extension(entry.path).toLowerCase();
             // Support .bin (Whisper), .gguf (Llama), and .ckpt (DeepFilterNet)
             if (ext == '.bin' || ext == '.gguf' || ext == '.ckpt' || entry.path.endsWith('.ckpt.best')) {
               return entry.path;
             }
           }
        }
      } catch (e) {
        debugPrint('ModelManager: Error searching folder: $e');
      }
    }
    
    // 2. Fallback to direct file (Not a zip or folder not found)
    return p.join(modelsDirPath, info.filename);
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
      // Handle Google Drive Large File "Confirm" logic
      String finalUrl = url;
      String? cookieHeader;

      if (driveId != null) {
        // Use a browser-like User-Agent to avoid being blocked as a bot
        const browserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
        
        final initialResponse = await _dio.get(
          url,
          options: Options(
            followRedirects: true,
            responseType: ResponseType.plain,
            headers: {'User-Agent': browserUserAgent},
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        
        // Extract cookies to maintain session for the confirmation
        final setCookies = initialResponse.headers['set-cookie'];
        if (setCookies != null && setCookies.isNotEmpty) {
          // Join all cookies, taking only the key=value part
          cookieHeader = setCookies.map((c) => c.split(';').first).join('; ');
        }

        // Check if we got the "virus scan" warning page or login page
        final body = initialResponse.data.toString();
        
        // Check for common error messages
        if (body.contains('Google Drive - Quota exceeded') || 
            body.contains('too many users have viewed or downloaded this file')) {
          throw Exception('Google Drive download quota exceeded for this file. Please try again in 24 hours or choose a different model.');
        }

        // Improved Token extraction from multiple possible locations in the HTML
        String? confirmToken;
        
        // Pattern 1: confirm=TOKEN in URL/links
        final urlMatch = RegExp(r'confirm=([a-zA-Z0-9_-]+)').firstMatch(body);
        if (urlMatch != null) {
          confirmToken = urlMatch.group(1);
        } else {
          // Pattern 2: <input type="hidden" name="confirm" value="TOKEN">
          final inputMatch = RegExp(r'name="confirm"\s+value="([^"]+)"').firstMatch(body) ?? 
                            RegExp(r'value="([^"]+)"\s+name="confirm"').firstMatch(body);
          if (inputMatch != null) {
            confirmToken = inputMatch.group(1);
          } else {
            // Pattern 3: Look for confirm in the entire body strings (more aggressive)
            final genericMatch = RegExp(r'confirm=([a-zA-Z0-9_-]+)').firstMatch(body);
            if (genericMatch != null) {
              confirmToken = genericMatch.group(1);
            }
          }
        }

        if (confirmToken != null) {
          // Use the secure download domain
          finalUrl = 'https://drive.usercontent.google.com/download?id=$driveId&confirm=$confirmToken&export=download';
          LoggingService().log('GDrive large file: using confirm token', category: 'MODELS', details: {'token': confirmToken});
        } 
        // Pattern 4: static t as fallback if still nothing found but suspected large file
        else if (body.contains('confirm=t') || body.contains('download-form') || body.contains('Download anyway')) {
          finalUrl = '$url&confirm=t';
          LoggingService().log('GDrive large file: using static confirm token (t)', category: 'MODELS');
        }
      }

      final response = await _dio.get<ResponseBody>(
        finalUrl,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            if (existingLength > 0) 'range': 'bytes=$existingLength-',
            if (cookieHeader != null) 'cookie': cookieHeader,
          },
          receiveTimeout: const Duration(hours: 4),
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // Validate that we are not downloading an HTML page (error page) 
      // when we expect a large binary model
      final contentType = response.headers.value('content-type') ?? '';
      if (contentType.contains('text/html') && actualExpectedSize > 100000) {
        // If we still get HTML after confirmation, it might be a block or a quota limit
        final checkBodyResponse = await _dio.get(finalUrl, options: Options(responseType: ResponseType.plain, headers: {'User-Agent': 'Mozilla/5.0'}));
        final errBody = checkBodyResponse.data.toString();
        if (errBody.contains('quota') || errBody.contains('exceeded')) {
           throw Exception('Google Drive quota exceeded. Try again in 24h or use a smaller model.');
        }
        throw Exception('Download failed: Google Drive is still serving a warning page. This usually happens if the automated confirmation is blocked. Please try one more time or check if your internet has restrictions.');
      }


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
      
      // Guard against suspiciously small downloads from Google Drive (likely warning pages)
      if (total > 0 && total < 50000 && actualExpectedSize > 1000000) {
         throw Exception('Download failed: Received incomplete file. This usually happens when Google Drive blocks automated downloads. Try again in a few minutes.');
      }


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
      
      // Verification: Check for size mismatch
      if (actualExpectedSize > 0 && finalSize < actualExpectedSize * 0.9) {
        // If it's a ZIP, it might be slightly smaller but not 10x smaller
        if (finalSize < 100000) { // Under 100KB is definitely wrong for these models
           throw Exception('Download failed: The saved file is too small ($finalSize bytes). It is likely a corrupted error page.');
        }
      }

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
