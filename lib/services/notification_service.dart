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
    if (_isInitialized) return;

    _onNotificationTap = onNotificationTap;

    // Initialize timezone data
    tz_data.initializeTimeZones();

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

    await androidPlugin?.createNotificationChannel(persistentChannel);
    await androidPlugin?.createNotificationChannel(nonPersistentChannel);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && _onNotificationTap != null) {
      _onNotificationTap!(payload);
    }
  }

  Future<void> scheduleNotification(Event event) async {
    if (!_isInitialized) return;
    if (!event.hasNotification || event.notificationTime == null) return;

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

    final scheduledDate = tz.TZDateTime.from(event.notificationTime!, tz.local);

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
  }) async {
    if (!_isInitialized) return;

    final channelId = persistent ? 'persistent_events' : 'non_persistent_events';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      persistent ? 'Persistent Event Notifications' : 'Non-Persistent Event Notifications',
      channelDescription: persistent
          ? 'Notifications that cannot be swiped away. Must be acknowledged.'
          : 'Regular notifications that can be swiped away.',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: persistent,
      autoCancel: !persistent,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond, // Unique id
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
