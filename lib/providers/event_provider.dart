import 'package:flutter/material.dart';
import '../models/event.dart';
import '../models/event_filter.dart';
import '../services/event_database_service.dart';
import '../services/notification_service.dart';
import '../services/alarm_service.dart';
import '../services/logging_service.dart';

class EventProvider extends ChangeNotifier {
  final EventDatabaseService _db = EventDatabaseService();
  final NotificationService _notificationService = NotificationService();
  final AlarmService _alarmService = AlarmService();

  List<Event> _events = [];
  EventFilter _currentFilter = EventFilter();
  bool _isLoading = false;
  String? _error;
  int _upcomingEventCount = 0;

  // Getters
  List<Event> get events => List.unmodifiable(_events);
  EventFilter get currentFilter => _currentFilter;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get upcomingEventCount => _upcomingEventCount;
  bool get hasActiveFilter => _currentFilter.isActive;
  int get activeFilterCount => _currentFilter.activeFilterCount;

  /// Initialize provider and load initial data
  Future<void> initialize() async {
    await loadEvents();
    await _updateUpcomingCount();
  }

  /// Load events with current filter
  Future<void> loadEvents() async {
    _setLoading(true);
    _clearError();

    try {
      _events = await _db.getAllEvents(filter: _currentFilter.isActive ? _currentFilter : null);
      _setLoading(false);
    } catch (e) {
      _setError('Failed to load events: $e');
      _setLoading(false);
    }
  }

  /// Create a new event
  Future<void> createEvent(Event event) async {
    _setLoading(true);
    _clearError();

    try {
      // Validate alarm time > notification time
      if (event.hasAlarm && event.hasNotification && 
          event.alarmTime != null && event.notificationTime != null) {
        if (event.alarmTime!.isBefore(event.notificationTime!)) {
          throw Exception('Alarm time must be after notification time');
        }
      }

      // Save to database
      await _db.createEvent(event);

      // Schedule notification if enabled
      if (event.hasNotification && event.notificationTime != null && event.isEnabled) {
        await _notificationService.scheduleNotification(event);
      }

      // Schedule alarm if enabled
      if (event.hasAlarm && event.alarmTime != null && event.isEnabled) {
        await _alarmService.scheduleAlarm(event);
      }

      LoggingService().log(
        'Event created',
        category: 'EVENTS',
        details: {
          'event_id': event.id,
          'title': event.title,
          'has_notification': event.hasNotification,
          'has_alarm': event.hasAlarm,
        },
      );

      await loadEvents();
      await _updateUpcomingCount();
    } catch (e) {
      _setError('Failed to create event: $e');
      _setLoading(false);
    }
  }

  /// Update an existing event
  Future<void> updateEvent(Event event) async {
    _setLoading(true);
    _clearError();

    try {
      // Validate alarm time > notification time
      if (event.hasAlarm && event.hasNotification && 
          event.alarmTime != null && event.notificationTime != null) {
        if (event.alarmTime!.isBefore(event.notificationTime!)) {
          throw Exception('Alarm time must be after notification time');
        }
      }

      // Cancel existing notifications and alarms
      await _notificationService.cancelNotification(event.id);
      await _alarmService.cancelAlarm(event.id);

      // Update in database
      await _db.updateEvent(event);

      // Reschedule if enabled
      if (event.isEnabled) {
        if (event.hasNotification && event.notificationTime != null && !event.isNotificationAcknowledged) {
          await _notificationService.scheduleNotification(event);
        }
        if (event.hasAlarm && event.alarmTime != null && !event.isAlarmAcknowledged) {
          await _alarmService.scheduleAlarm(event);
        }
      }

      LoggingService().log(
        'Event updated',
        category: 'EVENTS',
        details: {'event_id': event.id, 'title': event.title},
      );

      await loadEvents();
      await _updateUpcomingCount();
    } catch (e) {
      _setError('Failed to update event: $e');
      _setLoading(false);
    }
  }

  /// Delete an event
  Future<void> deleteEvent(String id) async {
    _setLoading(true);
    _clearError();

    try {
      // Cancel notifications and alarms
      await _notificationService.cancelNotification(id);
      await _alarmService.cancelAlarm(id);

      // Delete from database
      await _db.deleteEvent(id);

      LoggingService().log(
        'Event deleted',
        category: 'EVENTS',
        details: {'event_id': id},
      );

      await loadEvents();
      await _updateUpcomingCount();
    } catch (e) {
      _setError('Failed to delete event: $e');
      _setLoading(false);
    }
  }

