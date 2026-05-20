import 'package:uuid/uuid.dart';

enum RecurrenceType { none, daily, weekly, monthly, yearly }

class Event {
  final String id;
  String title;
  String? description;
  bool isEnabled;
  final DateTime createdAt;
  DateTime updatedAt;

  // Notification settings
  bool hasNotification;
  bool isNotificationPersistent;
  DateTime? notificationTime;
  bool isNotificationAcknowledged;

  // Alarm settings
  bool hasAlarm;
  bool isAlarmPersistent;
  DateTime? alarmTime;
  bool isAlarmAcknowledged;

  // Recurrence settings
  RecurrenceType recurrenceType;
  int recurrenceInterval;
  DateTime? recurrenceEndDate;
  int? maxOccurrences;
  int occurrenceCount;

  Event({
    String? id,
    this.title = 'Blank Notifier',
    this.description,
    this.isEnabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.hasNotification = true,
    this.isNotificationPersistent = true,
    this.notificationTime,
    this.isNotificationAcknowledged = false,
    this.hasAlarm = true,
    this.isAlarmPersistent = true,
    this.alarmTime,
    this.isAlarmAcknowledged = false,
    this.recurrenceType = RecurrenceType.none,
    this.recurrenceInterval = 1,
    this.recurrenceEndDate,
    this.maxOccurrences,
    this.occurrenceCount = 0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isRecurring => recurrenceType != RecurrenceType.none;

  bool get hasNotificationPending {
    if (!hasNotification || !isEnabled) return false;
    if (notificationTime == null) return false;
    if (isNotificationAcknowledged) return false;
    return notificationTime!.isAfter(DateTime.now());
  }

  bool get hasAlarmPending {
    if (!hasAlarm || !isEnabled) return false;
    if (alarmTime == null) return false;
    if (isAlarmAcknowledged) return false;
    return alarmTime!.isAfter(DateTime.now());
  }

  bool get isUpcoming {
    final now = DateTime.now();
    if (notificationTime != null && notificationTime!.isAfter(now)) return true;
    if (alarmTime != null && alarmTime!.isAfter(now)) return true;
    return false;
  }

  bool get isExpired {
    final now = DateTime.now();
    if (notificationTime != null && notificationTime!.isBefore(now)) {
      if (alarmTime != null) {
        return alarmTime!.isBefore(now);
      }
      return true;
    }
    return false;
  }

  DateTime? get nextTriggerTime {
    if (!isEnabled) return null;
    
    DateTime? nextTime;
    
    if (hasNotification && notificationTime != null && !isNotificationAcknowledged) {
      nextTime = notificationTime;
    }
    
    if (hasAlarm && alarmTime != null && !isAlarmAcknowledged) {
      if (nextTime == null || alarmTime!.isBefore(nextTime)) {
        nextTime = alarmTime;
      }
    }
    
    return nextTime;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'is_enabled': isEnabled ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'has_notification': hasNotification ? 1 : 0,
      'is_notification_persistent': isNotificationPersistent ? 1 : 0,
      'notification_time': notificationTime?.millisecondsSinceEpoch,
      'is_notification_acknowledged': isNotificationAcknowledged ? 1 : 0,
      'has_alarm': hasAlarm ? 1 : 0,
      'is_alarm_persistent': isAlarmPersistent ? 1 : 0,
      'alarm_time': alarmTime?.millisecondsSinceEpoch,
      'is_alarm_acknowledged': isAlarmAcknowledged ? 1 : 0,
      'recurrence_type': recurrenceType.name,
      'recurrence_interval': recurrenceInterval,
      'recurrence_end_date': recurrenceEndDate?.millisecondsSinceEpoch,
      'max_occurrences': maxOccurrences,
      'occurrence_count': occurrenceCount,
    };
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      isEnabled: (json['is_enabled'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
      hasNotification: (json['has_notification'] as int) == 1,
      isNotificationPersistent: (json['is_notification_persistent'] as int) == 1,
      notificationTime: json['notification_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['notification_time'] as int)
          : null,
      isNotificationAcknowledged: (json['is_notification_acknowledged'] as int) == 1,
      hasAlarm: (json['has_alarm'] as int) == 1,
      isAlarmPersistent: (json['is_alarm_persistent'] as int) == 1,
      alarmTime: json['alarm_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['alarm_time'] as int)
          : null,
      isAlarmAcknowledged: (json['is_alarm_acknowledged'] as int) == 1,
      recurrenceType: RecurrenceType.values.firstWhere(
        (e) => e.name == json['recurrence_type'],
        orElse: () => RecurrenceType.none,
      ),
      recurrenceInterval: json['recurrence_interval'] as int? ?? 1,
      recurrenceEndDate: json['recurrence_end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['recurrence_end_date'] as int)
          : null,
      maxOccurrences: json['max_occurrences'] as int?,
      occurrenceCount: json['occurrence_count'] as int? ?? 0,
    );
  }

  Event copyWith({
    String? id,
    String? title,
    String? description,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hasNotification,
    bool? isNotificationPersistent,
    DateTime? notificationTime,
    bool? isNotificationAcknowledged,
    bool? hasAlarm,
    bool? isAlarmPersistent,
    DateTime? alarmTime,
    bool? isAlarmAcknowledged,
    RecurrenceType? recurrenceType,
    int? recurrenceInterval,
    DateTime? recurrenceEndDate,
    int? maxOccurrences,
    int? occurrenceCount,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      hasNotification: hasNotification ?? this.hasNotification,
      isNotificationPersistent: isNotificationPersistent ?? this.isNotificationPersistent,
      notificationTime: notificationTime ?? this.notificationTime,
      isNotificationAcknowledged: isNotificationAcknowledged ?? this.isNotificationAcknowledged,
      hasAlarm: hasAlarm ?? this.hasAlarm,
      isAlarmPersistent: isAlarmPersistent ?? this.isAlarmPersistent,
      alarmTime: alarmTime ?? this.alarmTime,
      isAlarmAcknowledged: isAlarmAcknowledged ?? this.isAlarmAcknowledged,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      maxOccurrences: maxOccurrences ?? this.maxOccurrences,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
    );
  }

  /// Generate the next occurrence of a recurring event
  Event? generateNextOccurrence() {
    if (!isRecurring) return null;
    if (maxOccurrences != null && occurrenceCount >= maxOccurrences!) return null;
    if (recurrenceEndDate != null && DateTime.now().isAfter(recurrenceEndDate!)) {
      return null;
    }

    DateTime calculateNextDate(DateTime from) {
      switch (recurrenceType) {
        case RecurrenceType.daily:
          return from.add(Duration(days: recurrenceInterval));
        case RecurrenceType.weekly:
          return from.add(Duration(days: 7 * recurrenceInterval));
        case RecurrenceType.monthly:
          return DateTime(from.year, from.month + recurrenceInterval, from.day, from.hour, from.minute);
        case RecurrenceType.yearly:
          return DateTime(from.year + recurrenceInterval, from.month, from.day, from.hour, from.minute);
        case RecurrenceType.none:
          return from;
      }
    }

    final nextNotificationTime = notificationTime != null
        ? calculateNextDate(notificationTime!)
        : null;
    
    final nextAlarmTime = alarmTime != null
        ? calculateNextDate(alarmTime!)
        : null;

    // Check if next occurrence is beyond end date
    if (recurrenceEndDate != null) {
      final checkTime = nextAlarmTime ?? nextNotificationTime;
      if (checkTime != null && checkTime.isAfter(recurrenceEndDate!)) {
        return null;
      }
    }

    return copyWith(
      id: const Uuid().v4(),
      notificationTime: nextNotificationTime,
      alarmTime: nextAlarmTime,
      isNotificationAcknowledged: false,
      isAlarmAcknowledged: false,
      occurrenceCount: occurrenceCount + 1,
      createdAt: DateTime.now(),
    );
  }
}
