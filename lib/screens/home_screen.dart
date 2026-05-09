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
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showTooltip = false;
  final ValueNotifier<int> _shakeTrigger = ValueNotifier(0);

  @override
  void dispose() {
    _shakeTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          ),

          // Decorative Background Glows
          Positioned(
            top: -100,
            right: -50,
            child: _BackgroundGlow(
              size: 300,
              color: AppTheme.primaryPurple.withOpacity(0.12),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -100,
            child: _BackgroundGlow(
              size: 400,
              color: AppTheme.accentCyan.withOpacity(0.08),
            ),
          ),

          SafeArea(
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
                            const SizedBox(height: 12),

                            // Status badge
                            _StatusBadge(provider: provider),

                            const SizedBox(height: 16),

                            // Processing mode toggle
                            _ProcessingModeToggle(provider: provider),

                            const SizedBox(height: 16),

                            // Active models mini-display
                            _ActiveModelsDisplay(
                              provider: provider,
                            ),

                            const SizedBox(height: 48),

                            // Record button
                            SizedBox(
                              height: 240, // Expanded height to include tooltip hit area
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                clipBehavior: Clip.none,
                                children: [
                                  // Custom Tooltip
                                  if (_showTooltip)
                                    Positioned(
                                      top: 0,
                                      child: _RequirementTooltip(
                                        onSetup: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => const ModelsScreen(),
                                            ),
                                          );
                                        },
                                        onClose: () {
                                          setState(() {
                                            _showTooltip = false;
                                          });
                                        },
                                      ),
                                    ),
                                  
                                  Positioned(
                                    bottom: -20, // Center the button a bit better
                                    child: RecordButton(
                                      isRecording: provider.isRecording,
                                      isProcessing: provider.isProcessing,
                                      isEnabled: provider.areAllModelsSelected,
                                      shakeTrigger: _shakeTrigger,
                                      recordingDuration: provider.recordingDuration,
                                      onTap: () => _handleRecordTap(context, provider),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),

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

                            // Real-time partial transcript display — visible
                            // during both recording and the subsequent
                            // transcribing stage (inference from the last
                            // timer tick may finish after stop() is called).
                            if (provider.processingMode ==
                                    ProcessingMode.realtime &&
                                provider.partialText.isNotEmpty &&
                                provider.stage !=
                                    ProcessingStage.completed) ...[
                              const SizedBox(height: 16),
                              _RealtimePartialDisplay(
                                text: provider.partialText,
                              ),
                            ],

                            // Result display
                            if (provider.lastResult != null &&
                                provider.stage == ProcessingStage.completed) ...[
                              const SizedBox(height: 24),
                              TranscriptionDisplay(
                                result: provider.lastResult!,
                              ),
                              const SizedBox(height: 24),
                              _NewRecordingButton(
                                onTap: () => provider.reset(),
                              ),
                            ],

                            const SizedBox(height: 60),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Logo with Glow
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryPurple.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.primaryGradient.createShader(bounds),
                child: const Text(
                  'EchoSync AI',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              Text(
                'OFFLINE INTELLIGENCE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted.withOpacity(0.6),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Action Buttons
          _AppBarAction(
            icon: Icons.cloud_queue_rounded,
            color: AppTheme.accentCyan,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ModelsScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          _AppBarAction(
            icon: Icons.tune_rounded,
            color: AppTheme.textSecondary,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
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

    // NEW: Check if all categories have an active model
    if (!provider.areAllModelsSelected) {
      setState(() {
        _showTooltip = true;
      });
      _shakeTrigger.value++;
      return;
    }

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

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _AppBarAction({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _BackgroundGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size * 0.5,
            spreadRadius: size * 0.2,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AppProvider provider;

  const _StatusBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    IconData icon;

    switch (provider.stage) {
      case ProcessingStage.idle:
        final settings = provider.appSettings;
        text =
            '${settings.transcriptionStyle == TranscriptionStyle.smart ? "Smart" : "Raw"} • ${settings.transcriptionTone == TranscriptionTone.formal ? "Formal" : "Casual"}';
        color = AppTheme.textMuted;
        icon = Icons.insights_rounded;
        break;
      case ProcessingStage.recording:
        text = 'Recording...';
        color = AppTheme.recording;
        icon = Icons.radio_button_checked_rounded;
        break;
      case ProcessingStage.noiseFiltering:
        text = 'Filtering noise...';
        color = AppTheme.accentCyan;
        icon = Icons.waves_rounded;
        break;
      case ProcessingStage.transcribing:
        text = 'Transcribing speech...';
        color = AppTheme.accentCyan;
        icon = Icons.translate_rounded;
        break;
      case ProcessingStage.formatting:
        text = 'AI formatting...';
        color = AppTheme.primaryPurple;
        icon = Icons.auto_awesome_rounded;
        break;
      case ProcessingStage.completed:
        text = 'Ready for use';
        color = AppTheme.success;
        icon = Icons.check_circle_rounded;
        break;
      case ProcessingStage.error:
        text = 'Engine Error';
        color = AppTheme.error;
        icon = Icons.warning_amber_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.stage == ProcessingStage.recording)
             _PulseIcon(icon: icon, color: color)
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulseIcon({required this.icon, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
      child: Icon(widget.icon, size: 14, color: widget.color),
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
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.error.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.error, 
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppTheme.error,
            padding: EdgeInsets.zero,
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
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accentCyan.withOpacity(0.1),
                  AppTheme.accentCyan.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accentCyan.withOpacity(0.2),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay_rounded, size: 18, color: AppTheme.accentCyan),
                SizedBox(width: 10),
                Text(
                  'Start New Session',
                  style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveModelsDisplay extends StatelessWidget {
  final AppProvider provider;

  const _ActiveModelsDisplay({
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final activeModels = provider.getActiveModelNames();
    final categories = provider.cloudCategories;
    if (activeModels.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Text(
          'PIPELINE STATUS',
          style: TextStyle(
            color: AppTheme.textMuted.withOpacity(0.4),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: categories.map((category) {
              final categoryId = category['id'] as String;
              final categoryName = category['name'] as String;
              final activeId = provider.activeModels[categoryId];
              final isNone = activeId == null || activeId.isEmpty;
              
              String modelName = isNone ? 'Empty Slot' : 'Unknown';
              if (!isNone) {
                final models = category['models'] as List;
                final model = models.firstWhere((m) => m['id'] == activeId, orElse: () => null);
                modelName = model != null ? model['name'] as String : 'Unknown';
              }
              
              IconData icon;
              if (categoryName.contains('Noise')) {
                icon = Icons.waves_rounded;
              } else if (categoryName.contains('STT') || categoryName.contains('Speech')) {
                icon = Icons.mic_rounded;
              } else {
                icon = Icons.auto_awesome_rounded;
              }

              Widget chip = Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isNone ? Colors.white.withOpacity(0.02) : AppTheme.accentCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: isNone 
                    ? Border.all(color: Colors.white.withOpacity(0.05), width: 1, style: BorderStyle.solid) 
                    : Border.all(color: AppTheme.accentCyan.withOpacity(0.2), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isNone ? Colors.white.withOpacity(0.05) : AppTheme.accentCyan.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isNone ? Icons.add_rounded : icon,
                        size: 14,
                        color: isNone ? AppTheme.textMuted : AppTheme.accentCyan,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryName.split('(').first.trim().toUpperCase(),
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          modelName,
                          style: TextStyle(
                            color: isNone ? AppTheme.textMuted.withOpacity(0.6) : AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: isNone ? FontWeight.w400 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              if (isNone) {
                return _BreathingHighlight(child: chip);
              }

              return chip;
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _BreathingHighlight extends StatefulWidget {
  final Widget child;

  const _BreathingHighlight({required this.child});

  @override
  State<_BreathingHighlight> createState() => _BreathingHighlightState();
}

class _BreathingHighlightState extends State<_BreathingHighlight>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.warning.withOpacity(0.15 * _animation.value),
                blurRadius: 15 * _animation.value,
                spreadRadius: 2 * _animation.value,
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Color.lerp(
                  Colors.white.withOpacity(0.1),
                  AppTheme.warning.withOpacity(0.6),
                  _animation.value,
                )!,
                width: 1.5,
              ),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Processing Mode Toggle
// ─────────────────────────────────────────────────────────────────────────────

class _ProcessingModeToggle extends StatelessWidget {
  final AppProvider provider;

  const _ProcessingModeToggle({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isBatch = provider.processingMode == ProcessingMode.batch;
    final enabled = provider.isToggleEnabled;

    return Tooltip(
      message: enabled ? '' : 'Stop recording to change mode',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              _ModeOption(
                label: 'Real-time',
                icon: Icons.stream_rounded,
                selected: !isBatch,
                enabled: enabled,
                onTap: enabled
                    ? () => provider.setProcessingMode(ProcessingMode.realtime)
                    : null,
              ),
              _ModeOption(
                label: 'Batch',
                icon: Icons.queue_music_rounded,
                selected: isBatch,
                enabled: enabled,
                onTap: enabled
                    ? () => provider.setProcessingMode(ProcessingMode.batch)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        selected ? AppTheme.accentCyan : AppTheme.textMuted.withOpacity(0.5);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accentCyan.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(color: AppTheme.accentCyan.withOpacity(0.3))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: enabled ? activeColor : activeColor.withOpacity(0.4)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? activeColor : activeColor.withOpacity(0.4),
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Real-time Partial Transcript Display
// ─────────────────────────────────────────────────────────────────────────────

class _RealtimePartialDisplay extends StatelessWidget {
  final String text;

  const _RealtimePartialDisplay({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.accentCyan.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentCyan.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _PulseIcon(
                    icon: Icons.graphic_eq_rounded,
                    color: AppTheme.accentCyan),
                const SizedBox(width: 8),
                Text(
                  'Live Transcript',
                  style: TextStyle(
                    color: AppTheme.accentCyan.withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequirementTooltip extends StatelessWidget {
  final VoidCallback onSetup;
  final VoidCallback onClose;

  const _RequirementTooltip({
    required this.onSetup,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      curve: Curves.elasticOut,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          alignment: Alignment.bottomCenter,
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.warning.withOpacity(0.95),
              AppTheme.warning.withOpacity(0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.warning.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            const Icon(Icons.info_outline_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'Pipeline Incomplete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onSetup,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SETUP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
