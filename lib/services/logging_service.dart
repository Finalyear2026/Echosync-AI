import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Service for detailed logging to a text file for debugging.
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  File? _logFile;

  /// Initialize the log file in the Android app-specific external directory.
  Future<void> init() async {
    try {
      // Android/data/com.echosync.echosync_ai/files/ logs.txt
      final Directory? dir = await getExternalStorageDirectory();
      if (dir != null) {
        _logFile = File('${dir.path}/logs.txt');
        if (!await _logFile!.exists()) {
          await _logFile!.create(recursive: true);
        }
        await log('--- LOGGING SESSION INITIALIZED ---', category: 'SYSTEM');
      }
    } catch (e) {
      debugPrint('LoggingService Init Error: $e');
    }
  }

  /// Write a detailed log entry with timestamp and category.
  Future<void> log(String message, {String? category, Map<String, dynamic>? details}) async {
    try {
      if (_logFile == null) {
        final Directory? dir = await getExternalStorageDirectory();
        if (dir != null) {
          _logFile = File('${dir.path}/logs.txt');
          if (!await _logFile!.exists()) {
            await _logFile!.create(recursive: true);
          }
        }
      }
      
      if (_logFile == null) {
        debugPrint('LoggingService: Could not access log file storage.');
        return;
      }

      final timestamp = DateTime.now().toString();
      final catStr = category != null ? '[$category] ' : '';
      
      String logEntry = '$timestamp $catStr$message';
      if (details != null && details.isNotEmpty) {
        logEntry += '\nDetails: $details';
      }
      
      // Ensure the message ends with a newline and extra spacing for readability
      await _logFile!.writeAsString(
        '$logEntry\n\n',
        mode: FileMode.append,
        flush: true,
      );
      
      // Also print to console for easier debugging during development
      debugPrint('FILE_LOG: $logEntry');
    } catch (e) {
      debugPrint('LoggingService Log Error: $e');
    }
  }
}
