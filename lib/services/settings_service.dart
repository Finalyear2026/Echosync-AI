import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/snippet.dart';
import '../models/processing_state.dart';

/// Service for managing app settings, personal dictionary, and snippet library.
/// Uses Hive for local persistence.
class SettingsService {
  static const _settingsBoxName = 'settings';
  static const _dictionaryBoxName = 'dictionary';
  static const _snippetsBoxName = 'snippets';

  late Box _settingsBox;
  late Box<DictionaryEntry> _dictionaryBox;
  late Box<Snippet> _snippetsBox;
  final _uuid = const Uuid();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize Hive boxes
  Future<void> initialize() async {
    if (_isInitialized) return;

    _settingsBox = await Hive.openBox(_settingsBoxName);
    _dictionaryBox = await Hive.openBox<DictionaryEntry>(_dictionaryBoxName);
    _snippetsBox = await Hive.openBox<Snippet>(_snippetsBoxName);
    _isInitialized = true;
    debugPrint('Settings: Initialized. Dictionary=${_dictionaryBox.length}, '
        'Snippets=${_snippetsBox.length}');
  }

  // --- App Settings ---

  AppSettings getSettings() {
    final json = _settingsBox.get('appSettings');
    if (json == null) return AppSettings();
    return AppSettings.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _settingsBox.put('appSettings', settings.toJson());
  }

  Future<void> setTranscriptionStyle(TranscriptionStyle style) async {
    final settings = getSettings();
    settings.transcriptionStyle = style;
    await saveSettings(settings);
  }

  Future<void> setTranscriptionTone(TranscriptionTone tone) async {
    final settings = getSettings();
    settings.transcriptionTone = tone;
    await saveSettings(settings);
  }

  Future<void> setWhisperModel(String model) async {
    final settings = getSettings();
    settings.whisperModel = model;
    await saveSettings(settings);
  }

  Future<void> setNoiseFilterEnabled(bool enabled) async {
    final settings = getSettings();
    settings.noiseFilterEnabled = enabled;
    await saveSettings(settings);
  }

  // --- Model Registry Sync ---

  String? getRegistryEtag() {
    return _settingsBox.get('registryEtag') as String?;
  }

  Future<void> setRegistryEtag(String etag) async {
    await _settingsBox.put('registryEtag', etag);
  }

  // --- Personal Dictionary ---

  List<DictionaryEntry> getDictionary() {
    return _dictionaryBox.values.toList();
  }

  Future<void> addDictionaryEntry(String misheardWord, String correctWord) async {
    final entry = DictionaryEntry(
      id: _uuid.v4(),
      misheardWord: misheardWord,
      correctWord: correctWord,
    );
    await _dictionaryBox.put(entry.id, entry);
  }

  Future<void> updateDictionaryEntry(
    String id,
    String misheardWord,
    String correctWord,
  ) async {
    final entry = _dictionaryBox.get(id);
    if (entry != null) {
      entry.misheardWord = misheardWord;
      entry.correctWord = correctWord;
      await entry.save();
    }
  }

  Future<void> deleteDictionaryEntry(String id) async {
    await _dictionaryBox.delete(id);
  }

  /// Get dictionary as list of maps for LLM prompt
  List<Map<String, String>> getDictionaryForPrompt() {
    return _dictionaryBox.values
        .map((e) => {'misheard': e.misheardWord, 'correct': e.correctWord})
        .toList();
  }

  // --- Snippet Library ---

  List<Snippet> getSnippets() {
    return _snippetsBox.values.toList();
  }

  Future<void> addSnippet(
    String triggerPhrase,
    String templateContent, {
    String? description,
  }) async {
    final snippet = Snippet(
      id: _uuid.v4(),
      triggerPhrase: triggerPhrase,
      templateContent: templateContent,
      description: description,
    );
    await _snippetsBox.put(snippet.id, snippet);
  }

  Future<void> updateSnippet(
    String id,
    String triggerPhrase,
    String templateContent, {
    String? description,
  }) async {
    final snippet = _snippetsBox.get(id);
    if (snippet != null) {
      snippet.triggerPhrase = triggerPhrase;
      snippet.templateContent = templateContent;
      snippet.description = description;
      await snippet.save();
    }
  }

  Future<void> deleteSnippet(String id) async {
    await _snippetsBox.delete(id);
  }

  /// Get snippets as list of maps for LLM prompt
  List<Map<String, String>> getSnippetsForPrompt() {
    return _snippetsBox.values
        .map((s) => {'trigger': s.triggerPhrase, 'template': s.templateContent})
        .toList();
  }

  Future<void> dispose() async {
    await _settingsBox.close();
    await _dictionaryBox.close();
    await _snippetsBox.close();
  }
}
