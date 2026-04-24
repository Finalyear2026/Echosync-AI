package com.echosync.echosync_ai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val AI_CORE_CHANNEL = "com.echosync.ai/deepfilternet" // Keeping channel ID for compatibility
    private var aiProcessorPlugin: AiProcessorPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        aiProcessorPlugin = AiProcessorPlugin(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AI_CORE_CHANNEL)
            .setMethodCallHandler(aiProcessorPlugin)
    }

    override fun onDestroy() {
        aiProcessorPlugin?.dispose()
        super.onDestroy()
    }
}
