import 'alert_service.dart';

class RunAnywhereService {
  // Simulated offline LLM responses (in production, use runanywhere_flutter)
  
  Future<String> generateExplanation(String detectionType, double confidence, int zone) async {
    // Simulate LLM processing
    await Future.delayed(const Duration(milliseconds: 500));

    if (detectionType == 'gunshot') {
      return 'A gunshot has been detected with $confidence confidence in Zone $zone. '
          'This is a critical threat indicator that may suggest poaching activity. '
          'Immediate ranger dispatch to the location is strongly recommended. '
          'Wildlife in the area may be under threat and require protection measures.';
    } else if (detectionType == 'chainsaw') {
      return 'Chainsaw activity detected with $confidence confidence in Zone $zone. '
          'This indicates potential illegal logging operations. '
          'The forest canopy in this zone may be at risk. '
          'Activate anti-logging patrol units and document the incident for legal proceedings.';
    }

    return 'Forest sounds detected in Zone $zone. Normal ambient activity detected. '
        'Continue routine monitoring procedures.';
  }

  Future<List<String>> generateActionPlan(Alert alert) async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (alert.type == 'gunshot') {
      return [
        '🚨 CRITICAL: Immediate ranger dispatch required',
        '📍 GPS coordinates marked and logged',
        '🔒 Activate perimeter security measures',
        '📞 Contact forest control room for coordination',
        '⚕️ Prepare emergency medical response',
        '🎥 Enable camera traps in adjacent zones',
        '📋 Document for legal prosecution',
      ];
    } else if (alert.type == 'chainsaw') {
      return [
        '⚠️ Deploy anti-logging patrol unit',
        '🛰️ Activate aerial surveillance if available',
        '📸 Mark location for evidence collection',
        '👮 Coordinate with local law enforcement',
        '🌳 Assess environmental damage extent',
        '📊 Log incident in forest protection database',
        '🔍 Investigate source of logging equipment',
      ];
    }

    return [
      '👁️ Continue passive monitoring',
      '📝 Log routine data',
      '🔔 Maintain alert',
    ];
  }

  Future<String> answerQuery(String query, List<Alert> recentAlerts) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final lower = query.toLowerCase();

    if (lower.contains('last') || lower.contains('recent')) {
      if (recentAlerts.isEmpty) {
        return 'No alerts have been detected yet. The forest is currently quiet.';
      }
      final last = recentAlerts.first;
      return 'The last alert was a **${last.type}** detection in Zone ${last.zone} '
          'with ${(last.confidence * 100).toStringAsFixed(0)}% confidence. '
          'Severity: ${last.severity}. ${last.explanation}';
    }

    if (lower.contains('summary') || lower.contains('today')) {
      final gunshotCount = recentAlerts.where((a) => a.type == 'gunshot').length;
      final chainsawCount = recentAlerts.where((a) => a.type == 'chainsaw').length;
      return "Today's summary: ${recentAlerts.length} total detections — "
          "$gunshotCount gunshots and $chainsawCount chainsaws. "
          'Continue vigilant monitoring.';
    }

    if (lower.contains('threat')) {
      final criticalCount = recentAlerts.where((a) => a.severity == 'CRITICAL').length;
      final warningCount = recentAlerts.where((a) => a.severity == 'WARNING').length;

      if (criticalCount > 0) {
        return '🚨 HIGH THREAT LEVEL: $criticalCount critical incident(s) detected. '
            'Immediate ranger dispatch strongly recommended. '
            '$warningCount additional warning-level detections on record.';
      }

      if (warningCount > 0) {
        return 'Moderate threat level. $warningCount warning-level incident(s) require investigation. '
            'Deploy patrol units to affected zones.';
      }

      return 'Current threat level is LOW. No significant threats detected. Continue surveillance.';
    }

    if (lower.contains('help')) {
      return 'I am VanRakshak AI Ranger Assistant. Commands:\n'
          '• "Show last alert" — Latest detection details\n'
          '• "Today\'s summary" — Daily threat report\n'
          '• "Gunshot incidents" — Poaching activity\n'
          '• "Chainsaw alerts" — Logging threats\n'
          '• "Zone status" — Current zone info\n'
          '• "Threat level" — Current risk assessment';
    }

    return 'Query received: "$query". I monitor forest threats 24/7. '
        'Currently tracking ${recentAlerts.length} recorded alerts. Type "help" for commands.';
  }

  // Simulated TTS (in production, use piper TTS)
  Future<void> speak(String text) async {
    await Future.delayed(Duration(milliseconds: text.length * 50));
    print('TTS: $text');
  }
}
