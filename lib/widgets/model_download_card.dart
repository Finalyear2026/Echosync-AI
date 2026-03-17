import 'package:flutter/material.dart';
import '../services/model_manager_service.dart';
import '../theme/app_theme.dart';

/// Card showing model download status and progress.
class ModelDownloadCard extends StatelessWidget {
  final String modelKey;
  final ModelInfo modelInfo;
  final bool isDownloaded;
  final double downloadProgress;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  const ModelDownloadCard({
    super.key,
    required this.modelKey,
    required this.modelInfo,
    required this.isDownloaded,
    required this.downloadProgress,
    required this.isDownloading,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDownloaded
              ? AppTheme.success.withOpacity(0.3)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isDownloaded ? AppTheme.success : AppTheme.primaryPurple)
                      .withOpacity(0.15),
                ),
                child: Icon(
                  isDownloaded
                      ? Icons.check_circle_rounded
                      : modelKey.contains('whisper')
                          ? Icons.hearing_rounded
                          : Icons.psychology_rounded,
                  color: isDownloaded ? AppTheme.success : AppTheme.primaryPurple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelInfo.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${modelInfo.description} • ${modelInfo.sizeMB}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDownloaded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Ready',
                    style: TextStyle(
                      color: AppTheme.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (isDownloading)
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppTheme.textMuted,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                )
              else
                ElevatedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Download', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: downloadProgress,
                backgroundColor: Colors.white.withOpacity(0.06),
                valueColor: const AlwaysStoppedAnimation(AppTheme.accentCyan),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(downloadProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
