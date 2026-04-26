import 'processing_state.dart';

class AppSettings {
  TranscriptionStyle transcriptionStyle;
  TranscriptionTone transcriptionTone;
  String whisperModel;
  String nlpModel;
  String noiseCleaningModel;
  bool noiseFilterEnabled;
  bool useWhisperCppEngine;

  AppSettings({
    this.transcriptionStyle = TranscriptionStyle.smart,
    this.transcriptionTone = TranscriptionTone.formal,
    this.whisperModel = '',
    this.nlpModel = '',
    this.noiseCleaningModel = '',
    this.noiseFilterEnabled = true,
    this.useWhisperCppEngine = false,
  });

  Map<String, dynamic> toJson() => {
    'transcriptionStyle': transcriptionStyle.index,
    'transcriptionTone': transcriptionTone.index,
    'whisperModel': whisperModel,
    'nlpModel': nlpModel,
    'noiseCleaningModel': noiseCleaningModel,
    'noiseFilterEnabled': noiseFilterEnabled,
    'useWhisperCppEngine': useWhisperCppEngine,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    transcriptionStyle:
        TranscriptionStyle.values[json['transcriptionStyle'] as int? ?? 1],
    transcriptionTone:
        TranscriptionTone.values[json['transcriptionTone'] as int? ?? 0],
    whisperModel: json['whisperModel'] as String? ?? '',
    nlpModel: json['nlpModel'] as String? ?? '',
    noiseCleaningModel: json['noiseCleaningModel'] as String? ?? '',
    noiseFilterEnabled: json['noiseFilterEnabled'] as bool? ?? true,
    useWhisperCppEngine: json['useWhisperCppEngine'] as bool? ?? false,
  );
}
