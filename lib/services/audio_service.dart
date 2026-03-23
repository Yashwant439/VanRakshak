import 'package:record/record.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Audio service for VanRakshak with continuous listening support.
///
/// Provides two modes:
/// 1. **One-shot recording**: Record → stop → get bytes (original behavior)
/// 2. **Continuous listening**: Record in short segments, extract 0.975s frames
///    via a ring buffer, and emit frames through a stream for real-time inference.
class AudioService {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isContinuousMode = false;

  // Ring buffer for continuous audio (stores float32 samples at 16kHz)
  List<double> _ringBuffer = [];

  /// Max ring buffer size: 4 seconds at 16kHz = 64000 samples
  static const int _ringBufferMaxSamples = 64000;

  /// YAMNet frame size: 0.975s at 16kHz = 15600 samples
  static const int frameSize = 15600;

  /// Target sample rate
  static const int sampleRate = 16000;

  // Continuous mode timer & stream
  Timer? _continuousTimer;
  final _frameController = StreamController<List<double>>.broadcast();

  // Callbacks
  Function(List<int>)? onAudioChunk;
  Function(String)? onError;

  bool get isRecording => _isRecording;
  bool get isContinuousMode => _isContinuousMode;
  List<double> get ringBuffer => _ringBuffer;

  /// Stream of audio frames (each exactly [frameSize] samples) for real-time inference
  Stream<List<double>> get audioFrameStream => _frameController.stream;

  Future<bool> requestMicrophonePermission() async {
    final hasPermission = await _recorder.hasPermission();
    return hasPermission;
  }

