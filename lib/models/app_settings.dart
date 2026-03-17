import 'processing_state.dart';

class AppSettings {
  TranscriptionStyle transcriptionStyle;
  TranscriptionTone transcriptionTone;
  String whisperModel;
  bool noiseFilterEnabled;

  AppSettings({
    this.transcriptionStyle = TranscriptionStyle.smart,
    this.transcriptionTone = TranscriptionTone.formal,
    this.whisperModel = 'large-v3-turbo',
    this.noiseFilterEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'transcriptionStyle': transcriptionStyle.index,
        'transcriptionTone': transcriptionTone.index,
        'whisperModel': whisperModel,
        'noiseFilterEnabled': noiseFilterEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        transcriptionStyle:
            TranscriptionStyle.values[json['transcriptionStyle'] as int? ?? 1],
        transcriptionTone:
            TranscriptionTone.values[json['transcriptionTone'] as int? ?? 0],
        whisperModel: json['whisperModel'] as String? ?? 'large-v3-turbo',
        noiseFilterEnabled: json['noiseFilterEnabled'] as bool? ?? true,
      );
}
