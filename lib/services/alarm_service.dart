import 'dart:isolate';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/event.dart';
import 'event_database_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  bool _isInitialized = false;
  static const String _alarmPortName = 'echosync_alarm_port';
  static const MethodChannel _foregroundChannel =
      MethodChannel('com.echosync.ai/foreground_service');

  Future<void> initialize({Function(String eventId)? onAlarmTrigger}) async {
    if (_isInitialized) return;

    // Initialize alarm manager
    await AndroidAlarmManager.initialize();

    // Set up port for communication between isolate and main thread
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _alarmPortName);

    port.listen((dynamic data) {
      String? eventId;
      String title = 'Alarm';

      if (data is Map) {
        eventId = data['eventId'] as String?;
        title = (data['title'] as String?) ?? 'Alarm';
      } else if (data is String) {
        // Legacy fallback
        eventId = data;
      }

      if (eventId != null) {
        // Start ringtone on main isolate — MethodChannel works here
        _foregroundChannel
            .invokeMethod<void>('startAlarmRingtone', {'title': title})
            .catchError((e) => debugPrint('startAlarmRingtone error: $e'));

        if (onAlarmTrigger != null) {
          onAlarmTrigger(eventId);
        }
      }
    });

    _isInitialized = true;
  }

  @pragma('vm:entry-point')
  static void alarmCallback(int alarmId, Map<String, dynamic> params) {
    WidgetsFlutterBinding.ensureInitialized();

    final eventId = params['eventId'] as String;
    final isPersistent = params['isPersistent'] as bool? ?? true;
    final title = params['title'] as String? ?? 'Alarm';
    final description = params['description'] as String?;

    // Send both eventId and title to main isolate so it can start the ringtone
    final sendPort = IsolateNameServer.lookupPortByName(_alarmPortName);
    sendPort?.send({'eventId': eventId, 'title': title});

    _triggerAlarmEffect(eventId, title, description, isPersistent, isAlarm: true);
  }

  @pragma('vm:entry-point')
  static void notificationCallback(int alarmId, Map<String, dynamic> params) {
    WidgetsFlutterBinding.ensureInitialized();

    final eventId = params['eventId'] as String;
    final isPersistent = params['isPersistent'] as bool? ?? false;
    final title = params['title'] as String? ?? 'Reminder';
    final description = params['description'] as String?;

    _triggerAlarmEffect(eventId, title, description, isPersistent, isAlarm: false);
  }

  @pragma('vm:entry-point')
  static void _triggerAlarmEffect(
    String eventId,
    String title,
    String? description,
    bool isPersistent, {
    bool isAlarm = true,
  }) {
    WidgetsFlutterBinding.ensureInitialized();
    NotificationService().initialize().then((_) {
      NotificationService().showImmediateNotification(
        title: isAlarm ? '🔔 $title' : '🔔 $title',
        body: isAlarm ? (description ?? 'Alarm is ringing') : (description ?? 'Reminder'),
        payload: eventId,
        persistent: isPersistent,
        isAlarm: isAlarm,
      );
    });
  }

  Future<bool> canScheduleExactAlarms() async {
    final status = await Permission.scheduleExactAlarm.status;
    return status.isGranted;
  }

  Future<bool> requestExactAlarmPermission() async {
    final status = await Permission.scheduleExactAlarm.request();
    return status.isGranted;
  }

  Future<void> openAlarmSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.alarm);
  }

  /// Returns true if the app is already whitelisted from battery optimization
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _foregroundChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (e) {
      debugPrint('isIgnoringBatteryOptimizations error: $e');
      return false;
    }
  }

  /// Shows the system dialog that lets the user whitelist this app from battery optimization
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _foregroundChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('requestIgnoreBatteryOptimizations error: $e');
    }
  }

  /// Start the persistent foreground service to prevent process killing on OEM devices
  Future<void> startForegroundService() async {
    try {
      await _foregroundChannel.invokeMethod('startForegroundService');
      debugPrint('Foreground service started');
    } catch (e) {
      debugPrint('startForegroundService error: $e');
    }
  }

  /// Stop the persistent foreground service
  Future<void> stopForegroundService() async {
    try {
      await _foregroundChannel.invokeMethod('stopForegroundService');
      debugPrint('Foreground service stopped');
    } catch (e) {
      debugPrint('stopForegroundService error: $e');
    }
  }

  /// Schedules the notification reminder via AndroidAlarmManager so it fires
  /// reliably on OEM devices (OPPO/ColorOS, Xiaomi/MIUI) that suppress
  /// flutter_local_notifications zonedSchedule.
  Future<void> scheduleNotificationAlarm(Event event) async {
    if (!_isInitialized) return;
    if (!event.hasNotification || event.notificationTime == null) return;
    if (!event.isEnabled) return;

    final now = DateTime.now();
    if (event.notificationTime!.isBefore(now)) return;

    // Use a different ID space to avoid colliding with the alarm ID.
    final notifAlarmId = event.id.hashCode ^ 0x4E4F5446; // XOR with 'NOTF'

    debugPrint('Scheduling notification alarm for ${event.title} at ${event.notificationTime}');

    await AndroidAlarmManager.oneShotAt(
      event.notificationTime!,
      notifAlarmId,
      notificationCallback,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      params: {
        'eventId': event.id,
        'isPersistent': event.isNotificationPersistent,
        'title': event.title,
        'description': event.description,
      },
    );
  }

  Future<void> cancelNotificationAlarm(String eventId) async {
    if (!_isInitialized) return;
    final notifAlarmId = eventId.hashCode ^ 0x4E4F5446;
    await AndroidAlarmManager.cancel(notifAlarmId);
  }

  Future<void> scheduleAlarm(Event event) async {
    if (!_isInitialized) return;
    if (!event.hasAlarm || event.alarmTime == null) return;
    if (!event.isEnabled) return;

    final alarmId = event.id.hashCode;
    
    // Ensure alarm time is in the future
    final now = DateTime.now();
    if (event.alarmTime!.isBefore(now)) {
      debugPrint('Cannot schedule alarm for ${event.title}: time is in the past (${event.alarmTime} < $now)');
      return;
    }

    // Check for exact alarm permission on Android 12+
    final canScheduleExact = await canScheduleExactAlarms();
    if (!canScheduleExact) {
      debugPrint('Warning: Exact alarm permission not granted. Alarm may not trigger at exact time.');
    }

    debugPrint('Scheduling alarm for ${event.title} at ${event.alarmTime}');

    await AndroidAlarmManager.oneShotAt(
      event.alarmTime!,
      alarmId,
      alarmCallback,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      params: {
        'eventId': event.id,
        'isPersistent': event.isAlarmPersistent,
        'title': event.title,
        'description': event.description,
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

    // Stop the native alarm ringtone
    try {
      await _foregroundChannel.invokeMethod('stopAlarmRingtone');
    } catch (e) {
      debugPrint('stopAlarmRingtone error: $e');
    }

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
      if (event.hasNotification && event.notificationTime != null && !event.isNotificationAcknowledged) {
        await scheduleNotificationAlarm(event);
      }
      if (event.hasAlarm && event.alarmTime != null && !event.isAlarmAcknowledged) {
        await scheduleAlarm(event);
      }
    }
  }
}
