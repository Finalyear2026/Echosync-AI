package com.echosync.echosync_ai

object WhisperHardwareProbe {
    init {
        System.loadLibrary("whisper_hardware_probe")
    }

    external fun nativeIsWhisperCppCompatible(): Boolean

    fun isWhisperCppCompatible(): Boolean {
        return try {
            nativeIsWhisperCppCompatible()
        } catch (_: UnsatisfiedLinkError) {
            false
        }
    }
}