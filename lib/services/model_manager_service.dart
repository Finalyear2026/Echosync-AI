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
    final dir = await getApplicationDocumentsDirectory();
    final modelsPath = '${dir.path}/models';
    await Directory(modelsPath).create(recursive: true);
    return modelsPath;
  }

  /// Check if a model file exists locally and is valid (correct size)
  Future<bool> isModelDownloaded(String modelKey) async {
    final info = models[modelKey];
    if (info == null) return false;
    final path = '${await modelsDir}/${info.filename}';
    final file = File(path);
    if (!file.existsSync()) return false;

    // Check size — must be at least 95% of expected size to be considered valid
    final size = await file.length();
    final isValid = size >= info.sizeBytes * 0.95;
    if (!isValid) {
      debugPrint('ModelManager: $modelKey file found but INVALID size: '
          '$size vs expected ${info.sizeBytes}');
    }
    return isValid;
  }

  /// Delete corrupted or incomplete model files
  Future<void> validateModelFiles() async {
    for (final key in models.keys) {
      final info = models[key]!;
      final path = '${await modelsDir}/${info.filename}';
      final file = File(path);
      if (file.existsSync()) {
        final size = await file.length();
        if (size < info.sizeBytes * 0.9) {
          debugPrint('ModelManager: Deleting corrupted model: $key ($size bytes)');
          await file.delete();
        }
      }
    }
  }

  /// Get the local path for a model
  Future<String> getModelPath(String modelKey) async {
    final info = models[modelKey];
    if (info == null) throw ArgumentError('Unknown model: $modelKey');
    return '${await modelsDir}/${info.filename}';
  }

  /// Get download progress for a model (0.0 to 1.0)
  double getProgress(String modelKey) => _downloadProgress[modelKey] ?? 0.0;

  /// Download a model file with progress tracking and resume support
  Future<String> downloadModel(
    String modelKey, {
    String? driveId,
    bool isZip = false,
    ValueChanged<double>? onProgress,
  }) async {
    final info = models[modelKey];
    final filename = info?.filename ?? (isZip ? '$modelKey.zip' : '$modelKey.bin');
    final expectedSize = info?.sizeBytes ?? 0;

    final modelsDirPath = await modelsDir;
    final filePath = '$modelsDirPath/$filename';
    final file = File(filePath);
    final tempPath = '$filePath.part';
    final tempFile = File(tempPath);

    // 1. Check if already downloaded and valid
    if (file.existsSync()) {
      final size = await file.length();
      if (size >= expectedSize * 0.95) {
        _downloadProgress[modelKey] = 1.0;
        onProgress?.call(1.0);
        return filePath;
      }
      // If file exists but is too small, delete it and use temp logic
      await file.delete();
    }

    // 2. Resume logic
    int existingLength = 0;
    if (tempFile.existsSync()) {
      existingLength = await tempFile.length();
    }

    final cancelToken = CancelToken();
    _cancelTokens[modelKey] = cancelToken;
    
    final url = driveId != null ? _getDriveDownloadUrl(driveId) : (info?.url ?? '');

    try {
      await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final progress = (existingLength + received) / (existingLength + total);
          _downloadProgress[modelKey] = progress;
          onProgress?.call(progress);
        },
        options: Options(
          headers: existingLength > 0 ? {'range': 'bytes=$existingLength-'} : null,
          receiveTimeout: const Duration(hours: 2),
          responseType: ResponseType.stream,
        ),
        deleteOnError: false, // Keep partial file for resume
      );

      // 3. Finalize file
      await tempFile.rename(filePath);
      
      // 4. Handle Zip extraction
      if (isZip) {
        await _extractZip(filePath, modelsDirPath);
      }

      _downloadProgress[modelKey] = 1.0;
      onProgress?.call(1.0);
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
        File('$targetDir/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory('$targetDir/$filename').createSync(recursive: true);
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
  Future<void> deleteModel(String modelKey) async {
    final info = models[modelKey];
    if (info == null) return;
    final path = '${await modelsDir}/${info.filename}';
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      _downloadProgress.remove(modelKey);
      debugPrint('ModelManager: Deleted $modelKey from $path');
    }
  }

  /// Get status of all models
  Future<Map<String, bool>> getModelStatuses() async {
    final statuses = <String, bool>{};
    for (final key in models.keys) {
      statuses[key] = await isModelDownloaded(key);
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
