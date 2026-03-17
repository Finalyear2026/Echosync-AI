package com.echosync.echosync_ai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val DEEP_FILTER_CHANNEL = "com.echosync.ai/deepfilternet"
    private var deepFilterPlugin: DeepFilterNetPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deepFilterPlugin = DeepFilterNetPlugin(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEP_FILTER_CHANNEL)
            .setMethodCallHandler(deepFilterPlugin)
    }

    override fun onDestroy() {
        deepFilterPlugin?.dispose()
        super.onDestroy()
    }
}
