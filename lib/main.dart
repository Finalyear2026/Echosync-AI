import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/dictionary_entry.dart';
import 'models/snippet.dart';
import 'providers/app_provider.dart';
import 'services/audio_recorder_service.dart';
import 'services/noise_filter_service.dart';
import 'services/transcription_service.dart';
import 'services/llm_service.dart';
import 'services/model_manager_service.dart';
import 'services/settings_service.dart';
import 'services/pipeline_service.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surfaceDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(DictionaryEntryAdapter());
  Hive.registerAdapter(SnippetAdapter());

  // Request permissions
  await _requestPermissions();

  // Initialize services
  final settings = SettingsService();
  await settings.initialize();
  
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
      )..initialize(),
      child: const EchoSyncApp(),
    ),
  );
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