  /// Start one-shot recording to a file. Call [stopRecording] to get the audio bytes.
  Future<void> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = p.join(
          tempDir.path,
          'recording_${DateTime.now().millisecondsSinceEpoch}.wav',
        );

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: sampleRate,
            numChannels: 1,
          ),
          path: path,
        );
        _isRecording = true;
        _ringBuffer.clear();
      } else {
        onError?.call('Microphone permission denied');
      }
    } catch (e) {
      onError?.call('Error starting recording: $e');
    }
  }

  /// Start continuous listening mode.
  ///
  /// Records in 1-second segments, extracts audio frames, and emits them
  /// through [audioFrameStream] for real-time inference.
  Future<void> startContinuousListening() async {
    try {
      if (!await _recorder.hasPermission()) {
        onError?.call('Microphone permission denied');
        return;
      }

      _isContinuousMode = true;
      _isRecording = true;
      _ringBuffer.clear();

      // Start recording the first segment
      await _startNewSegment();

      // Every 1 second: stop, process, restart
      _continuousTimer = Timer.periodic(
        const Duration(milliseconds: 1000),
        (_) => _processSegmentAndRestart(),
      );
    } catch (e) {
      onError?.call('Error starting continuous listening: $e');
      _isContinuousMode = false;
      _isRecording = false;
    }
  }

  /// Stop continuous listening mode.
  Future<void> stopContinuousListening() async {
    _continuousTimer?.cancel();
    _continuousTimer = null;
    _isContinuousMode = false;

    try {
      await _recorder.stop();
    } catch (_) {}

    _isRecording = false;
    _ringBuffer.clear();
  }

  Future<void> _startNewSegment() async {
    final tempDir = await getTemporaryDirectory();
    final path = p.join(
      tempDir.path,
      'segment_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
      path: path,
    );
  }

  Future<void> _processSegmentAndRestart() async {
    if (!_isContinuousMode) return;

    try {
      // Stop current recording to get the file
      final recordedPath = await _recorder.stop();

      if (recordedPath != null) {
        final file = File(recordedPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final samples = convertBytesToFloat32(bytes);

          // Add to ring buffer
          _ringBuffer.addAll(samples);

          // Trim ring buffer to max size
          if (_ringBuffer.length > _ringBufferMaxSamples) {
            _ringBuffer = _ringBuffer.sublist(
              _ringBuffer.length - _ringBufferMaxSamples,
            );
          }

          // Extract and emit frame if we have enough data
          if (_ringBuffer.length >= frameSize) {
            final frame = _ringBuffer.sublist(
              _ringBuffer.length - frameSize,
            );
            _frameController.add(frame);
          }

          // Clean up temp file
          try {
            await file.delete();
          } catch (_) {}
        }
      }

      // Restart recording for next segment
      if (_isContinuousMode) {
        await _startNewSegment();
      }
    } catch (e) {
      print('AudioService: Error processing segment: $e');
      // Try to restart even if there was an error
      if (_isContinuousMode) {
        try {
          await _startNewSegment();
        } catch (_) {}
      }
    }
  }

  Future<Uint8List?> stopRecording() async {
    try {
      final recordedPath = await _recorder.stop();
      _isRecording = false;

      if (recordedPath != null) {
        final file = File(recordedPath);
        return file.readAsBytesSync();
      }
      return null;
    } catch (e) {
      onError?.call('Error stopping recording: $e');
      return null;
    }
  }

  Future<void> pauseRecording() async {
    try {
      await _recorder.pause();
      _isRecording = false;
    } catch (e) {
      onError?.call('Error pausing recording: $e');
    }
  }

  Future<void> resumeRecording() async {
    try {
      await _recorder.resume();
      _isRecording = true;
    } catch (e) {
      onError?.call('Error resuming recording: $e');
    }
  }

  /// Convert WAV audio bytes to float32 waveform normalized to [-1.0, 1.0].
  ///
  /// Validates WAV header for correct sample rate, bit depth, and channel count.
  /// If the header indicates non-16kHz audio, the data is resampled.
  List<double> convertBytesToFloat32(Uint8List audioBytes) {
    if (audioBytes.length < 44) {
      // Too short for WAV header, treat as raw PCM
      return _rawPcmToFloat32(audioBytes, 0);
    }

    // Parse WAV header
    final byteData = ByteData.view(
      audioBytes.buffer,
      audioBytes.offsetInBytes,
      audioBytes.length,
    );

    // Check "RIFF" magic at offset 0
    final riff = String.fromCharCodes(audioBytes.sublist(0, 4));
    if (riff != 'RIFF') {
      // Not a WAV file, treat as raw PCM
      return _rawPcmToFloat32(audioBytes, 0);
    }

    // Parse header fields
    final wavSampleRate = byteData.getUint32(24, Endian.little);
    final bitsPerSample = byteData.getUint16(34, Endian.little);
    final numChannels = byteData.getUint16(22, Endian.little);

    // Find "data" chunk — it's usually at offset 36, but be safe
    int dataOffset = 44; // Standard WAV header size
    for (int i = 36; i < audioBytes.length - 4; i++) {
      if (audioBytes[i] == 0x64 && // 'd'
          audioBytes[i + 1] == 0x61 && // 'a'
          audioBytes[i + 2] == 0x74 && // 't'
          audioBytes[i + 3] == 0x61) { // 'a'
        dataOffset = i + 8; // Skip "data" + chunk size (4 bytes)
        break;
      }
    }

    // Convert PCM samples to float32
    final List<double> samples = _rawPcmToFloat32(audioBytes, dataOffset, bitsPerSample: bitsPerSample);

    // If stereo, convert to mono by averaging channels
    List<double> monoSamples;
    if (numChannels == 2) {
      monoSamples = [];
      for (int i = 0; i < samples.length - 1; i += 2) {
        monoSamples.add((samples[i] + samples[i + 1]) / 2.0);
      }
    } else {
      monoSamples = samples;
    }

    // Resample if needed
    if (wavSampleRate != sampleRate) {
      monoSamples = _resample(monoSamples, wavSampleRate, sampleRate);
    }

    return monoSamples;
  }

  /// Convert raw PCM bytes to float32, starting at [startOffset].
  List<double> _rawPcmToFloat32(Uint8List audioBytes, int startOffset, {int bitsPerSample = 16}) {
    final byteData = ByteData.view(
      audioBytes.buffer,
      audioBytes.offsetInBytes,
      audioBytes.length,
    );
    final List<double> float32Data = [];

    if (bitsPerSample == 16) {
      for (int i = startOffset; i < audioBytes.length - 1; i += 2) {
        final int16 = byteData.getInt16(i, Endian.little);
        float32Data.add(int16 / 32768.0);
      }
    } else if (bitsPerSample == 8) {
      for (int i = startOffset; i < audioBytes.length; i++) {
        final uint8 = audioBytes[i];
        float32Data.add((uint8 - 128) / 128.0);
      }
    } else if (bitsPerSample == 32) {
      for (int i = startOffset; i < audioBytes.length - 3; i += 4) {
        final int32 = byteData.getInt32(i, Endian.little);
        float32Data.add(int32 / 2147483648.0);
      }
    }

    return float32Data;
  }

  /// Simple linear interpolation resampling.
  List<double> _resample(List<double> audio, int inputRate, int outputRate) {
    if (inputRate == outputRate) return audio;

    final ratio = inputRate / outputRate;
    final outputLength = (audio.length / ratio).floor();
    final resampled = <double>[];

    for (int i = 0; i < outputLength; i++) {
      final srcIndex = i * ratio;
      final srcFloor = srcIndex.floor();
      final srcCeil = min(srcFloor + 1, audio.length - 1);
      final frac = srcIndex - srcFloor;

      // Linear interpolation
      resampled.add(audio[srcFloor] * (1 - frac) + audio[srcCeil] * frac);
    }

    return resampled;
  }

  /// Downsample helper (legacy compatibility)
  List<double> downsample(List<double> audio, int inputRate, int outputRate) {
    return _resample(audio, inputRate, outputRate);
  }

  /// Extract a single YAMNet-compatible frame from audio data.
  /// Returns null if audio is too short.
  List<double>? extractFrame(List<double> audio, {int offset = 0}) {
    if (audio.length < offset + frameSize) return null;
    return audio.sublist(offset, offset + frameSize);
  }

  /// Extract all possible frames from audio data with given overlap ratio.
  List<List<double>> extractAllFrames(List<double> audio, {double overlapRatio = 0.5}) {
    final frames = <List<double>>[];
    final stride = (frameSize * (1 - overlapRatio)).toInt();

    for (int start = 0; start + frameSize <= audio.length; start += stride) {
      frames.add(audio.sublist(start, start + frameSize));
    }

    return frames;
  }

  void dispose() {
    _continuousTimer?.cancel();
    _frameController.close();
    _recorder.dispose();
  }
}
