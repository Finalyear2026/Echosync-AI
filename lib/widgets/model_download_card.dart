import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../services/model_manager_service.dart';

class ModelDownloadCard extends StatelessWidget {
  final String modelId;
  final String name;
  final String description;
  final int sizeBytes;
  final String driveId;
  final bool isZip;
  final String filename;
  final bool isOnline;
  final String categoryId;

  const ModelDownloadCard({
    super.key,
    required this.modelId,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.driveId,
    required this.isZip,
    required this.filename,
    required this.isOnline,
    required this.categoryId,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final isDownloaded = provider.isModelDownloaded(modelId);
        final downloadInfo = provider.downloadProgress[modelId];
        final isDownloading = provider.isModelDownloading(modelId);
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
        final isPaused = provider.isPaused(modelId);
        final isActive = provider.isModelActive(categoryId, modelId);

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
                  _buildIcon(isDownloaded),
                  const SizedBox(width: 12),
                  _buildDetails(sizeMB),
                  _buildActions(context, provider, isDownloaded, isDownloading, isPaused),
                ],
              ),
              if (isDownloading || isPaused) _buildProgress(downloadInfo, isPaused: isPaused),

            ],
          ),
        );

      },
    );
  }

  Widget _buildIcon(bool isDownloaded) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isDownloaded ? AppTheme.success : AppTheme.primaryPurple).withOpacity(0.15),
      ),
      child: Icon(
        isDownloaded ? Icons.check_circle_rounded : Icons.cloud_download_rounded,
        color: isDownloaded ? AppTheme.success : AppTheme.primaryPurple,
        size: 18,
      ),
    );
  }

  Widget _buildDetails(String sizeMB) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('$description • $sizeMB MB', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, AppProvider provider, bool isDownloaded, bool isDownloading, bool isPaused) {
    if (isDownloaded) {
      final isActive = provider.isModelActive(categoryId, modelId);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: isActive 
              ? () => provider.deactivateModel(categoryId)
              : () => provider.activateModel(categoryId, modelId),
            child: Text(
              isActive ? 'Activated' : 'Activate',
              style: TextStyle(color: isActive ? AppTheme.success : AppTheme.accentCyan),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => provider.deleteModel(modelId, filename: filename, isZip: isZip),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
          ),
        ],
      );
    }

    if (isDownloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => provider.pauseDownload(modelId),
            icon: const Icon(Icons.pause_circle_outline, color: AppTheme.accentCyan),
          ),
          IconButton(
            onPressed: () => provider.cancelDownload(modelId, filename: filename),
            icon: const Icon(Icons.cancel_outlined, color: AppTheme.textMuted),
          ),
        ],
      );
    }

    if (isPaused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: isOnline 
              ? () => provider.downloadModel(
                modelId,
                driveId: driveId,
                isZip: isZip,
                expectedSize: sizeBytes,
                filename: filename,
              )
              : () => _showOfflineMessage(context),
            icon: Icon(
              Icons.play_circle_outline, 
              color: isOnline ? AppTheme.accentCyan : AppTheme.textMuted
            ),
          ),
          IconButton(
            onPressed: () => provider.cancelDownload(modelId, filename: filename),
            icon: const Icon(Icons.cancel_outlined, color: AppTheme.textMuted),
          ),
        ],
      );
    }


    return ElevatedButton(
      onPressed: isOnline 
        ? () => provider.downloadModel(
          modelId, 
          driveId: driveId, 
          isZip: isZip,
          expectedSize: sizeBytes,
          filename: filename,
        )
        : () => _showOfflineMessage(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: isOnline ? AppTheme.primaryPurple : AppTheme.textMuted.withOpacity(0.3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: Text(
        'Download', 
        style: TextStyle(
          fontSize: 12,
          color: isOnline ? Colors.white : Colors.white24,
        )
      ),
    );
  }

  void _showOfflineMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('you are offline'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildProgress(DownloadProgressInfo? info, {bool isPaused = false}) {

    if (info == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 12.0),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    
    return Column(
      children: [
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: info.progress,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: const AlwaysStoppedAnimation(AppTheme.accentCyan),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Text(
              '${info.downloadedMB}MB / ${info.totalMB}MB',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
             Text(
              isPaused ? '0 KB/s' : info.speedText,
              style: const TextStyle(color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.bold),
            ),

            Text(
              info.percentageText,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

