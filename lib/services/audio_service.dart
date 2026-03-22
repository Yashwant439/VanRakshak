import 'package:record/record.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class AudioService {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  List<int> _audioBuffer = [];
  
  // Callback for audio chunks
  Function(List<int>)? onAudioChunk;
  Function(String)? onError;

  bool get isRecording => _isRecording;
  List<int> get audioBuffer => _audioBuffer;

  Future<bool> requestMicrophonePermission() async {
    final hasPermission = await _recorder.hasPermission();
    return hasPermission;
  }

  Future<void> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = p.join(tempDir.path, 'recording_${DateTime.now().millisecondsSinceEpoch}.wav');

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );
        _isRecording = true;
        _audioBuffer.clear();
      } else {
        onError?.call('Microphone permission denied');
      }
    } catch (e) {
      onError?.call('Error starting recording: $e');
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

  // Convert audio bytes to float32 waveform (required for YAMNet)
  List<double> convertBytesToFloat32(Uint8List audioBytes) {
    // WAV header is 44 bytes. Skip it to get raw PCM samples.
    // If using raw PCM (no header), set startOffset to 0.
    final int startOffset = audioBytes.length > 44 ? 44 : 0;
    final ByteData byteData = ByteData.view(
      audioBytes.buffer,
      audioBytes.offsetInBytes,
      audioBytes.length,
    );
    final List<double> float32Data = [];

    for (int i = startOffset; i < audioBytes.length - 1; i += 2) {
      final int16 = byteData.getInt16(i, Endian.little);
      float32Data.add(int16 / 32768.0);
    }

    return float32Data;
  }

  // Downsample if needed
  List<double> downsample(List<double> audio, int inputRate, int outputRate) {
    if (inputRate == outputRate) return audio;

    final ratio = inputRate / outputRate;
    final downsampled = <double>[];

    for (double i = 0; i < audio.length; i += ratio) {
      downsampled.add(audio[i.toInt()]);
    }

    return downsampled;
  }

  void dispose() {
    _recorder.dispose();
  }
}
