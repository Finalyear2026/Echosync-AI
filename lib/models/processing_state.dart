/// Processing pipeline state
enum ProcessingStage {
  idle,
  recording,
  noiseFiltering,
  transcribing,
  formatting,
  completed,
  error,
}

/// Transcription style
enum TranscriptionStyle {
  raw,
  smart,
}

/// Transcription tone
enum TranscriptionTone {
  formal,
  casual,
}
