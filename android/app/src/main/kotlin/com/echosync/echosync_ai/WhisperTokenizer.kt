package com.echosync.echosync_ai

import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Whisper BPE Tokenizer.
 * Decodes token IDs back to text using the vocab.json vocabulary file.
 * Falls back to byte-level GPT-2 decoding if vocab file is not found.
 *
 * HOW TO GET vocab.json:
 *   Run this Python snippet once on your PC to generate the vocab file:
 *   ```python
 *   import json, whisper
 *   tokenizer = whisper.tokenizer.get_tokenizer(multilingual=True)
 *   vocab = {v: k for k, v in tokenizer.encoder.items()}
 *   with open("vocab.json", "w", encoding="utf-8") as f:
 *       json.dump(vocab, f, ensure_ascii=False)
 *   ```
 *   Then place vocab.json in the same folder as your .tflite model.
 */
class WhisperTokenizer {

    private val tokenToText = mutableMapOf<Int, String>()
    private var isLoaded = false

    companion object {
        private const val TAG = "WhisperTokenizer"

        // Special token IDs (multilingual model)
        private const val TOKEN_EOT = 50256

        /**
         * GPT-2 byte-to-unicode table.
         * Maps 0-255 byte values to unicode characters used by the BPE tokenizer.
         */
        private val BYTES_TO_UNICODE: Map<Int, Char> by lazy {
            val bs = mutableListOf<Int>()
            ('!'.code..'~'.code).forEach { bs.add(it) }
            ('\u00A1'.code..'\u00AC'.code).forEach { bs.add(it) }
            ('\u00AE'.code..'\u00FF'.code).forEach { bs.add(it) }
            val cs = bs.toMutableList()
            var n = 0
            for (b in 0 until 256) {
                if (b !in bs) { bs.add(b); cs.add(256 + n); n++ }
            }
            bs.zip(cs).associate { (b, c) -> b to c.toChar() }
        }

        private val UNICODE_TO_BYTES: Map<Char, Int> by lazy {
            BYTES_TO_UNICODE.entries.associate { (b, c) -> c to b }
        }
    }

    /** 
     * Load vocabulary from a JSON file.
     * Supports both formats:
     *   - ID to Token: {"0": "!", "1": "\"" }
     *   - Token to ID (Standard HF): {"!": 0, "\"": 1}
     */
    fun load(vocabFile: File): Boolean {
        return try {
            val json = JSONObject(vocabFile.readText(Charsets.UTF_8))
            tokenToText.clear()
            val keys = json.keys()
            
            while (keys.hasNext()) {
                val key = keys.next()
                // IMPORTANT: The standard HF vocab is {"token": id}
                // Even if the token is a number string like "123", it's the KEY.
                val id = json.optInt(key, -1)
                if (id != -1) {
                    tokenToText[id] = key
                } else {
                    // Fallback for {"id": "token"} format
                    val idFromKey = key.toIntOrNull()
                    if (idFromKey != null) {
                        tokenToText[idFromKey] = json.getString(key)
                    }
                }
            }
            isLoaded = tokenToText.isNotEmpty()
            Log.i(TAG, "Vocabulary loaded: ${tokenToText.size} tokens")
            isLoaded
        } catch (e: Exception) {
            Log.w(TAG, "Load error: ${e.message}")
            false
        }
    }

    fun decode(tokenIds: IntArray): String {
        val byteStream = mutableListOf<Byte>()

        for (id in tokenIds) {
            // Stop at EOT (50257) or padding
            if (id == TOKEN_EOT || id < 0) break
            
            // Skip control tokens (typically 50258+)
            if (id > TOKEN_EOT) continue

            val piece = tokenToText[id] ?: continue
            
            // Convert piece (potentially GPT-2 encoded) back to raw bytes
            for (char in piece) {
                UNICODE_TO_BYTES[char]?.let { byteStream.add(it.toByte()) }
            }
        }

        // Convert the full byte stream to UTF-8 once to handle multi-byte chars (Emoji/Arabic/etc)
        val decoded = String(byteStream.toByteArray(), Charsets.UTF_8)
        
        // Clean up GPT-2 artifact spaces and newlines
        return decoded
            .replace('\u0120', ' ')
            .replace('\u010A', '\n')
            .trim()
    }

    /**
     * Fallback token decoding using GPT-2 byte table.
     * Only works well for simple ASCII text without multi-char BPE merges.
     */
    private fun byteDecodeFallback(tokenId: Int): String? {
        if (tokenId < 0 || tokenId >= 256) return null
        val uChar = BYTES_TO_UNICODE[tokenId] ?: return null
        val byteVal = UNICODE_TO_BYTES[uChar] ?: return null
        return if (byteVal in 32..126) byteVal.toChar().toString() else null
    }
}
