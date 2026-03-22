import 'package:uuid/uuid.dart';
import 'ml_service.dart';

class AlertService {
  List<Alert> alerts = [];
  Function(Alert)? onNewAlert;

  // Statistical properties
  int gunshots = 0,
      chainsaws = 0,
      totalAlerts = 0;

  void createAlert(DetectionResult detection, int zone) {
    final alert = Alert(
      id: const Uuid().v4(),
      type: detection.label,
      confidence: detection.confidence,
      timestamp: detection.timestamp,
      zone: zone,
      severity: _mapSeverity(detection.threat),
      severityScore: _calculateSeverityScore(detection.label, detection.confidence),
      explanation: _generateExplanation(detection.label, detection.confidence, zone),
      suggestedActions: _generateActions(detection.label),
      isRead: false,
    );

    alerts.insert(0, alert);
    totalAlerts++;

    if (detection.label == 'gunshot') gunshots++;
    if (detection.label == 'chainsaw') chainsaws++;

    onNewAlert?.call(alert);
  }

  String _mapSeverity(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.critical:
        return 'CRITICAL';
      case ThreatLevel.warning:
        return 'WARNING';
      case ThreatLevel.info:
        return 'INFO';
      case ThreatLevel.safe:
        return 'SAFE';
    }
  }

  double _calculateSeverityScore(String label, double confidence) {
    if (label == 'gunshot') return (confidence * 0.9 + 0.05).clamp(0, 1);
    if (label == 'chainsaw') return (confidence * 0.6 + 0.02).clamp(0, 0.85);
    return 0.05;
  }

  String _generateExplanation(String label, double confidence, int zone) {
    final pct = (confidence * 100).toStringAsFixed(0);

    if (label == 'gunshot') {
      return 'Gunshot detected in Zone $zone with $pct% confidence. This may indicate poaching or '
          'illegal hunting activity. Immediate ranger response is recommended to secure the area.';
    } else if (label == 'chainsaw') {
      return 'Chainsaw activity detected in Zone $zone with $pct% confidence. This could indicate '
          'illegal logging or tree felling operations. Assessment and immediate enforcement action needed.';
    }

    return 'Ambient forest sounds detected in Zone $zone. Normal wildlife activity with no immediate threat.';
  }

  List<String> _generateActions(String label) {
    if (label == 'gunshot') {
      return [
        'Deploy nearest ranger unit to GPS coordinates immediately',
        'Alert forest department control room with zone details',
        'Activate perimeter lockdown in adjacent zones',
        'Document incident with timestamp for legal records',
        'Coordinate with wildlife SOS helpline if animals injured',
      ];
    } else if (label == 'chainsaw') {
      return [
        'Dispatch anti-poaching unit to investigate sound source',
        'Alert local forest range officer and field director',
        'Activate aerial surveillance drone if available',
        'Coordinate with police for legal enforcement support',
        'Mark zone for post-incident environmental assessment',
      ];
    }

    return [
      'Continue passive monitoring',
      'Log routine patrol data',
    ];
  }

  List<Alert> getAlertsForDate(DateTime date) {
    return alerts.where((a) {
      final same = a.timestamp.year == date.year &&
          a.timestamp.month == date.month &&
          a.timestamp.day == date.day;
      return same;
    }).toList();
  }

  void clearAlerts() {
    alerts.clear();
    gunshots = 0;
    chainsaws = 0;
    totalAlerts = 0;
  }
}

class Alert {
  final String id;
  final String type;
  final double confidence;
  final DateTime timestamp;
  final int zone;
  final String severity;
  final double severityScore;
  final String explanation;
  final List<String> suggestedActions;
  bool isRead;

  Alert({
    required this.id,
    required this.type,
    required this.confidence,
    required this.timestamp,
    required this.zone,
    required this.severity,
    required this.severityScore,
    required this.explanation,
    required this.suggestedActions,
    required this.isRead,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        'zone': zone,
        'severity': severity,
        'severityScore': severityScore,
        'explanation': explanation,
        'suggestedActions': suggestedActions,
        'isRead': isRead,
      };

  factory Alert.fromJson(Map<String, dynamic> json) => Alert(
        id: json['id'],
        type: json['type'],
        confidence: json['confidence'],
        timestamp: DateTime.parse(json['timestamp']),
        zone: json['zone'],
        severity: json['severity'],
        severityScore: json['severityScore'],
        explanation: json['explanation'],
        suggestedActions: List<String>.from(json['suggestedActions']),
        isRead: json['isRead'],
      );
}
