#include <jni.h>
#include <sys/auxv.h>

#if defined(__aarch64__)
#include <asm/hwcap.h>
#ifndef HWCAP_ASIMDDP
#define HWCAP_ASIMDDP (1UL << 20)
#endif
#endif

extern "C" JNIEXPORT jboolean JNICALL
Java_com_echosync_echosync_1ai_WhisperHardwareProbe_nativeIsWhisperCppCompatible(
        JNIEnv* /*env*/,
        jobject /*thiz*/) {
#if defined(__aarch64__)
    const unsigned long hwcap = getauxval(AT_HWCAP);
    const bool hasDotProd = (hwcap & HWCAP_ASIMDDP) != 0;
    return hasDotProd ? JNI_TRUE : JNI_FALSE;
#else
    return JNI_FALSE;
#endif
}