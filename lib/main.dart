import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

import 'package:echosync_ai/models/dictionary_entry.dart';
import 'package:echosync_ai/models/snippet.dart';
import 'package:echosync_ai/providers/app_provider.dart';
import 'package:echosync_ai/services/audio_recorder_service.dart';
import 'package:echosync_ai/services/noise_filter_service.dart';
import 'package:echosync_ai/services/transcription_service.dart';
import 'package:echosync_ai/services/llm_service.dart';
import 'package:echosync_ai/services/model_manager_service.dart';
import 'package:echosync_ai/services/settings_service.dart';
import 'package:echosync_ai/services/pipeline_service.dart';
import 'package:echosync_ai/screens/home_screen.dart';
import 'package:echosync_ai/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surfaceDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Settings service initialize (finds path)
  final settings = SettingsService();
  await settings.initialize();

  final whisperCppCompatible = await _checkWhisperCppCompatibility();

  // Request permissions
  await _requestPermissions();

  // Initialize services

  final audioRecorder = AudioRecorderService();
  final noiseFilter = NoiseFilterService();
  final transcription = TranscriptionService();
  final llm = LlmService();
  final modelManager = ModelManagerService();

  final pipeline = PipelineService(
    audioRecorder: audioRecorder,
    noiseFilter: noiseFilter,
    transcription: transcription,
    llm: llm,
    settings: settings,
    modelManager: modelManager,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(
        pipeline: pipeline,
        settings: settings,
        modelManager: modelManager,
        whisperCppCompatible: whisperCppCompatible,
      )..initialize(),
      child: const EchoSyncApp(),
    ),
  );
}

Future<bool> _checkWhisperCppCompatibility() async {
  const channel = MethodChannel('com.echosync.ai/deepfilternet');
  try {
    return await channel.invokeMethod<bool>('isWhisperCppCompatible') ?? false;
  } catch (e) {
    debugPrint('Whisper.cpp compatibility probe failed: $e');
    return false;
  }
}

Future<void> _requestPermissions() async {
  final micStatus = await Permission.microphone.status;
  if (!micStatus.isGranted) {
    await Permission.microphone.request();
  }
}

class EchoSyncApp extends StatelessWidget {
  const EchoSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoSync AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
