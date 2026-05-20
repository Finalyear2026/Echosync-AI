import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/event.dart';
import '../models/event_filter.dart';

class EventDatabaseService {
  static final EventDatabaseService _instance = EventDatabaseService._internal();
  factory EventDatabaseService() => _instance;
  EventDatabaseService._internal();

  Database? _database;

  static const String _databaseName = 'events.db';
  static const int _databaseVersion = 1;
  static const String _tableName = 'events';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path = join(await getDatabasesPath(), _databaseName);
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        has_notification INTEGER NOT NULL DEFAULT 1,
        is_notification_persistent INTEGER NOT NULL DEFAULT 1,
        notification_time INTEGER,
        is_notification_acknowledged INTEGER NOT NULL DEFAULT 0,
        has_alarm INTEGER NOT NULL DEFAULT 1,
        is_alarm_persistent INTEGER NOT NULL DEFAULT 1,
        alarm_time INTEGER,
        is_alarm_acknowledged INTEGER NOT NULL DEFAULT 0,
        recurrence_type TEXT DEFAULT 'none',
        recurrence_interval INTEGER DEFAULT 1,
        recurrence_end_date INTEGER,
        max_occurrences INTEGER,
        occurrence_count INTEGER DEFAULT 0
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_events_enabled ON $_tableName(is_enabled)');
    await db.execute('CREATE INDEX idx_events_notification_time ON $_tableName(notification_time)');
    await db.execute('CREATE INDEX idx_events_alarm_time ON $_tableName(alarm_time)');
    await db.execute('CREATE INDEX idx_events_created_at ON $_tableName(created_at)');
    await db.execute('CREATE INDEX idx_events_recurrence_type ON $_tableName(recurrence_type)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
  }

  // CRUD Operations

  Future<String> createEvent(Event event) async {
    final Database db = await database;
    await db.insert(
      _tableName,
      event.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return event.id;
  }

  Future<Event?> getEvent(String id) async {
    final Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return Event.fromJson(maps.first);
    }
    return null;
  }

  Future<List<Event>> getAllEvents({EventFilter? filter}) async {
    final Database db = await database;
    
    String? whereClause;
    List<dynamic>? whereArgs;
    String? orderBy;

    if (filter != null) {
      final conditions = <String>[];
      final args = <dynamic>[];

      // Search query (title or description)
      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        conditions.add('(title LIKE ? OR description LIKE ?)');
        args.add('%${filter.searchQuery}%');
        args.add('%${filter.searchQuery}%');
      }

      // Date range
      if (filter.startDate != null) {
        conditions.add('(notification_time >= ? OR alarm_time >= ?)');
        final startMs = filter.startDate!.millisecondsSinceEpoch;
        args.add(startMs);
        args.add(startMs);
      }

      if (filter.endDate != null) {
        conditions.add('(notification_time <= ? OR alarm_time <= ?)');
        final endMs = filter.endDate!.millisecondsSinceEpoch;
        args.add(endMs);
        args.add(endMs);
      }

      // Status filters
      if (filter.isEnabled != null) {
        conditions.add('is_enabled = ?');
        args.add(filter.isEnabled! ? 1 : 0);
      }

      if (filter.isAcknowledged != null) {
        conditions.add('(is_notification_acknowledged = ? AND is_alarm_acknowledged = ?)');
        args.add(filter.isAcknowledged! ? 1 : 0);
        args.add(filter.isAcknowledged! ? 1 : 0);
      }

      // Has notification/alarm
      if (filter.hasNotification != null) {
        conditions.add('has_notification = ?');
        args.add(filter.hasNotification! ? 1 : 0);
      }

      if (filter.hasAlarm != null) {
        conditions.add('has_alarm = ?');
        args.add(filter.hasAlarm! ? 1 : 0);
      }

      // Persistence
      if (filter.isNotificationPersistent != null) {
        conditions.add('is_notification_persistent = ?');
        args.add(filter.isNotificationPersistent! ? 1 : 0);
      }

      if (filter.isAlarmPersistent != null) {
        conditions.add('is_alarm_persistent = ?');
        args.add(filter.isAlarmPersistent! ? 1 : 0);
      }

      // Recurrence
      if (filter.isRecurring != null) {
        if (filter.isRecurring!) {
          conditions.add("recurrence_type != 'none'");
        } else {
          conditions.add("recurrence_type = 'none'");
        }
      }

      if (filter.recurrenceType != null) {
        conditions.add('recurrence_type = ?');
        args.add(filter.recurrenceType!.name);
      }

      if (conditions.isNotEmpty) {
        whereClause = conditions.join(' AND ');
        whereArgs = args;
      }

      // Sorting
      String sortColumn;
      switch (filter.sortField) {
        case SortField.eventDate:
          sortColumn = 'COALESCE(alarm_time, notification_time)';
          break;
        case SortField.createdDate:
          sortColumn = 'created_at';
          break;
        case SortField.title:
          sortColumn = 'title';
          break;
      }
      final sortDirection = filter.sortOrder == SortOrder.ascending ? 'ASC' : 'DESC';
      orderBy = '$sortColumn $sortDirection';
    } else {
      // Default sort by event date ascending
      orderBy = 'COALESCE(alarm_time, notification_time) ASC';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );

    return List.generate(maps.length, (i) => Event.fromJson(maps[i]));
  }

  Future<List<Event>> getUpcomingEvents() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'is_enabled = 1 AND ((has_notification = 1 AND notification_time > ? AND is_notification_acknowledged = 0) OR (has_alarm = 1 AND alarm_time > ? AND is_alarm_acknowledged = 0))',
      whereArgs: [now, now],
      orderBy: 'COALESCE(alarm_time, notification_time) ASC',
    );

    return List.generate(maps.length, (i) => Event.fromJson(maps[i]));
  }

  Future<List<Event>> getPendingNotifications() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'is_enabled = 1 AND has_notification = 1 AND notification_time <= ? AND is_notification_acknowledged = 0',
      whereArgs: [now],
      orderBy: 'notification_time ASC',
    );

    return List.generate(maps.length, (i) => Event.fromJson(maps[i]));
  }

  Future<List<Event>> getPendingAlarms() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'is_enabled = 1 AND has_alarm = 1 AND alarm_time <= ? AND is_alarm_acknowledged = 0',
      whereArgs: [now],
      orderBy: 'alarm_time ASC',
    );

    return List.generate(maps.length, (i) => Event.fromJson(maps[i]));
  }

  Future<int> updateEvent(Event event) async {
    final Database db = await database;
    event.updatedAt = DateTime.now();
    
    return await db.update(
      _tableName,
      event.toJson(),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<int> deleteEvent(String id) async {
    final Database db = await database;
    return await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> toggleEventEnabled(String id, bool isEnabled) async {
    final Database db = await database;
    return await db.update(
      _tableName,
      {
        'is_enabled': isEnabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> acknowledgeEvent(String id) async {
    final Database db = await database;
    return await db.update(
      _tableName,
      {
        'is_notification_acknowledged': 1,
        'is_alarm_acknowledged': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getEventCount() async {
    final Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getUpcomingEventCount() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM $_tableName 
      WHERE is_enabled = 1 
      AND (
        (has_notification = 1 AND notification_time > ? AND is_notification_acknowledged = 0)
        OR 
        (has_alarm = 1 AND alarm_time > ? AND is_alarm_acknowledged = 0)
      )
    ''', [now, now]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
