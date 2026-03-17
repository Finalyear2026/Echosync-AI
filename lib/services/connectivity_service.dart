import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service to monitor internet connectivity status
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  
  // Stream to allow UI components to listen to connectivity changes
  Stream<bool> get onConnectivityChanged => _connectivity.onConnectivityChanged
      .map((List<ConnectivityResult> results) => _isConnected(results));

  /// Check current connectivity status
  Future<bool> checkConnection() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  bool _isConnected(List<ConnectivityResult> results) {
    // If any result is something other than none, we are loosely "connected"
    return results.any((result) => result != ConnectivityResult.none);
  }
}
