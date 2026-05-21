"""
EchoSync Configuration
Centralized settings for easy tuning without code changes.
"""

from dataclasses import dataclass


@dataclass
class STTConfig:
    """Speech-to-Text configuration."""
    
    # Model selection
    model_size_small: str = "small"
    model_size_medium: str = "medium"
    ram_threshold_gb: int = 8
    
    # Transcription parameters
    language: str = "ur"  # Urdu
    initial_prompt: str = "یہ اردو، پنجابی اور انگریزی میں بات چیت ہے۔ Roman Urdu bhi use ho sakti hai."
    
    # Speed vs accuracy tradeoff
    beam_size_final: int = 3      # Higher = more accurate, slower (1-5)
    beam_size_partial: int = 1    # Keep at 1 for real-time
    best_of_final: int = 3        # Higher = more accurate, slower (1-5)
    best_of_partial: int = 1      # Keep at 1 for real-time
    
    # Quality thresholds
    temperature: float = 0.0                    # 0 = deterministic
    compression_ratio_threshold: float = 2.4    # Filters repetitions
    log_prob_threshold: float = -1.0            # Filters low confidence
    no_speech_threshold: float = 0.6            # Silence detection
    
    # Performance
    condition_on_previous_text: bool = True     # Use context
    without_timestamps: bool = True             # Faster text-only mode
    
    # CPU optimization
    num_workers: int = 4          # CPU threads for parallel processing
    cpu_threads: int = 4          # Per-worker threads


@dataclass
class VADConfig:
    """Voice Activity Detection configuration."""
    
    # Energy-based VAD
    energy_threshold: int = 150           # RMS threshold (50-500)
    speech_frames_min: int = 5            # Min frames to start (~150ms)
    silence_frames_end: int = 25          # Frames to end (~750ms)
    max_segment_frames: int = 333         # Max segment (~10s)
    
    # Silero VAD (if available)
    silero_threshold: float = 0.2         # Speech probability (0.0-1.0)
    silero_silence_window_ms: int = 700   # Silence duration to end
    
    # Partial transcript timing
    partial_interval_seconds: float = 2.0  # How often to emit partials
    partial_window_frames: int = 200       # Context window (~6s)


@dataclass
class AudioConfig:
    """Audio capture configuration."""
    
    sample_rate: int = 16000
    channels: int = 1
    dtype: str = "int16"
    frame_ms: int = 30
    

@dataclass
class AppConfig:
    """Application-wide configuration."""
    
    stt: STTConfig = STTConfig()
    vad: VADConfig = VADConfig()
    audio: AudioConfig = AudioConfig()
    
    # Logging
    log_level: str = "INFO"
    log_transcripts: bool = True
    log_timings: bool = True


# Global config instance
config = AppConfig()


def tune_for_speed():
    """Optimize for fastest transcription (lower accuracy)."""
    config.stt.beam_size_final = 1
    config.stt.best_of_final = 1
    config.stt.model_size_small = "tiny"
    config.vad.partial_window_frames = 100  # 3s window


def tune_for_accuracy():
    """Optimize for best accuracy (slower)."""
    config.stt.beam_size_final = 5
    config.stt.best_of_final = 5
    config.stt.model_size_small = "medium"
    config.vad.partial_window_frames = 267  # 8s window


def tune_for_noisy_environment():
    """Optimize for noisy environments."""
    config.vad.energy_threshold = 250
    config.vad.speech_frames_min = 8
    config.stt.no_speech_threshold = 0.7


def tune_for_quiet_environment():
    """Optimize for quiet environments (sensitive mic)."""
    config.vad.energy_threshold = 80
    config.vad.speech_frames_min = 3
    config.stt.no_speech_threshold = 0.5


# Example usage:
# from config import config, tune_for_speed
# tune_for_speed()  # Apply speed optimizations
