import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:async';
import 'dart:math';

/// YAMNet-based sound detection service for VanRakshak.
///
/// YAMNet expects a flat float32 tensor of 15600 samples (0.975s at 16kHz)
/// and outputs scores for 521 AudioSet classes.
/// We map a subset of those 521 classes to threat categories.
class MLService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  List<String> _yamnetLabels = []; // All 521 YAMNet labels

  // Maps YAMNet class indices → our threat categories
  static const Map<String, List<int>> threatClassIndices = {
    'gunshot': [421, 422, 423, 424, 425], // Gunshot/gunfire, Machine gun, Fusillade, Artillery, Cap gun
    'explosion': [420, 426, 427, 429, 430], // Explosion, Fireworks, Firecracker, Eruption, Boom
    'chainsaw': [341],                      // Chainsaw
    'vehicle': [294, 300, 301, 310, 320],   // Vehicle, Motor vehicle, Car, Truck, Motorcycle
  };

  // Classes that commonly cause false positives for gunshots
  static const List<int> _gunshotFalsePositiveIndices = [
    460, // Bang
    461, // Slap, smack
    462, // Whack, thwack
    463, // Smash, crash
    428, // Burst, pop
  ];

  /// Required input length for YAMNet: 0.975 seconds at 16kHz
  static const int yamnetInputLength = 15600;

  /// Number of YAMNet output classes
  static const int yamnetOutputClasses = 521;

  bool get isModelLoaded => _isModelLoaded;
  List<String> get yamnetLabels => _yamnetLabels;

  Future<void> loadModel() async {
    try {
      // Load TFLite model (stock YAMNet for audio classification)
      _interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
      _isModelLoaded = true;

      // Load the real 521 YAMNet labels from CSV
      await _loadLabels();

      print('MLService: Model loaded. Labels: ${_yamnetLabels.length}');
      print('MLService: Input tensor: ${_interpreter!.getInputTensor(0).shape}');
      print('MLService: Output tensor count: ${_interpreter!.getOutputTensors().length}');
      for (int i = 0; i < _interpreter!.getOutputTensors().length; i++) {
        print('MLService: Output[$i] shape: ${_interpreter!.getOutputTensor(i).shape}');
      }
    } catch (e) {
      print('Error loading model: $e');
      _isModelLoaded = false;
    }
  }

  Future<void> _loadLabels() async {
    try {
      final csvString = await rootBundle.loadString('assets/labels/labels.csv');
      final rows = const CsvToListConverter().convert(csvString);

      // Skip header row: index, mid, display_name
      _yamnetLabels = [];
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].length >= 3) {
          _yamnetLabels.add(rows[i][2].toString());
        }
      }

      print('MLService: Loaded ${_yamnetLabels.length} labels');
    } catch (e) {
      print('Error loading labels: $e');
      // Fallback: create empty list (inference will still work, just no label names)
      _yamnetLabels = List.filled(yamnetOutputClasses, 'unknown');
    }
  }

  /// Run inference on a single audio frame.
  ///
  /// [audioFrame] must be exactly [yamnetInputLength] (15600) float32 samples
  /// at 16kHz sample rate, normalized to [-1.0, 1.0].
  Future<DetectionResult?> detectFromAudio(List<double> audioFrame) async {
    if (!_isModelLoaded || _interpreter == null) {
      return null;
    }

    try {
      // Validate and prepare input
      final frame = _prepareInput(audioFrame);

      // YAMNet TFLite has multiple outputs. The first is class scores [1, 521].
      // Some YAMNet TFLite versions output:
      //   Output 0: scores [1, 521]
      //   Output 1: embeddings [1, 1024]
      //   Output 2: log_mel [1, 96, 64]
      // We only need output 0 (scores).

      final outputTensors = _interpreter!.getOutputTensors();
      final numOutputs = outputTensors.length;

      // Prepare output buffers for all outputs
      final outputs = <int, Object>{};
      for (int i = 0; i < numOutputs; i++) {
        final shape = outputTensors[i].shape;
        if (shape.length == 2) {
          outputs[i] = List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
        } else if (shape.length == 3) {
          outputs[i] = List.generate(
            shape[0],
            (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)),
          );
        } else {
          outputs[i] = List.filled(shape.reduce((a, b) => a * b), 0.0);
        }
      }

      // Run inference with multiple outputs
      _interpreter!.runForMultipleInputs([frame], outputs);

      // Extract class scores from output 0
      final rawScores = outputs[0];
      List<double> scores;

      if (rawScores is List<List<double>>) {
        scores = rawScores[0];
      } else if (rawScores is List) {
        scores = (rawScores[0] as List).map((e) => (e as num).toDouble()).toList();
      } else {
        print('MLService: Unexpected output type: ${rawScores.runtimeType}');
        return null;
      }

      // Map YAMNet scores to our threat categories
      return _mapToThreatDetection(scores);
    } catch (e) {
      print('Error running inference: $e');
      return null;
    }
  }

  /// Process multiple overlapping frames and aggregate results.
  /// This reduces false positives by requiring consistency across frames.
  Future<DetectionResult?> detectFromAudioMultiFrame(List<double> audioData) async {
    if (audioData.length < yamnetInputLength) return null;

    final results = <DetectionResult>[];
    final stride = yamnetInputLength ~/ 2; // 50% overlap

    for (int start = 0; start + yamnetInputLength <= audioData.length; start += stride) {
      final frame = audioData.sublist(start, start + yamnetInputLength);
      final result = await detectFromAudio(frame);
      if (result != null) {
        results.add(result);
      }
    }

    if (results.isEmpty) return null;

    // Aggregate: use the result with highest threat confidence
    results.sort((a, b) {
      final aThreat = a.threat.index;
      final bThreat = b.threat.index;
      if (aThreat != bThreat) return aThreat.compareTo(bThreat);
      return b.confidence.compareTo(a.confidence);
    });

    return results.first;
  }

  /// Prepare input: ensure exactly 15600 samples, normalized.
  List<double> _prepareInput(List<double> audioFrame) {
    List<double> frame;

    if (audioFrame.length == yamnetInputLength) {
      frame = List<double>.from(audioFrame);
    } else if (audioFrame.length > yamnetInputLength) {
      // Take center crop
      final start = (audioFrame.length - yamnetInputLength) ~/ 2;
      frame = audioFrame.sublist(start, start + yamnetInputLength);
    } else {
      // Zero-pad to required length
      frame = List<double>.from(audioFrame);
      frame.addAll(List.filled(yamnetInputLength - audioFrame.length, 0.0));
    }

    // Ensure values are in [-1.0, 1.0]
    final maxAbs = frame.map((v) => v.abs()).reduce(max);
    if (maxAbs > 1.0) {
      frame = frame.map((v) => v / maxAbs).toList();
    }

    return frame;
  }

  /// Map raw 521-class YAMNet scores to our threat detection result.
  DetectionResult _mapToThreatDetection(List<double> scores) {
    // Collect scores for each threat category
    final threatScores = <String, double>{};

    for (final entry in threatClassIndices.entries) {
      final category = entry.key;
      final indices = entry.value;

      // Max score across all YAMNet classes in this threat category
      double maxScore = 0.0;
      for (final idx in indices) {
        if (idx < scores.length && scores[idx] > maxScore) {
          maxScore = scores[idx];
        }
      }
      threatScores[category] = maxScore;
    }

    // Check for false positive suppression on gunshots
    double fpScore = 0.0;
    for (final idx in _gunshotFalsePositiveIndices) {
      if (idx < scores.length && scores[idx] > fpScore) {
        fpScore = scores[idx];
      }
    }

    // If false positive classes score higher than gunshot, suppress gunshot
    if (threatScores['gunshot']! > 0 && fpScore > threatScores['gunshot']! * 0.8) {
      threatScores['gunshot'] = threatScores['gunshot']! * 0.3; // Heavily discount
    }

    // Find the top threat category
    String topCategory = 'ambient';
    double topScore = 0.0;
    for (final entry in threatScores.entries) {
      if (entry.value > topScore) {
        topScore = entry.value;
        topCategory = entry.key;
      }
    }

    // Also find top 5 raw YAMNet predictions for debugging/display
    final allPredictions = <PredictionScore>[];
    for (int i = 0; i < scores.length && i < _yamnetLabels.length; i++) {
      if (scores[i] > 0.05) {
        allPredictions.add(PredictionScore(
          label: _yamnetLabels[i],
          score: scores[i],
          yamnetIndex: i,
        ));
      }
    }
    allPredictions.sort((a, b) => b.score.compareTo(a.score));

    // Determine threat level based on category and confidence
    final threat = _classifyThreat(topCategory, topScore);

    return DetectionResult(
      label: topCategory,
      confidence: topScore,
      threat: threat,
      timestamp: DateTime.now(),
      allPredictions: allPredictions.take(5).toList(),
      rawYamnetTopLabel: allPredictions.isNotEmpty ? allPredictions.first.label : 'unknown',
    );
  }

  ThreatLevel _classifyThreat(String category, double confidence) {
    switch (category) {
      case 'gunshot':
        if (confidence >= 0.6) return ThreatLevel.critical;
        if (confidence >= 0.4) return ThreatLevel.warning;
        return ThreatLevel.info;
      case 'explosion':
        if (confidence >= 0.6) return ThreatLevel.critical;
        if (confidence >= 0.4) return ThreatLevel.warning;
        return ThreatLevel.info;
      case 'chainsaw':
        if (confidence >= 0.5) return ThreatLevel.warning;
        if (confidence >= 0.3) return ThreatLevel.info;
        return ThreatLevel.safe;
      case 'vehicle':
        if (confidence >= 0.6) return ThreatLevel.info;
        return ThreatLevel.safe;
      default:
        return ThreatLevel.safe;
    }
  }

  double calculateSeverityScore(String label, double confidence) {
    switch (label) {
      case 'gunshot':
        return (confidence * 0.95 + 0.05).clamp(0.0, 1.0);
      case 'explosion':
        return (confidence * 0.90 + 0.05).clamp(0.0, 1.0);
      case 'chainsaw':
        return (confidence * 0.70 + 0.02).clamp(0.0, 0.85);
      case 'vehicle':
        return (confidence * 0.40).clamp(0.0, 0.50);
      default:
        return 0.05;
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}

class PredictionScore {
  final String label;
  final double score;
  final int yamnetIndex;

  PredictionScore({
    required this.label,
    required this.score,
    this.yamnetIndex = -1,
  });

  @override
  String toString() => '$label: ${(score * 100).toStringAsFixed(1)}% [idx:$yamnetIndex]';
}

class DetectionResult {
  final String label;
  final double confidence;
  final ThreatLevel threat;
  final DateTime timestamp;
  final List<PredictionScore> allPredictions;
  final String rawYamnetTopLabel;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.threat,
    required this.timestamp,
    required this.allPredictions,
    this.rawYamnetTopLabel = '',
  });

  bool get isThreat => threat == ThreatLevel.critical || threat == ThreatLevel.warning;

  @override
  String toString() =>
      'DetectionResult($label, ${(confidence * 100).toStringAsFixed(1)}%, $threat, yamnet:$rawYamnetTopLabel)';
}

enum ThreatLevel { critical, warning, info, safe }
