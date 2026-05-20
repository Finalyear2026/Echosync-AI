import 'event.dart';

enum SortField { eventDate, createdDate, title }
enum SortOrder { ascending, descending }

class EventFilter {
  String? searchQuery;
  DateTime? startDate;
  DateTime? endDate;
  bool? isEnabled;
  bool? isAcknowledged;
  bool? isExpired;
  bool? hasNotification;
  bool? hasAlarm;
  bool? isNotificationPersistent;
  bool? isAlarmPersistent;
  bool? isRecurring;
  RecurrenceType? recurrenceType;
  SortField sortField;
  SortOrder sortOrder;

  EventFilter({
    this.searchQuery,
    this.startDate,
    this.endDate,
    this.isEnabled,
    this.isAcknowledged,
    this.isExpired,
    this.hasNotification,
    this.hasAlarm,
    this.isNotificationPersistent,
    this.isAlarmPersistent,
    this.isRecurring,
    this.recurrenceType,
    this.sortField = SortField.eventDate,
    this.sortOrder = SortOrder.ascending,
  });

  EventFilter copyWith({
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    bool? isEnabled,
    bool? isAcknowledged,
    bool? isExpired,
    bool? hasNotification,
    bool? hasAlarm,
    bool? isNotificationPersistent,
    bool? isAlarmPersistent,
    bool? isRecurring,
    RecurrenceType? recurrenceType,
    SortField? sortField,
    SortOrder? sortOrder,
    bool clearSearchQuery = false,
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearIsEnabled = false,
    bool clearIsAcknowledged = false,
    bool clearIsExpired = false,
    bool clearHasNotification = false,
    bool clearHasAlarm = false,
    bool clearIsNotificationPersistent = false,
    bool clearIsAlarmPersistent = false,
    bool clearIsRecurring = false,
    bool clearRecurrenceType = false,
  }) {
    return EventFilter(
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      isEnabled: clearIsEnabled ? null : (isEnabled ?? this.isEnabled),
      isAcknowledged: clearIsAcknowledged ? null : (isAcknowledged ?? this.isAcknowledged),
      isExpired: clearIsExpired ? null : (isExpired ?? this.isExpired),
      hasNotification: clearHasNotification ? null : (hasNotification ?? this.hasNotification),
      hasAlarm: clearHasAlarm ? null : (hasAlarm ?? this.hasAlarm),
      isNotificationPersistent: clearIsNotificationPersistent
          ? null
          : (isNotificationPersistent ?? this.isNotificationPersistent),
      isAlarmPersistent: clearIsAlarmPersistent ? null : (isAlarmPersistent ?? this.isAlarmPersistent),
      isRecurring: clearIsRecurring ? null : (isRecurring ?? this.isRecurring),
      recurrenceType: clearRecurrenceType ? null : (recurrenceType ?? this.recurrenceType),
      sortField: sortField ?? this.sortField,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  bool get isActive {
    return searchQuery != null ||
        startDate != null ||
        endDate != null ||
        isEnabled != null ||
        isAcknowledged != null ||
        isExpired != null ||
        hasNotification != null ||
        hasAlarm != null ||
        isNotificationPersistent != null ||
        isAlarmPersistent != null ||
        isRecurring != null ||
        recurrenceType != null;
  }

  int get activeFilterCount {
    int count = 0;
    if (searchQuery != null) count++;
    if (startDate != null) count++;
    if (endDate != null) count++;
    if (isEnabled != null) count++;
    if (isAcknowledged != null) count++;
    if (isExpired != null) count++;
    if (hasNotification != null) count++;
    if (hasAlarm != null) count++;
    if (isNotificationPersistent != null) count++;
    if (isAlarmPersistent != null) count++;
    if (isRecurring != null) count++;
    if (recurrenceType != null) count++;
    return count;
  }

  void clear() {
    searchQuery = null;
    startDate = null;
    endDate = null;
    isEnabled = null;
    isAcknowledged = null;
    isExpired = null;
    hasNotification = null;
    hasAlarm = null;
    isNotificationPersistent = null;
    isAlarmPersistent = null;
    isRecurring = null;
    recurrenceType = null;
    sortField = SortField.eventDate;
    sortOrder = SortOrder.ascending;
  }
}