  /// Toggle event enabled status
  Future<void> toggleEventEnabled(String id) async {
    try {
      final event = await _db.getEvent(id);
      if (event == null) return;

      final newEnabled = !event.isEnabled;
      await _db.toggleEventEnabled(id, newEnabled);

      if (newEnabled) {
        // Re-enable notifications and alarms
        if (event.hasNotification && event.notificationTime != null && !event.isNotificationAcknowledged) {
          await _notificationService.scheduleNotification(event);
        }
        if (event.hasAlarm && event.alarmTime != null && !event.isAlarmAcknowledged) {
          await _alarmService.scheduleAlarm(event);
        }
      } else {
        // Cancel notifications and alarms
        await _notificationService.cancelNotification(id);
        await _alarmService.cancelAlarm(id);
      }

      LoggingService().log(
        'Event ${newEnabled ? 'enabled' : 'disabled'}',
        category: 'EVENTS',
        details: {'event_id': id},
      );

      await loadEvents();
      await _updateUpcomingCount();
    } catch (e) {
      _setError('Failed to toggle event: $e');
      notifyListeners();
    }
  }

  /// Acknowledge an event (triggered from notification)
  Future<void> acknowledgeEvent(String id) async {
    try {
      final event = await _db.getEvent(id);
      if (event == null) return;

      // Cancel alarm if ringing
      await _alarmService.cancelAlarm(id);

      // Update database
      await _db.acknowledgeEvent(id);

      // Cancel notification
      await _notificationService.cancelNotification(id);

      // If recurring, generate next occurrence
      if (event.isRecurring) {
        final nextEvent = event.generateNextOccurrence();
        if (nextEvent != null) {
          await _db.createEvent(nextEvent);
          if (nextEvent.hasNotification && nextEvent.notificationTime != null) {
            await _notificationService.scheduleNotification(nextEvent);
          }
          if (nextEvent.hasAlarm && nextEvent.alarmTime != null) {
            await _alarmService.scheduleAlarm(nextEvent);
          }
          LoggingService().log(
            'Next recurring event created',
            category: 'EVENTS',
            details: {'event_id': nextEvent.id, 'parent_id': id},
          );
        }
      }

      LoggingService().log(
        'Event acknowledged',
        category: 'EVENTS',
        details: {'event_id': id},
      );

      await loadEvents();
      await _updateUpcomingCount();
    } catch (e) {
      _setError('Failed to acknowledge event: $e');
      notifyListeners();
    }
  }

  /// Set filter and reload events
  Future<void> setFilter(EventFilter filter) async {
    _currentFilter = filter;
    await loadEvents();
  }

  /// Update specific filter field
  Future<void> updateFilter({
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
  }) async {
    _currentFilter = _currentFilter.copyWith(
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
      isEnabled: isEnabled,
      isAcknowledged: isAcknowledged,
      isExpired: isExpired,
      hasNotification: hasNotification,
      hasAlarm: hasAlarm,
      isNotificationPersistent: isNotificationPersistent,
      isAlarmPersistent: isAlarmPersistent,
      isRecurring: isRecurring,
      recurrenceType: recurrenceType,
      sortField: sortField,
      sortOrder: sortOrder,
    );
    await loadEvents();
  }

  /// Clear specific filter field
  Future<void> clearFilterField({
    bool searchQuery = false,
    bool startDate = false,
    bool endDate = false,
    bool isEnabled = false,
    bool isAcknowledged = false,
    bool isExpired = false,
    bool hasNotification = false,
    bool hasAlarm = false,
    bool isNotificationPersistent = false,
    bool isAlarmPersistent = false,
    bool isRecurring = false,
    bool recurrenceType = false,
  }) async {
    _currentFilter = _currentFilter.copyWith(
      clearSearchQuery: searchQuery,
      clearStartDate: startDate,
      clearEndDate: endDate,
      clearIsEnabled: isEnabled,
      clearIsAcknowledged: isAcknowledged,
      clearIsExpired: isExpired,
      clearHasNotification: hasNotification,
      clearHasAlarm: hasAlarm,
      clearIsNotificationPersistent: isNotificationPersistent,
      clearIsAlarmPersistent: isAlarmPersistent,
      clearIsRecurring: isRecurring,
      clearRecurrenceType: recurrenceType,
    );
    await loadEvents();
  }

  /// Clear all filters
  Future<void> clearAllFilters() async {
    _currentFilter = EventFilter();
    await loadEvents();
  }

  /// Refresh upcoming event count
  Future<void> _updateUpcomingCount() async {
    try {
      _upcomingEventCount = await _db.getUpcomingEventCount();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update upcoming count: $e');
    }
  }

  /// Get event by ID
  Future<Event?> getEvent(String id) async {
    return await _db.getEvent(id);
  }

  /// Reschedule all pending notifications and alarms (call on app startup)
  Future<void> rescheduleAllPending() async {
    try {
      await _alarmService.rescheduleAllAlarms();
      LoggingService().log(
        'Rescheduled all pending events',
        category: 'EVENTS',
      );
    } catch (e) {
      LoggingService().log(
        'Failed to reschedule pending events',
        category: 'EVENTS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  // Private helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    _events = [];
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
