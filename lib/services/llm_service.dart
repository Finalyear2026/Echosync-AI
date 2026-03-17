import 'package:flutter/foundation.dart';
import 'package:flutter_llama/flutter_llama.dart';
import '../models/processing_state.dart';

/// Service for LLM-based text formatting using Qwen2.5 via llama.cpp.
/// Handles filler word removal, grammar fixes, tone adjustment, and
/// context-aware editing.
class LlmService {
  FlutterLlama? _llama;
  bool _isModelLoaded = false;

  bool get isModelLoaded => _isModelLoaded;

  /// Initialize and load the LLM model
  Future<bool> loadModel(String modelPath) async {
    try {
      _llama = FlutterLlama.instance;

      final config = LlamaConfig(
        modelPath: modelPath,
        nThreads: 4,
        nGpuLayers: 0, // CPU only for max compatibility
        contextSize: 2048,
        batchSize: 512,
        useGpu: false,
        verbose: false,
      );

      final success = await _llama!.loadModel(config);
      _isModelLoaded = success;
      debugPrint('LLM: Model loaded=$success from $modelPath');
      return success;
    } catch (e) {
      debugPrint('LLM: Model load error: $e');
      _isModelLoaded = false;
      return false;
    }
  }

  /// Format transcribed text using the LLM.
  /// Applies filler word removal, grammar fixes, tone adjustment, etc.
  Future<String> formatText({
    required String rawText,
    required TranscriptionStyle style,
    required TranscriptionTone tone,
    List<Map<String, String>>? dictionary,
    List<Map<String, String>>? snippets,
  }) async {
    if (!_isModelLoaded || _llama == null) {
      debugPrint('LLM: Model not loaded, returning raw text');
      return rawText;
    }

    if (style == TranscriptionStyle.raw) {
      return rawText;
    }

    try {
      final prompt = _buildPrompt(
        rawText: rawText,
        tone: tone,
        dictionary: dictionary,
        snippets: snippets,
      );

      final params = GenerationParams(
        prompt: prompt,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        maxTokens: 2048,
        repeatPenalty: 1.1,
      );

      final response = await _llama!.generate(params);
      final formatted = _extractFormattedText(response.text);
      debugPrint('LLM: Formatted text. Tokens=${response.tokensGenerated}, '
          'Speed=${response.tokensPerSecond.toStringAsFixed(1)} tok/s');
      return formatted;
    } catch (e) {
      debugPrint('LLM: Formatting error: $e');
      return rawText; // Return raw text on error
    }
  }

  /// Build the prompt for text formatting
  String _buildPrompt({
    required String rawText,
    required TranscriptionTone tone,
    List<Map<String, String>>? dictionary,
    List<Map<String, String>>? snippets,
  }) {
    final toneInstruction = tone == TranscriptionTone.formal
        ? 'Use a formal, professional tone.'
        : 'Use a casual, conversational tone.';

    var dictInstruction = '';
    if (dictionary != null && dictionary.isNotEmpty) {
      final corrections = dictionary
          .map((d) => '"${d['misheard']}" → "${d['correct']}"')
          .join(', ');
      dictInstruction = '\n- Apply these word corrections: $corrections';
    }

    var snippetInstruction = '';
    if (snippets != null && snippets.isNotEmpty) {
      final triggers = snippets
          .map((s) => 'When you see "${s['trigger']}", replace it with: "${s['template']}"')
          .join('\n  ');
      snippetInstruction = '\n- Apply these snippet replacements:\n  $triggers';
    }

    return '''<|im_start|>system
You are a text formatting assistant. Your ONLY task is to clean up and format the following voice transcription. Follow these rules strictly:
- Remove filler words (um, uh, hmm, like, you know, basically, actually, so, well)
- Fix grammar, punctuation, and capitalization
- Fix misheard words based on context
- $toneInstruction
- Do NOT add new information or change the meaning
- Do NOT add explanations or commentary
- Output ONLY the formatted text, nothing else$dictInstruction$snippetInstruction
<|im_end|>
<|im_start|>user
Format this transcription:

$rawText
<|im_end|>
<|im_start|>assistant
''';
  }

  /// Extract the formatted text from the LLM response
  String _extractFormattedText(String response) {
    // Remove any trailing special tokens
    var text = response
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_start|>', '')
        .trim();

    // Remove any "Here is the formatted text:" preambles
    final preambles = [
      'here is the formatted text:',
      'here is the corrected text:',
      'formatted text:',
      'corrected text:',
    ];
    final lowerText = text.toLowerCase();
    for (final preamble in preambles) {
      if (lowerText.startsWith(preamble)) {
        text = text.substring(preamble.length).trim();
        break;
      }
    }

    return text;
  }

  /// Get model info
  Future<Map<String, dynamic>?> getModelInfo() async {
    if (!_isModelLoaded || _llama == null) return null;
    try {
      return await _llama!.getModelInfo();
    } catch (e) {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_llama != null) {
      try {
        await _llama!.unloadModel();
      } catch (e) {
        debugPrint('LLM: Dispose error: $e');
      }
    }
    _isModelLoaded = false;
  }
}
