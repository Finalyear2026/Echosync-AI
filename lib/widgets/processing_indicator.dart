import 'package:flutter/material.dart';
import '../models/processing_state.dart';
import '../theme/app_theme.dart';

/// Shows step-by-step processing progress through the pipeline stages.
class ProcessingIndicator extends StatelessWidget {
  final ProcessingStage currentStage;

  const ProcessingIndicator({
    super.key,
    required this.currentStage,
  });

  @override
  Widget build(BuildContext context) {
    if (currentStage == ProcessingStage.idle ||
        currentStage == ProcessingStage.recording) {
      return const SizedBox.shrink();
    }

    final stages = [
      _StageInfo('Noise Filter', Icons.graphic_eq_rounded, ProcessingStage.noiseFiltering),
      _StageInfo('Transcribe', Icons.subtitles_rounded, ProcessingStage.transcribing),
      _StageInfo('AI Format', Icons.auto_fix_high_rounded, ProcessingStage.formatting),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stages.asMap().entries.map((entry) {
          final index = entry.key;
          final stage = entry.value;
          final isActive = currentStage == stage.processingStage;
          final isCompleted = _isStageCompleted(stage.processingStage);
          final isError = currentStage == ProcessingStage.error;

          return Expanded(
            child: Row(
              children: [
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isCompleted
                          ? AppTheme.success.withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                    ),
                  ),
                _StageIcon(
                  icon: stage.icon,
                  label: stage.label,
                  isActive: isActive,
                  isCompleted: isCompleted,
                  isError: isError && isActive,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isStageCompleted(ProcessingStage stage) {
    final order = [
      ProcessingStage.noiseFiltering,
      ProcessingStage.transcribing,
      ProcessingStage.formatting,
      ProcessingStage.completed,
    ];
    final currentIndex = order.indexOf(currentStage);
    final stageIndex = order.indexOf(stage);
    return currentIndex > stageIndex;
  }
}

class _StageInfo {
  final String label;
  final IconData icon;
  final ProcessingStage processingStage;

  _StageInfo(this.label, this.icon, this.processingStage);
}

class _StageIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isCompleted;
  final bool isError;

  const _StageIcon({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isCompleted,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    if (isError) {
      color = AppTheme.error;
    } else if (isCompleted) {
      color = AppTheme.success;
    } else if (isActive) {
      color = AppTheme.accentCyan;
    } else {
      color = AppTheme.textMuted;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: isActive && !isError
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(
                  isCompleted ? Icons.check_rounded : icon,
                  color: color,
                  size: 20,
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
