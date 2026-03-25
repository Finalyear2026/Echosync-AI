import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/processing_state.dart';
import '../theme/app_theme.dart';
import '../widgets/record_button.dart';
import '../widgets/processing_indicator.dart';
import '../widgets/transcription_display.dart';
import 'settings_screen.dart';
import 'models_screen.dart';


/// Main home screen — single-page design with record button and result display.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Column(
            children: [
              // App bar area
              _buildAppBar(context),

              // Main content
              Expanded(
                child: Consumer<AppProvider>(
                  builder: (context, provider, child) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),

                          // Status badge
                          _StatusBadge(provider: provider),

                          const SizedBox(height: 12),

                          // Active models mini-display
                          _ActiveModelsDisplay(provider: provider),

                          const SizedBox(height: 40),

                          // Record button
                          RecordButton(
                            isRecording: provider.isRecording,
                            isProcessing: provider.isProcessing,
                            recordingDuration: provider.recordingDuration,
                            onTap: () => _handleRecordTap(context, provider),
                          ),

                          const SizedBox(height: 24),

                          // Processing progress
                          ProcessingIndicator(
                            currentStage: provider.stage,
                          ),

                          // Error display
                          if (provider.stage == ProcessingStage.error &&
                              provider.errorMessage != null)
                            _ErrorDisplay(
                                message: provider.errorMessage!,
                                onDismiss: () => provider.reset()),

                          // Result display
                          if (provider.lastResult != null &&
                              provider.stage == ProcessingStage.completed) ...[
                            const SizedBox(height: 16),
                            TranscriptionDisplay(
                              result: provider.lastResult!,
                            ),
                            const SizedBox(height: 16),
                            _NewRecordingButton(
                              onTap: () => provider.reset(),
                            ),
                          ],

                          const SizedBox(height: 40),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Logo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.primaryGradient.createShader(bounds),
            child: const Text(
              'EchoSync AI',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const Spacer(),
          // Models button (NEW in v0.2.0)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.cloud_queue_rounded, size: 20),
              color: AppTheme.accentCyan,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ModelsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Settings button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.tune_rounded, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleRecordTap(BuildContext context, AppProvider provider) async {
    // Check if models are ready
    final appSettings = provider.appSettings;
    final modelId = appSettings.whisperModel;
    final isUnsupported = modelId.toLowerCase().contains('v3') || modelId.toLowerCase().contains('turbo');

    if (!provider.isRecording) {
      if (isUnsupported) {
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Whisper V3/Turbo is not supported by the current engine. Please select Base, Small or Medium in Settings.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      final modelsReady = await provider.areModelsReady();
      if (!modelsReady) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please download required AI models first.'),
              action: SnackBarAction(
                label: 'Models',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ModelsScreen(),
                    ),
                  );
                },
              ),
            ),
          );
        }
        return;
      }
    }

    provider.toggleRecording();
  }
}


class _StatusBadge extends StatelessWidget {
  final AppProvider provider;

  const _StatusBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;

    switch (provider.stage) {
      case ProcessingStage.idle:
        final settings = provider.appSettings;
        text =
            '${settings.transcriptionStyle == TranscriptionStyle.smart ? "Smart" : "Raw"} • ${settings.transcriptionTone == TranscriptionTone.formal ? "Formal" : "Casual"}';
        color = AppTheme.textMuted;
        break;
      case ProcessingStage.recording:
        text = 'Recording...';
        color = AppTheme.recording;
        break;
      case ProcessingStage.noiseFiltering:
        text = 'Filtering noise...';
        color = AppTheme.accentCyan;
        break;
      case ProcessingStage.transcribing:
        text = 'Transcribing speech...';
        color = AppTheme.accentCyan;
        break;
      case ProcessingStage.formatting:
        text = 'AI formatting...';
        color = AppTheme.primaryPurple;
        break;
      case ProcessingStage.completed:
        text = 'Done!';
        color = AppTheme.success;
        break;
      case ProcessingStage.error:
        text = 'Error occurred';
        color = AppTheme.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorDisplay({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppTheme.error,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _NewRecordingButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewRecordingButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: const Text('New Recording'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.accentCyan,
          side: BorderSide(color: AppTheme.accentCyan.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
class _ActiveModelsDisplay extends StatelessWidget {
  final AppProvider provider;

  const _ActiveModelsDisplay({required this.provider});

  @override
  Widget build(BuildContext context) {
    final activeModels = provider.getActiveModelNames();
    if (activeModels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: activeModels.entries.map((entry) {
          final isNone = entry.value == 'None';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${entry.key}: ',
                  style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  entry.value,
                  style: TextStyle(
                    color: isNone ? Colors.orangeAccent.withOpacity(0.8) : AppTheme.accentCyan.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: isNone ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
