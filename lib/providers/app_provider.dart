import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/ml_service.dart';
import '../services/alert_service.dart';
import '../services/storage_service.dart';
import '../services/runanywhere_service.dart';
import 'dart:async';
import 'dart:typed_data';

class AppProvider extends ChangeNotifier {
  final AudioService audioService;
  final MLService mlService;
  final AlertService alertService;
  final StorageService storageService;
  final RunAnywhereService runAnywhereService;

  // State variables
  bool _isListening = false;
  String _detectionStatus = 'Idle';
  String? _lastDetectedLabel;
  double? _lastConfidence;
  int _currentZone = 1;
  double _sensitivity = 0.5;
  bool _lowPowerMode = false;
  int _unreadAlerts = 0;

  // Detection stream
  Timer? _detectionTimer;

  // Getters
  bool get isListening => _isListening;
  String get detectionStatus => _detectionStatus;
  String? get lastDetectedLabel => _lastDetectedLabel;
  double? get lastConfidence => _lastConfidence;
  int get currentZone => _currentZone;
  double get sensitivity => _sensitivity;
  bool get lowPowerMode => _lowPowerMode;
  int get unreadAlerts => _unreadAlerts;

  List<Alert> get alerts => alertService.alerts;

  AppProvider({
    required this.audioService,
    required this.mlService,
    required this.alertService,
    required this.storageService,
    required this.runAnywhereService,
  }) {
    _init();
  }

  Future<void> _init() async {
    // Load saved settings
    _sensitivity = storageService.getSensitivity();
    _currentZone = storageService.getCurrentZone();
    _lowPowerMode = storageService.getLowPowerMode();
    
    // Load previous alerts
    final saved = storageService.getAlerts();
    alertService.alerts = saved;
    
    // Load model
    await mlService.loadModel();
    
    notifyListeners();
  }

  Future<void> startListening() async {
    try {
      _detectionStatus = 'Requesting permission...';
      notifyListeners();

      final hasPermission = await audioService.requestMicrophonePermission();
      if (!hasPermission) {
        _detectionStatus = 'Microphone permission denied';
        notifyListeners();
        return;
      }

      await audioService.startRecording();
      _isListening = true;
      _detectionStatus = 'Listening...';
      notifyListeners();

      // Simulate continuous detection (in production, process real audio stream)
      _startDetectionLoop();
    } catch (e) {
      _detectionStatus = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    try {
      final audioBytes = await audioService.stopRecording();
      _isListening = false;
      _detectionTimer?.cancel();
      _detectionStatus = 'Idle';
      notifyListeners();

      if (audioBytes != null) {
        await _processAudio(audioBytes);
      }
    } catch (e) {
      _detectionStatus = 'Error: $e';
      notifyListeners();
    }
  }

  void _startDetectionLoop() {
    // Simulate audio chunk processing every 2 seconds
    _detectionTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      // In production, process real audio chunks from the stream
      // For demo, simulate random detections based on sensitivity
      final shouldDetect = (_sensitivity > 0.3);
      
      if (shouldDetect && _isListening) {
        // Simulate inference
        final fakeDetection = _generateDemoDetection();
        if (fakeDetection != null) {
          alertService.createAlert(fakeDetection, _currentZone);
          _lastDetectedLabel = fakeDetection.label;
          _lastConfidence = fakeDetection.confidence;
          await storageService.saveAlert(alertService.alerts.first);
          _unreadAlerts++;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _processAudio(Uint8List audioBytes) async {
    try {
      _detectionStatus = 'Processing...';
      notifyListeners();

      // Convert bytes to float32
      final float32 = audioService.convertBytesToFloat32(audioBytes);

      // Run inference
      final detection = await mlService.detectFromAudio(float32);

      if (detection != null && detection.confidence >= _sensitivity) {
        alertService.createAlert(detection, _currentZone);
        _lastDetectedLabel = detection.label;
        _lastConfidence = detection.confidence;
        await storageService.saveAlert(alertService.alerts.first);
        _unreadAlerts++;
        _detectionStatus = 'Detected: ${detection.label}';
      } else {
        _detectionStatus = 'No threat detected';
      }

      notifyListeners();
    } catch (e) {
      _detectionStatus = 'Error processing: $e';
      notifyListeners();
    }
  }

  DetectionResult? _generateDemoDetection() {
    // Simulated detection for demo mode
    final random = DateTime.now().millisecond % 100;
    
    if (random < 30) {
      return DetectionResult(
        label: 'gunshot',
        confidence: 0.75 + (random % 20) / 100,
        threat: ThreatLevel.critical,
        timestamp: DateTime.now(),
        allPredictions: [],
      );
    } else if (random < 60) {
      return DetectionResult(
        label: 'chainsaw',
        confidence: 0.65 + (random % 20) / 100,
        threat: ThreatLevel.warning,
        timestamp: DateTime.now(),
        allPredictions: [],
      );
    }
    
    return null;
  }

  Future<void> simulateDetection(String type) async {
    _detectionStatus = 'Simulating $type detection...';
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    final detection = DetectionResult(
      label: type,
      confidence: type == 'gunshot' ? 0.85 : 0.75,
      threat: type == 'gunshot' ? ThreatLevel.critical : ThreatLevel.warning,
      timestamp: DateTime.now(),
      allPredictions: [],
    );

    alertService.createAlert(detection, _currentZone);
    _lastDetectedLabel = type;
    _lastConfidence = detection.confidence;
    await storageService.saveAlert(alertService.alerts.first);
    _unreadAlerts++;

    _detectionStatus = 'Detected: $type';
    notifyListeners();
  }

  Future<void> setSensitivity(double value) async {
    _sensitivity = value;
    await storageService.saveSensitivity(value);
    notifyListeners();
  }

  Future<void> setCurrentZone(int zone) async {
    _currentZone = zone;
    await storageService.saveCurrentZone(zone);
    notifyListeners();
  }

  Future<void> setLowPowerMode(bool value) async {
    _lowPowerMode = value;
    await storageService.saveLowPowerMode(value);
    notifyListeners();
  }

  Future<void> clearAlerts() async {
    alertService.clearAlerts();
    await storageService.clearAlerts();
    _unreadAlerts = 0;
    notifyListeners();
  }

  void markAlertAsRead(Alert alert) {
    alert.isRead = true;
    storageService.saveAlert(alert);
    if (_unreadAlerts > 0) _unreadAlerts--;
    notifyListeners();
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    audioService.dispose();
    mlService.dispose();
    storageService.close();
    super.dispose();
  }
}
