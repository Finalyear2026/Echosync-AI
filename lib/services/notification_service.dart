import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/event.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  Function(String eventId)? _onNotificationTap;

  Future<void> initialize({Function(String eventId)? onNotificationTap}) async {
    // Always update the tap handler so re-calls from EchoSyncAppState take effect.
    if (onNotificationTap != null) {
      _onNotificationTap = onNotificationTap;
    }

    if (_isInitialized) return;

    // Initialize timezone data and resolve the device local timezone.
    // DateTime.now().timeZoneName gives the IANA name on Android (e.g. "Asia/Karachi").
    tz_data.initializeTimeZones();
    try {
      final timezoneName = DateTime.now().timeZoneName;
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      // fallback: keep UTC
    }

    // Android initialization settings
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings (for future compatibility)
    const DarwinInitializationSettings darwinInitializationSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const InitializationSettings initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: darwinInitializationSettings,
    );

    // Initialize the plugin
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channels
    await _createNotificationChannels();

    _isInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      'alarm_events',
      'Alarm Notifications',
      description: 'Alarm sounds and vibration.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel persistentChannel = AndroidNotificationChannel(
      'persistent_events',
      'Persistent Event Notifications',
      description: 'Notifications that cannot be swiped away. Must be acknowledged.',
      importance: Importance.high,
    );

    const AndroidNotificationChannel nonPersistentChannel = AndroidNotificationChannel(
      'non_persistent_events',
      'Non-Persistent Event Notifications',
      description: 'Regular notifications that can be swiped away.',
      importance: Importance.high,
    );

    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(alarmChannel);
    await androidPlugin?.createNotificationChannel(persistentChannel);
    await androidPlugin?.createNotificationChannel(nonPersistentChannel);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && _onNotificationTap != null) {
      _onNotificationTap!(payload);
    }
  }

  Future<bool> scheduleNotification(Event event) async {
    if (!_isInitialized) {
      debugPrint('NotificationService not initialized, cannot schedule');
      return false;
    }
    if (!event.hasNotification || event.notificationTime == null) {
      debugPrint('Event ${event.title} has no notification or no time set');
      return false;
    }
    if (!event.isEnabled) {
      debugPrint('Event ${event.title} is disabled, skipping notification');
      return false;
    }

    // Check if notification time is in the past
    final now = DateTime.now();
    if (event.notificationTime!.isBefore(now)) {
      debugPrint('Cannot schedule notification for ${event.title}: time is in the past (${event.notificationTime} < $now)');
      return false;
    }

    try {
      final channelId = event.isNotificationPersistent ? 'persistent_events' : 'non_persistent_events';
      final ongoing = event.isNotificationPersistent;
      final autoCancel = !event.isNotificationPersistent;

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId,
        event.isNotificationPersistent 
            ? 'Persistent Event Notifications' 
            : 'Non-Persistent Event Notifications',
        channelDescription: event.isNotificationPersistent
            ? 'Notifications that cannot be swiped away. Must be acknowledged.'
            : 'Regular notifications that can be swiped away.',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: ongoing,
        autoCancel: autoCancel,
        category: AndroidNotificationCategory.event,
        visibility: NotificationVisibility.public,
        fullScreenIntent: event.isNotificationPersistent,
        showWhen: true,
        when: event.notificationTime!.millisecondsSinceEpoch,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      final t = event.notificationTime!;
      final scheduledDate = tz.TZDateTime(
        tz.local, t.year, t.month, t.day, t.hour, t.minute, t.second,
      );

      debugPrint('Scheduling notification for ${event.title} at ${event.notificationTime} (local: $scheduledDate)');

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        event.id.hashCode, // Use hash of event id as notification id
        event.title,
        event.description ?? 'Event notification',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: event.id,
      );

      debugPrint('Notification scheduled successfully for ${event.title}');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Failed to schedule notification for ${event.title}: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  }

  Future<void> cancelNotification(String eventId) async {
    if (!_isInitialized) return;
    await _flutterLocalNotificationsPlugin.cancel(eventId.hashCode);
  }

  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> showImmediateNotification({
    required String title,
    required String body,
    String? payload,
    bool persistent = false,
    bool isAlarm = false,
  }) async {
    if (!_isInitialized) return;

    final String channelId;
    final String channelName;
    final String channelDesc;
    final Importance importance;
    final Priority priority;

    if (isAlarm) {
      channelId = 'alarm_events';
      channelName = 'Alarm Notifications';
      channelDesc = 'Alarm sounds and vibration.';
      importance = Importance.max;
      priority = Priority.max;
    } else if (persistent) {
      channelId = 'persistent_events';
      channelName = 'Persistent Event Notifications';
      channelDesc = 'Notifications that cannot be swiped away. Must be acknowledged.';
      importance = Importance.high;
      priority = Priority.high;
    } else {
      channelId = 'non_persistent_events';
      channelName = 'Non-Persistent Event Notifications';
      channelDesc = 'Regular notifications that can be swiped away.';
      importance = Importance.high;
      priority = Priority.high;
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: priority,
      ongoing: persistent && !isAlarm,
      autoCancel: !persistent || isAlarm,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: isAlarm,
      category: isAlarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.event,
      visibility: NotificationVisibility.public,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (!_isInitialized) return [];
    return await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }

  Future<void> requestPermissions() async {
    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }
}
