package com.echosync.echosync_ai

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * DeepFilterNet platform channel plugin for noise suppression.
 *
 * This processes WAV audio files (48kHz, 16-bit, mono) through DeepFilterNet
 * to remove background noise.
 *
 * Note: The actual DeepFilterNet native library integration depends on the
 * io.github.kaleyravideo:android-deepfilternet library being available.
 * If the library is not found at build time, this falls through to a
 * passthrough mode that copies the audio without filtering.
 */
class DeepFilterNetPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private var isInitialized = false
    private var deepFilterNet: Any? = null
    private val LIB_CLASS = "com.rikorose.deepfilternet.NativeDeepFilterNet"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                try {
                    initialize()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INIT_ERROR", "Failed to initialize DeepFilterNet: ${e.message}", null)
                }
            }
            "processAudioFile" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                if (inputPath == null || outputPath == null) {
                    result.error("INVALID_ARGS", "inputPath and outputPath are required", null)
                    return
                }
                try {
                    val processed = processAudioFile(inputPath, outputPath)
                    result.success(processed)
                } catch (e: Exception) {
                    result.error("PROCESS_ERROR", "Failed to process audio: ${e.message}", null)
                }
            }
            "dispose" -> {
                dispose()
                result.success(true)
            }
            "isAvailable" -> {
                result.success(isDeepFilterAvailable())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun isDeepFilterAvailable(): Boolean {
        return try {
            Class.forName(LIB_CLASS)
            true
        } catch (e: ClassNotFoundException) {
            false
        }
    }

    private fun initialize() {
        try {
            // Try to initialize the actual DeepFilterNet library
            val clazz = Class.forName(LIB_CLASS)
            val constructor = clazz.getConstructor(Context::class.java)
            deepFilterNet = constructor.newInstance(context)
            isInitialized = true
        } catch (e: ClassNotFoundException) {
            // DeepFilterNet library not available - use passthrough mode
            isInitialized = true
            deepFilterNet = null
        } catch (e: Exception) {
            // Other initialization error - still allow app to work
            isInitialized = true
            deepFilterNet = null
        }
    }

    /**
     * Process a WAV audio file through noise filtering.
     * If DeepFilterNet is not available, performs a simple passthrough copy.
     */
    private fun processAudioFile(inputPath: String, outputPath: String): Boolean {
        if (!isInitialized) {
            initialize()
        }

        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            throw IllegalArgumentException("Input file does not exist: $inputPath")
        }

        if (deepFilterNet != null) {
            // Process with actual DeepFilterNet
            return processWithDeepFilter(inputPath, outputPath)
        } else {
            // Passthrough: copy the file as-is (no noise filtering)
            inputFile.copyTo(File(outputPath), overwrite = true)
            return true
        }
    }

    private fun processWithDeepFilter(inputPath: String, outputPath: String): Boolean {
        try {
            val clazz = deepFilterNet!!.javaClass
            val processMethod = clazz.getMethod("processFile", String::class.java, String::class.java)
            processMethod.invoke(deepFilterNet, inputPath, outputPath)
            return true
        } catch (e: Exception) {
            // Fallback: copy the file without filtering
            File(inputPath).copyTo(File(outputPath), overwrite = true)
            return true
        }
    }

    fun dispose() {
        if (deepFilterNet != null) {
            try {
                val clazz = deepFilterNet!!.javaClass
                val disposeMethod = clazz.getMethod("release")
                disposeMethod.invoke(deepFilterNet)
            } catch (e: Exception) {
                // Ignore disposal errors
            }
        }
        deepFilterNet = null
        isInitialized = false
    }
}
