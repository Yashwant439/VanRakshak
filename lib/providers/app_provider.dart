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
  bool _isDemoMode = false;

  // Detection state
  DetectionResult? _lastDetectionResult;
  List<DetectionResult> _detectionHistory = [];
  StreamSubscription<List<double>>? _audioSubscription;

  // Temporal smoothing: require N consecutive threat frames to trigger alert
  static const int _consecutiveFramesRequired = 2;
  int _consecutiveThreatFrames = 0;
  String? _lastThreatCategory;

  // Getters
  bool get isListening => _isListening;
  String get detectionStatus => _detectionStatus;
  String? get lastDetectedLabel => _lastDetectedLabel;
  double? get lastConfidence => _lastConfidence;
  int get currentZone => _currentZone;
  double get sensitivity => _sensitivity;
  bool get lowPowerMode => _lowPowerMode;
  int get unreadAlerts => _unreadAlerts;
  bool get isDemoMode => _isDemoMode;
  DetectionResult? get lastDetectionResult => _lastDetectionResult;
  List<DetectionResult> get detectionHistory => List.unmodifiable(_detectionHistory);
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
    _detectionStatus = 'Loading model...';
    notifyListeners();

    await mlService.loadModel();

    if (mlService.isModelLoaded) {
      _detectionStatus = 'Model loaded. Ready.';
    } else {
      _detectionStatus = 'Failed to load model';
    }

    notifyListeners();
  }

  /// Start real-time continuous listening and detection.
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

      if (!mlService.isModelLoaded) {
        _detectionStatus = 'Loading model...';
        notifyListeners();
        await mlService.loadModel();
        if (!mlService.isModelLoaded) {
          _detectionStatus = 'Model failed to load';
          notifyListeners();
          return;
        }
      }

      // Start continuous audio streaming
      await audioService.startContinuousListening();
      _isListening = true;
      _isDemoMode = false;
      _consecutiveThreatFrames = 0;
      _lastThreatCategory = null;
      _detectionStatus = 'Listening...';
      notifyListeners();

      // Subscribe to audio frames for real-time inference
      _audioSubscription = audioService.audioFrameStream.listen(
        _onAudioFrame,
        onError: (e) {
          print('AppProvider: Audio stream error: $e');
          _detectionStatus = 'Audio error: $e';
          notifyListeners();
        },
      );
    } catch (e) {
      _detectionStatus = 'Error: $e';
      notifyListeners();
    }
  }

  /// Stop listening.
  Future<void> stopListening() async {
    try {
      _audioSubscription?.cancel();
      _audioSubscription = null;

      await audioService.stopContinuousListening();
      _isListening = false;
      _consecutiveThreatFrames = 0;
      _lastThreatCategory = null;
      _detectionStatus = 'Idle';
      notifyListeners();
    } catch (e) {
      _detectionStatus = 'Error: $e';
      notifyListeners();
    }
  }

  /// Process a single audio frame from the continuous stream.
  Future<void> _onAudioFrame(List<double> frame) async {
    if (!_isListening) return;

    try {
      // Run inference
      final detection = await mlService.detectFromAudio(frame);

      if (detection == null) {
        _detectionStatus = 'Listening... (no result)';
        notifyListeners();
        return;
      }

      // Store in history
      _lastDetectionResult = detection;
      _detectionHistory.add(detection);
      if (_detectionHistory.length > 100) {
        _detectionHistory.removeAt(0);
      }

      // Update display
      _detectionStatus =
          'Listening... ${detection.rawYamnetTopLabel} (${(detection.confidence * 100).toStringAsFixed(0)}%)';

      // Check if this is a threat detection
      if (detection.isThreat && detection.confidence >= _sensitivity) {
        // Temporal smoothing: count consecutive threat frames
        if (_lastThreatCategory == detection.label) {
          _consecutiveThreatFrames++;
        } else {
          _consecutiveThreatFrames = 1;
          _lastThreatCategory = detection.label;
        }

        // Only trigger alert after N consecutive consistent threat frames
        if (_consecutiveThreatFrames >= _consecutiveFramesRequired) {
          _triggerAlert(detection);
          _consecutiveThreatFrames = 0; // Reset after triggering
        }
      } else {
        // No threat → decay the counter
        if (_consecutiveThreatFrames > 0) {
          _consecutiveThreatFrames--;
        }
      }

      notifyListeners();
    } catch (e) {
      print('AppProvider: Error processing frame: $e');
    }
  }

  /// Trigger an alert from a confirmed detection.
  Future<void> _triggerAlert(DetectionResult detection) async {
    alertService.createAlert(detection, _currentZone);
    _lastDetectedLabel = detection.label;
    _lastConfidence = detection.confidence;
    await storageService.saveAlert(alertService.alerts.first);
    await storageService.saveLastDetectionTime(detection.timestamp);
    _unreadAlerts++;

    _detectionStatus = '🚨 Detected: ${detection.label} '
        '(${(detection.confidence * 100).toStringAsFixed(0)}%)';

    print('ALERT TRIGGERED: $detection');
    notifyListeners();
  }

  /// Process a one-shot audio recording (when user manually records and stops).
  Future<void> processRecordedAudio(Uint8List audioBytes) async {
    try {
      _detectionStatus = 'Processing recording...';
      notifyListeners();

      // Convert bytes to float32
      final float32 = audioService.convertBytesToFloat32(audioBytes);

      // Run multi-frame inference for better accuracy
      final detection = await mlService.detectFromAudioMultiFrame(float32);

      if (detection != null && detection.confidence >= _sensitivity) {
        _triggerAlert(detection);
      } else if (detection != null) {
        _lastDetectedLabel = detection.label;
        _lastConfidence = detection.confidence;
        _detectionStatus =
            'Detected: ${detection.rawYamnetTopLabel} (below threshold)';
      } else {
        _detectionStatus = 'No sound detected';
      }

      notifyListeners();
    } catch (e) {
      _detectionStatus = 'Error processing: $e';
      notifyListeners();
    }
  }

  /// Simulate a detection for demo/testing purposes.
  Future<void> simulateDetection(String type) async {
    _isDemoMode = true;
    _detectionStatus = 'Simulating $type detection...';
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    final detection = DetectionResult(
      label: type,
      confidence: type == 'gunshot' ? 0.85 : 0.75,
      threat: type == 'gunshot' ? ThreatLevel.critical : ThreatLevel.warning,
      timestamp: DateTime.now(),
      allPredictions: [
        PredictionScore(
          label: type == 'gunshot' ? 'Gunshot, gunfire' : 'Chainsaw',
          score: type == 'gunshot' ? 0.85 : 0.75,
        ),
      ],
      rawYamnetTopLabel: type == 'gunshot' ? 'Gunshot, gunfire' : 'Chainsaw',
    );

    await _triggerAlert(detection);
    _detectionStatus = '(Demo) Detected: $type';
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
    _lastDetectedLabel = null;
    _lastConfidence = null;
    _lastDetectionResult = null;
    _detectionHistory.clear();
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
    _audioSubscription?.cancel();
    audioService.dispose();
    mlService.dispose();
    storageService.close();
    super.dispose();
  }
}
