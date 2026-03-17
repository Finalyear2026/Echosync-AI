class TranscriptionResult {
  final String rawText;
  final String formattedText;
  final String language;
  final Duration audioDuration;
  final Duration processingTime;
  final DateTime timestamp;
  final bool wasNoiseFiltered;
  final bool wasFormatted;

  TranscriptionResult({
    required this.rawText,
    required this.formattedText,
    required this.language,
    required this.audioDuration,
    required this.processingTime,
    required this.timestamp,
    this.wasNoiseFiltered = false,
    this.wasFormatted = false,
  });

  String get displayText => wasFormatted ? formattedText : rawText;

  Map<String, dynamic> toJson() => {
        'rawText': rawText,
        'formattedText': formattedText,
        'language': language,
        'audioDuration': audioDuration.inMilliseconds,
        'processingTime': processingTime.inMilliseconds,
        'timestamp': timestamp.toIso8601String(),
        'wasNoiseFiltered': wasNoiseFiltered,
        'wasFormatted': wasFormatted,
      };
}
