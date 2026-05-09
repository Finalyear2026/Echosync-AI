import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Service for recording audio from the device microphone.
/// Outputs WAV files at 48kHz, 16-bit, mono for DeepFilterNet compatibility.
class AudioRecorderService {
  AudioRecorder? _recorder;
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;

  Future<void> initialize() async {
    _recorder = AudioRecorder();
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    if (_recorder == null) await initialize();
    return await _recorder!.hasPermission();
  }

  /// Start recording audio
  Future<String> startRecording() async {
    if (_recorder == null) await initialize();
    if (_isRecording) {
      throw StateError('Already recording');
    }

    // Use External Storage for visibility in Windows File Explorer
    final extDir = await getExternalStorageDirectory();
    final internalDir = await getApplicationDocumentsDirectory();
    final dir = extDir ?? internalDir;
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentRecordingPath = '${dir.path}/recording_$timestamp.wav';

    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      bitRate: 256000, // 16000 * 16 * 1
      numChannels: 1,
    );

    await _recorder!.start(config, path: _currentRecordingPath!);
    _isRecording = true;
    _recordingStartTime = DateTime.now();

    debugPrint('AudioRecorder: Started recording to $_currentRecordingPath');
    return _currentRecordingPath!;
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    if (!_isRecording || _recorder == null) {
      return null;
    }

    final path = await _recorder!.stop();
    _isRecording = false;

    if (path != null && await File(path).exists()) {
      final file = File(path);
      final size = await file.length();
      debugPrint('AudioRecorder: Stopped recording. File: $path, Size: $size bytes');
      return path;
    }

    debugPrint('AudioRecorder: Recording stopped but no file produced');
    return null;
  }

  /// Get the duration of the current recording
  Duration? getRecordingDuration() {
    if (!_isRecording || _recordingStartTime == null) return null;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Cancel the current recording
  Future<void> cancelRecording() async {
    if (_isRecording && _recorder != null) {
      await _recorder!.stop();
      _isRecording = false;

      // Delete the partial recording file
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _currentRecordingPath = null;
    }
  }

  Future<void> dispose() async {
    await cancelRecording();
    _recorder?.dispose();
    _recorder = null;
  }
}
