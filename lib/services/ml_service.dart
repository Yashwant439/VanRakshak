import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:async';

class MLService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  Map<String, int> _labelMap = {};
  List<String> _labels = [];

  bool get isModelLoaded => _isModelLoaded;

  Future<void> loadModel() async {
    try {
      // Load TFLite model (YAMNet for audio classification)
      _interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
      _isModelLoaded = true;
      
      // Load labels
      await _loadLabels();
    } catch (e) {
      print('Error loading model: $e');
      _isModelLoaded = false;
    }
  }

  Future<void> _loadLabels() async {
    try {
      // For demo purposes, use predefined labels
      _labels = [
        'gunshot', 'chainsaw', 'forest_sounds', 'vehicle', 'speech',
        'wind', 'rain', 'bird_call', 'dog_bark', 'silence'
      ];
      
      for (int i = 0; i < _labels.length; i++) {
        _labelMap[_labels[i]] = i;
      }
    } catch (e) {
      print('Error loading labels: $e');
    }
  }

  Future<DetectionResult?> detectFromAudio(List<double> audioData) async {
    if (!_isModelLoaded || _interpreter == null) {
      return null;
    }

    try {
      // Prepare input: reshape to match model input shape
      // YAMNet expects: [1, audio_length]
      final input = [audioData];
      
      // Prepare output buffer
      var output = List.filled(1, List.filled(_labels.length, 0.0));
      
      // Run inference
      _interpreter!.run(input, output);
      
      // Parse results
      final scores = output[0] as List<dynamic>;
      
      // Find top 3 predictions
      final predictions = <PredictionScore>[];
      for (int i = 0; i < scores.length && i < _labels.length; i++) {
        predictions.add(PredictionScore(
          label: _labels[i],
          score: (scores[i] as num).toDouble(),
        ));
      }
      
      // Sort by confidence
      predictions.sort((a, b) => b.score.compareTo(a.score));
      
      final topPrediction = predictions.first;
      final threat = _classifyThreat(topPrediction.label, topPrediction.score);
      
      return DetectionResult(
        label: topPrediction.label,
        confidence: topPrediction.score,
        threat: threat,
        timestamp: DateTime.now(),
        allPredictions: predictions.take(3).toList(),
      );
    } catch (e) {
      print('Error running inference: $e');
      return null;
    }
  }

  ThreatLevel _classifyThreat(String label, double confidence) {
    if (label == 'gunshot' && confidence >= 0.7) {
      return ThreatLevel.critical;
    } else if (label == 'chainsaw' && confidence >= 0.7) {
      return ThreatLevel.warning;
    } else if (label == 'gunshot' && confidence >= 0.5) {
      return ThreatLevel.warning;
    } else if (label == 'chainsaw' && confidence >= 0.5) {
      return ThreatLevel.info;
    }
    return ThreatLevel.safe;
  }

  double calculateSeverityScore(String label, double confidence) {
    if (label == 'gunshot') {
      return (confidence * 0.9 + 0.05).clamp(0, 1);
    } else if (label == 'chainsaw') {
      return (confidence * 0.6 + 0.02).clamp(0, 0.85);
    }
    return 0.05;
  }

  void dispose() {
    _interpreter?.close();
  }
}

class PredictionScore {
  final String label;
  final double score;

  PredictionScore({required this.label, required this.score});
}

class DetectionResult {
  final String label;
  final double confidence;
  final ThreatLevel threat;
  final DateTime timestamp;
  final List<PredictionScore> allPredictions;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.threat,
    required this.timestamp,
    required this.allPredictions,
  });
}

enum ThreatLevel { critical, warning, info, safe }
