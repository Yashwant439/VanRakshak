import 'package:hive_flutter/hive_flutter.dart';
import 'alert_service.dart';

class StorageService {
  static const String _alertsBox = 'alerts';
  static const String _settingsBox = 'settings';
  static const String _sessionBox = 'session';

  late Box<dynamic> _alertsHive;
  late Box<dynamic> _settingsHive;
  late Box<dynamic> _sessionHive;

  Future<void> init() async {
    await Hive.initFlutter();
    _alertsHive = await Hive.openBox(_alertsBox);
    _settingsHive = await Hive.openBox(_settingsBox);
    _sessionHive = await Hive.openBox(_sessionBox);
  }

  // Settings methods
  Future<void> saveSensitivity(double value) async {
    await _settingsHive.put('sensitivity', value);
  }

  double getSensitivity() {
    return _settingsHive.get('sensitivity', defaultValue: 0.5);
  }

  Future<void> saveContinuousListening(bool value) async {
    await _settingsHive.put('continuousListening', value);
  }

  bool getContinuousListening() {
    return _settingsHive.get('continuousListening', defaultValue: false);
  }

  Future<void> saveLowPowerMode(bool value) async {
    await _settingsHive.put('lowPowerMode', value);
  }

  bool getLowPowerMode() {
    return _settingsHive.get('lowPowerMode', defaultValue: false);
  }

  Future<void> saveCurrentZone(int zone) async {
    await _settingsHive.put('currentZone', zone);
  }

  int getCurrentZone() {
    return _settingsHive.get('currentZone', defaultValue: 1);
  }

  Future<void> saveNotificationsEnabled(bool value) async {
    await _settingsHive.put('notificationsEnabled', value);
  }

  bool getNotificationsEnabled() {
    return _settingsHive.get('notificationsEnabled', defaultValue: true);
  }

  // Alerts methods
  Future<void> saveAlert(Alert alert) async {
    await _alertsHive.put(alert.id, alert.toJson());
  }

  List<Alert> getAlerts() {
    final alerts = <Alert>[];
    for (final value in _alertsHive.values) {
      if (value is Map) {
        alerts.add(Alert.fromJson(Map<String, dynamic>.from(value)));
      }
    }
    return alerts;
  }

  Future<void> clearAlerts() async {
    await _alertsHive.clear();
  }

  // Session methods
  Future<void> saveLastDetectionTime(DateTime time) async {
    await _sessionHive.put('lastDetectionTime', time.toIso8601String());
  }

  DateTime? getLastDetectionTime() {
    final time = _sessionHive.get('lastDetectionTime');
    return time != null ? DateTime.parse(time) : null;
  }

  Future<void> saveTotalAlertsToday(int count) async {
    await _sessionHive.put('totalAlertsToday', count);
  }

  int getTotalAlertsToday() {
    return _sessionHive.get('totalAlertsToday', defaultValue: 0);
  }

  Future<void> saveSessionStart(DateTime time) async {
    await _sessionHive.put('sessionStart', time.toIso8601String());
  }

  DateTime? getSessionStart() {
    final time = _sessionHive.get('sessionStart');
    return time != null ? DateTime.parse(time) : null;
  }

  // Utility
  int getStorageUsageBytes() {
    int size = 0;
    for (final value in _alertsHive.values) {
      if (value is Map) size += value.toString().length;
    }
    return size;
  }

  Future<void> close() async {
    await _alertsHive.close();
    await _settingsHive.close();
    await _sessionHive.close();
  }
}
