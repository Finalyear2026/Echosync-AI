import 'dart:isolate';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/event.dart';
import 'event_database_service.dart';
import 'notification_service.dart';

class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  bool _isInitialized = false;
  static const String _alarmPortName = 'echosync_alarm_port';
  static SendPort? _alarmSendPort;

  Future<void> initialize({Function(String eventId)? onAlarmTrigger}) async {
    if (_isInitialized) return;

    // Initialize alarm manager
    await AndroidAlarmManager.initialize();

    // Set up port for communication between isolate and main thread
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _alarmPortName);

    port.listen((dynamic data) {
      if (data is String && onAlarmTrigger != null) {
        onAlarmTrigger(data);
      }
    });

    _isInitialized = true;
  }

  static void alarmCallback(int alarmId, Map<String, dynamic> params) {
    // This runs in a separate isolate
    final eventId = params['eventId'] as String;
    final isPersistent = params['isPersistent'] as bool? ?? true;

    // Send message back to main isolate
    final sendPort = IsolateNameServer.lookupPortByName(_alarmPortName);
    sendPort?.send(eventId);

    // For persistent alarms, we need to show a full-screen notification or play alarm sound
    // Since we can't access UI here, we'll trigger a high-priority notification
    _triggerAlarmEffect(eventId, isPersistent);
  }

  static void _triggerAlarmEffect(String eventId, bool isPersistent) {
    // This static method can be used to trigger effects
    // In a real implementation, you might:
    // 1. Play an alarm sound using a native method channel
    // 2. Show a full-screen intent notification
    // 3. Vibrate the device
    
    // For now, we rely on the notification service to show a high-priority notification
    NotificationService().showImmediateNotification(
      title: 'Alarm Triggered',
      body: 'An event alarm has fired',
      payload: eventId,
      persistent: isPersistent,
    );
  }

  Future<void> scheduleAlarm(Event event) async {
    if (!_isInitialized) return;
    if (!event.hasAlarm || event.alarmTime == null) return;

    final alarmId = event.id.hashCode;
    
    // Ensure alarm time is in the future
    if (event.alarmTime!.isBefore(DateTime.now())) return;

    await AndroidAlarmManager.oneShotAt(
      event.alarmTime!,
      alarmId,
      alarmCallback,
      alarmClock: event.isAlarmPersistent,
      allowWhileIdle: true,
      exact: true,
      wakeup: event.isAlarmPersistent,
      rescheduleOnReboot: true,
      params: {
        'eventId': event.id,
        'isPersistent': event.isAlarmPersistent,
      },
    );
  }

  Future<void> cancelAlarm(String eventId) async {
    if (!_isInitialized) return;
    final alarmId = eventId.hashCode;
    await AndroidAlarmManager.cancel(alarmId);
  }

  Future<void> cancelAllAlarms() async {
    if (!_isInitialized) return;
    // AndroidAlarmManager doesn't have a cancelAll method
    // We need to track scheduled alarms separately or cancel individually
  }

  Future<bool> isAlarmScheduled(String eventId) async {
    if (!_isInitialized) return false;
    // Check if alarm is pending - this requires tracking separately
    // as AndroidAlarmManager doesn't expose a query method
    return false;
  }

  /// Acknowledge an alarm and stop it from ringing
  Future<void> acknowledgeAlarm(String eventId) async {
    await cancelAlarm(eventId);
    
    // Update database
    final db = EventDatabaseService();
    await db.acknowledgeEvent(eventId);
  }

  /// Reschedule all pending alarms (call on app startup)
  Future<void> rescheduleAllAlarms() async {
    if (!_isInitialized) return;

    final db = EventDatabaseService();
    final upcomingEvents = await db.getUpcomingEvents();

    for (final event in upcomingEvents) {
      if (event.hasAlarm && event.alarmTime != null && !event.isAlarmAcknowledged) {
        await scheduleAlarm(event);
      }
      if (event.hasNotification && event.notificationTime != null && !event.isNotificationAcknowledged) {
        await NotificationService().scheduleNotification(event);
      }
    }
  }
}
