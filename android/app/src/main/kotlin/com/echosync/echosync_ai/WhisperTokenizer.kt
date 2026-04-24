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
                val idStr = key.toIntOrNull()
                
                if (idStr != null) {
                    // Format: "id": "token"
                    tokenToText[idStr] = json.getString(key)
                } else {
                    // Format: "token": id
                    val id = json.optInt(key, -1)
                    if (id != -1) {
                        tokenToText[id] = key
                    }
                }
            }
            isLoaded = tokenToText.isNotEmpty()
            Log.i(TAG, "Vocabulary loaded: ${tokenToText.size} tokens from ${vocabFile.name}")
            isLoaded
        } catch (e: Exception) {
            Log.w(TAG, "Could not load vocab file: ${e.message}. Falling back to byte-level decoding.")
            isLoaded = false
            false
        }
    }

    /**
     * Decode a sequence of token IDs into a human-readable string.
     * Stops at EOT or zero-padding.
     */
    fun decode(tokenIds: IntArray): String {
        val result = StringBuilder()

        for (id in tokenIds) {
            // Stop at end-of-text or zero-padding
            if (id <= 0 || id == TOKEN_EOT) break

            // Skip all special tokens (50256+)
            if (id > TOKEN_EOT) continue

            val piece = if (isLoaded) {
                tokenToText[id] ?: continue
            } else {
                // Byte-level fallback: GPT-2 byte decoding
                byteDecodeFallback(id) ?: continue
            }
            result.append(piece)
        }

        // GPT-2 BPE uses 'G' (U+0120) as a space prefix for new words
        return result.toString()
            .replace('\u0120', ' ')   // word-boundary space
            .replace('\u010A', '\n')  // newline
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
