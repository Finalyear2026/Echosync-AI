package com.echosync.echosync_ai

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val AI_CORE_CHANNEL = "com.echosync.ai/deepfilternet" // Keeping channel ID for compatibility
    private val FOREGROUND_SERVICE_CHANNEL = "com.echosync.ai/foreground_service"
    private var aiProcessorPlugin: AiProcessorPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        aiProcessorPlugin = AiProcessorPlugin(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AI_CORE_CHANNEL)
            .setMethodCallHandler(aiProcessorPlugin)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        EchoSyncForegroundService.start(this)
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        EchoSyncForegroundService.stop(this)
                        result.success(true)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "openBatteryOptimizationSettings" -> {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        aiProcessorPlugin?.dispose()
        super.onDestroy()
    }
}
