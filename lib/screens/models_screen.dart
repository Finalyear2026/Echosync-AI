import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/app_provider.dart';
import '../services/connectivity_service.dart';
import '../widgets/model_download_card.dart';
import '../theme/app_theme.dart';
import '../services/logging_service.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final ConnectivityService _connectivity = ConnectivityService();
  bool _isOnline = false;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((connected) {
      setState(() => _isOnline = connected);
      LoggingService().log(
        'Connectivity status changed on ModelsScreen',
        category: 'SCREEN_MODELS',
        details: {'is_online': connected},
      );
      context.read<AppProvider>().refreshCloudModels();
    });

    LoggingService().log(
      'Entered ModelsScreen',
      category: 'SCREEN_MODELS',
    );
  }

  Future<void> _checkInitialConnection() async {
    final connected = await _connectivity.checkConnection();
    if (mounted) {
      setState(() => _isOnline = connected);
      context.read<AppProvider>().refreshCloudModels();
    }
  }

  @override
  void dispose() {
    LoggingService().log(
      'Leaving ModelsScreen',
      category: 'SCREEN_MODELS',
    );
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Models'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: _ConnectivityBadge(isOnline: _isOnline),
            ),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          final categories = provider.cloudCategories;

          // 1. Loading State
          if (provider.isRegistryLoading && categories.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching model registry...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            );
          }

          // 2. Error State (with Retry)
          if (provider.registryError != null && categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text(
                      provider.registryError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => provider.refreshCloudModels(force: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // 3. Offline and Empty State
          if (categories.isEmpty && !_isOnline) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.cloud_off, size: 64, color: AppTheme.accentColor.withOpacity(0.5)),
                   const SizedBox(height: 16),
                   const Text('No models available offline', 
                    style: TextStyle(color: Colors.white70, fontSize: 18)),
                   const SizedBox(height: 8),
                   const Text('Connect to internet to browse more',
                    style: TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final models = category['models'] as List;

              final visibleModels = models;

              if (visibleModels.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      category['name'],
                      style: TextStyle(
                        color: AppTheme.accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...visibleModels.map((model) => ModelDownloadCard(
                    modelId: model['id'],
                    name: model['name'],
                    description: model['description'],
                    sizeBytes: model['size_bytes'],
                    driveId: model['drive_id'],
                    isZip: model['is_zip'] ?? false,
                    filename: model['filename'],
                    isOnline: _isOnline,
                  )),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ConnectivityBadge extends StatelessWidget {
  final bool isOnline;
  const _ConnectivityBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnline ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color: isOnline ? Colors.green : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
