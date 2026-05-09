import 'dart:typed_data';

/// Sliding-window PCM buffer for real-time ASR.
///
/// Accumulates raw int16 PCM samples (16 kHz mono) and evicts the oldest
/// audio once the buffer exceeds [maxSamples], retaining [seedSamples] of
/// context so the next inference window has cross-boundary continuity.
class RollingPcmBuffer {
  final int maxSamples;
  final int seedSamples;

  final List<int> _samples = [];

  static const int _sampleRate = 16000;

  RollingPcmBuffer({
    this.maxSamples = 160000,
    this.seedSamples = 32000,
  });

  int get length => _samples.length;
  bool get isEmpty => _samples.isEmpty;
  bool get isOverfull => _samples.length >= maxSamples;

  Duration get duration =>
      Duration(milliseconds: (_samples.length * 1000) ~/ _sampleRate);

  /// Decode little-endian PCM-16 bytes and append to the internal sample list.
  void append(Uint8List pcmBytes) {
    for (int i = 0; i + 1 < pcmBytes.length; i += 2) {
      int sample = pcmBytes[i] | (pcmBytes[i + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      _samples.add(sample);
    }
  }

  /// Evict the oldest samples, keeping only [seedSamples] as context seed.
  void evictOldest() {
    if (_samples.length > seedSamples) {
      _samples.removeRange(0, _samples.length - seedSamples);
    }
  }

  /// Return the current buffer as a 16 kHz mono PCM-16 WAV [Uint8List].
  Uint8List snapshot() {
    return _buildWavBytes(_samples);
  }

  /// Return at most [maxSamples] of the most-recent audio as WAV bytes.
  ///
  /// Use this for real-time inference to keep the window at a fixed size
  /// (e.g. 4 s = 64 000 samples) regardless of how long the buffer has grown,
  /// preventing per-cycle inference time from growing unboundedly.
  Uint8List snapshotWindow(int maxSamples) {
    final start =
        _samples.length <= maxSamples ? 0 : _samples.length - maxSamples;
    return _buildWavBytes(_samples.sublist(start));
  }

  /// Clear the buffer entirely.
  void clear() {
    _samples.clear();
  }

  // ── WAV construction ────────────────────────────────────────────────────

  static Uint8List _buildWavBytes(List<int> samples) {
    final dataSize = samples.length * 2;
    final totalSize = 44 + dataSize;
    final bd = ByteData(totalSize);

    // RIFF header
    bd.setUint8(0, 0x52); bd.setUint8(1, 0x49); // "RI"
    bd.setUint8(2, 0x46); bd.setUint8(3, 0x46); // "FF"
    bd.setUint32(4, totalSize - 8, Endian.little);
    bd.setUint8(8, 0x57); bd.setUint8(9, 0x41); // "WA"
    bd.setUint8(10, 0x56); bd.setUint8(11, 0x45); // "VE"

    // fmt  chunk
    bd.setUint8(12, 0x66); bd.setUint8(13, 0x6D); // "fm"
    bd.setUint8(14, 0x74); bd.setUint8(15, 0x20); // "t "
    bd.setUint32(16, 16, Endian.little);           // chunk size
    bd.setUint16(20, 1, Endian.little);            // PCM format
    bd.setUint16(22, 1, Endian.little);            // mono
    bd.setUint32(24, _sampleRate, Endian.little);  // sample rate
    bd.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little);            // block align
    bd.setUint16(34, 16, Endian.little);           // bits per sample

    // data chunk
    bd.setUint8(36, 0x64); bd.setUint8(37, 0x61); // "da"
    bd.setUint8(38, 0x74); bd.setUint8(39, 0x61); // "ta"
    bd.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      bd.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return bd.buffer.asUint8List();
  }
}
