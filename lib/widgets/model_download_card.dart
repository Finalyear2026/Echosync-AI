import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

class ModelDownloadCard extends StatelessWidget {
  final String modelId;
  final String name;
  final String description;
  final int sizeBytes;
  final String driveId;
  final bool isZip;
  final String filename;

  const ModelDownloadCard({
    super.key,
    required this.modelId,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.driveId,
    required this.isZip,
    required this.filename,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final isDownloaded = provider.isModelDownloaded(modelId);
        final downloadProgress = provider.downloadProgress[modelId] ?? 0.0;
        final isDownloading = provider.currentlyDownloading == modelId;
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

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
                  _buildActions(context, provider, isDownloaded, isDownloading, downloadProgress),
                ],
              ),
              if (isDownloading) _buildProgress(downloadProgress),
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

  Widget _buildActions(BuildContext context, AppProvider provider, bool isDownloaded, bool isDownloading, double progress) {
    if (isDownloaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => provider.useModel('category', modelId), // Logic for actual category mapping
            child: const Text('Use', style: TextStyle(color: AppTheme.accentCyan)),
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
            onPressed: () => provider.cancelDownload(modelId),
            icon: const Icon(Icons.pause_circle_outline, color: AppTheme.accentCyan),
          ),
          IconButton(
            onPressed: () => provider.cancelDownload(modelId),
            icon: const Icon(Icons.cancel_outlined, color: AppTheme.textMuted),
          ),
        ],
      );
    }

    return ElevatedButton(
      onPressed: () => provider.downloadModel(
        modelId, 
        driveId: driveId, 
        isZip: isZip,
        expectedSize: sizeBytes,
        filename: filename,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryPurple,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: const Text('Download', style: TextStyle(fontSize: 12)),
    );
  }

  Widget _buildProgress(double progress) {
    return Column(
      children: [
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: const AlwaysStoppedAnimation(AppTheme.accentCyan),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${(progress * 100).toStringAsFixed(1)}%', 
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ),
      ],
    );
  }
}

