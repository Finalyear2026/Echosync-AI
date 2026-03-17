import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated record button with pulsing ring effect when recording.
class RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isProcessing;
  final VoidCallback onTap;
  final Duration recordingDuration;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isProcessing,
    required this.onTap,
    this.recordingDuration = Duration.zero,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _pulseController.repeat(reverse: true);
      _rippleController.repeat();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
      _rippleController.stop();
      _rippleController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Duration display
        AnimatedOpacity(
          opacity: widget.isRecording ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.recording.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.recording.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.recording,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(widget.recordingDuration),
                  style: const TextStyle(
                    color: AppTheme.recording,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Button with ripple rings
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripple rings (recording)
              if (widget.isRecording)
                AnimatedBuilder(
                  animation: _rippleAnimation,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(200, 200),
                      painter: _RipplePainter(
                        progress: _rippleAnimation.value,
                        color: AppTheme.recording,
                      ),
                    );
                  },
                ),

              // Main button
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final scale =
                      widget.isRecording ? _pulseAnimation.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: child,
                  );
                },
                child: GestureDetector(
                  onTap: widget.isProcessing ? null : widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: widget.isRecording
                          ? AppTheme.recordingGradient
                          : widget.isProcessing
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.textMuted,
                                    AppTheme.textMuted
                                  ],
                                )
                              : AppTheme.recordButtonGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (widget.isRecording
                                  ? AppTheme.recording
                                  : AppTheme.primaryPurple)
                              .withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: widget.isRecording
                          ? const Icon(
                              Icons.stop_rounded,
                              key: ValueKey('stop'),
                              color: Colors.white,
                              size: 44,
                            )
                          : widget.isProcessing
                              ? const SizedBox(
                                  key: ValueKey('processing'),
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.mic_rounded,
                                  key: ValueKey('mic'),
                                  color: Colors.white,
                                  size: 44,
                                ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Instruction text
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            widget.isRecording
                ? 'Tap to stop recording'
                : widget.isProcessing
                    ? 'Processing...'
                    : 'Tap to start recording',
            key: ValueKey(widget.isRecording
                ? 'recording'
                : widget.isProcessing
                    ? 'processing'
                    : 'idle'),
            style: TextStyle(
              color: widget.isRecording
                  ? AppTheme.recording
                  : AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < 3; i++) {
      final p = (progress + i * 0.33) % 1.0;
      final radius = 50 + (50 * p);
      final opacity = (1.0 - p) * 0.3;

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
