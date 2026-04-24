import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../models/app_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/snippet.dart';
import '../models/processing_state.dart';

/// Service for managing app settings, personal dictionary, and snippet library.
/// Uses Pretty-Printed JSON text files for local persistence.
class SettingsService {
  static const _encoder = JsonEncoder.withIndent('  ');
  static const _settingsFileName = 'settings.json';
  static const _dictionaryFileName = 'dictionary.json';
  static const _snippetsFileName = 'snippets.json';

  String? _basePath;
  final _uuid = const Uuid();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize file paths
  Future<void> initialize() async {
    if (_isInitialized) return;

    final extDir = await getExternalStorageDirectory();
    final internalDir = await getApplicationDocumentsDirectory();
    _basePath = (extDir ?? internalDir).path;

    _isInitialized = true;
    debugPrint('Settings: Initialized in $_basePath');
    
    // Cleanup legacy files on background
    _cleanupLegacyFiles();
  }

  Future<void> _cleanupLegacyFiles() async {
    try {
      final legacyFiles = [
        'settings.hive',
        'settings.hive.lock',
        'dictionary.hive',
        'dictionary.hive.lock',
        'snippets.hive',
        'snippets.hive.lock',
      ];

      for (final fileName in legacyFiles) {
        final file = _getFile(fileName);
        if (file.existsSync()) {
          await file.delete();
          debugPrint('Settings: Deleted legacy file $fileName');
        }
      }

      // Also cleanup any .json.part files that might be stuck
      final dir = Directory(_basePath!);
      final files = dir.listSync();
      for (final f in files) {
        if (f is File && f.path.endsWith('.part')) {
           await f.delete();
        }
      }
    } catch (e) {
      debugPrint('Settings: Cleanup error: $e');
    }
  }

  File _getFile(String fileName) {
    return File(p.join(_basePath!, fileName));
  }

  // --- App Settings ---

  AppSettings getSettings() {
    try {
      final file = _getFile(_settingsFileName);
      if (!file.existsSync()) return AppSettings();
      
      final content = file.readAsStringSync();
      final json = jsonDecode(content);
      return AppSettings.fromJson(Map<String, dynamic>.from(json as Map));
    } catch (e) {
      debugPrint('Settings: Error reading settings: $e');
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final file = _getFile(_settingsFileName);
      await file.writeAsString(_encoder.convert(settings.toJson()));
      debugPrint('Settings: Saved to $_settingsFileName');
    } catch (e) {
      debugPrint('Settings: Error saving settings: $e');
    }
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

  Future<void> updateWhisperModel(String model) async {
    final settings = getSettings();
    settings.whisperModel = model;
    await saveSettings(settings);
  }

  Future<void> updateNLPModel(String model) async {
    final settings = getSettings();
    settings.nlpModel = model;
    await saveSettings(settings);
  }

  Future<void> updateNoiseCleaningModel(String model) async {
    final settings = getSettings();
    settings.noiseCleaningModel = model;
    await saveSettings(settings);
  }

  Future<void> setNoiseFilterEnabled(bool enabled) async {
    final settings = getSettings();
    settings.noiseFilterEnabled = enabled;
    await saveSettings(settings);
  }

  // --- Model Registry Sync ---

  String? getRegistryEtag() {
    try {
      final file = _getFile('registry_etag.txt');
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  Future<void> setRegistryEtag(String etag) async {
    try {
      final file = _getFile('registry_etag.txt');
      await file.writeAsString(etag);
    } catch (_) {}
  }

  // --- Personal Dictionary ---

  List<DictionaryEntry> getDictionary() {
    try {
      final file = _getFile(_dictionaryFileName);
      if (!file.existsSync()) return [];
      
      final content = file.readAsStringSync();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList
          .map((e) => DictionaryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('Settings: Error reading dictionary: $e');
      return [];
    }
  }

  Future<void> _saveDictionary(List<DictionaryEntry> entries) async {
    try {
      final file = _getFile(_dictionaryFileName);
      final jsonList = entries.map((e) => e.toJson()).toList();
      await file.writeAsString(_encoder.convert(jsonList));
    } catch (e) {
      debugPrint('Settings: Error saving dictionary: $e');
    }
  }

  Future<void> addDictionaryEntry(String misheardWord, String correctWord) async {
    final entries = getDictionary();
    final entry = DictionaryEntry(
      id: _uuid.v4(),
      misheardWord: misheardWord,
      correctWord: correctWord,
    );
    entries.add(entry);
    await _saveDictionary(entries);
  }

  Future<void> updateDictionaryEntry(
    String id,
    String misheardWord,
    String correctWord,
  ) async {
    final entries = getDictionary();
    final index = entries.indexWhere((e) => e.id == id);
    if (index != -1) {
      entries[index].misheardWord = misheardWord;
      entries[index].correctWord = correctWord;
      await _saveDictionary(entries);
    }
  }

  Future<void> deleteDictionaryEntry(String id) async {
    final entries = getDictionary();
    entries.removeWhere((e) => e.id == id);
    await _saveDictionary(entries);
  }

  List<Map<String, String>> getDictionaryForPrompt() {
    return getDictionary()
        .map((e) => {'misheard': e.misheardWord, 'correct': e.correctWord})
        .toList();
  }

  // --- Snippet Library ---

  List<Snippet> getSnippets() {
    try {
      final file = _getFile(_snippetsFileName);
      if (!file.existsSync()) return [];
      
      final content = file.readAsStringSync();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList
          .map((e) => Snippet.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('Settings: Error reading snippets: $e');
      return [];
    }
  }

  Future<void> _saveSnippets(List<Snippet> snippets) async {
    try {
      final file = _getFile(_snippetsFileName);
      final jsonList = snippets.map((e) => e.toJson()).toList();
      await file.writeAsString(_encoder.convert(jsonList));
    } catch (e) {
      debugPrint('Settings: Error saving snippets: $e');
    }
  }

  Future<void> addSnippet(
    String triggerPhrase,
    String templateContent, {
    String? description,
  }) async {
    final snippets = getSnippets();
    final snippet = Snippet(
      id: _uuid.v4(),
      triggerPhrase: triggerPhrase,
      templateContent: templateContent,
      description: description,
    );
    snippets.add(snippet);
    await _saveSnippets(snippets);
  }

  Future<void> updateSnippet(
    String id,
    String triggerPhrase,
    String templateContent, {
    String? description,
  }) async {
    final snippets = getSnippets();
    final index = snippets.indexWhere((s) => s.id == id);
    if (index != -1) {
      snippets[index].triggerPhrase = triggerPhrase;
      snippets[index].templateContent = templateContent;
      snippets[index].description = description;
      await _saveSnippets(snippets);
    }
  }

  Future<void> deleteSnippet(String id) async {
    final snippets = getSnippets();
    snippets.removeWhere((s) => s.id == id);
    await _saveSnippets(snippets);
  }

  List<Map<String, String>> getSnippetsForPrompt() {
    return getSnippets()
        .map((s) => {'trigger': s.triggerPhrase, 'template': s.templateContent})
        .toList();
  }

  Future<void> dispose() async {
    // No-op for JSON files
  }
}
