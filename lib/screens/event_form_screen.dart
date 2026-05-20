import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event.dart';
import '../providers/event_provider.dart';
import '../theme/app_theme.dart';

class EventFormScreen extends StatefulWidget {
  final Event? event;

  const EventFormScreen({super.key, this.event});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  
  late bool _hasNotification;
  late bool _isNotificationPersistent;
  DateTime? _notificationTime;
  
  late bool _hasAlarm;
  late bool _isAlarmPersistent;
  DateTime? _alarmTime;
  
  late RecurrenceType _recurrenceType;
  late int _recurrenceInterval;
  DateTime? _recurrenceEndDate;
  int? _maxOccurrences;

  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    
    _titleController = TextEditingController(text: event?.title ?? 'Blank Notifier');
    _descriptionController = TextEditingController(text: event?.description ?? '');
    
    _hasNotification = event?.hasNotification ?? true;
    _isNotificationPersistent = event?.isNotificationPersistent ?? true;
    _notificationTime = event?.notificationTime ?? _getDefaultDateTime();
    
    _hasAlarm = event?.hasAlarm ?? true;
    _isAlarmPersistent = event?.isAlarmPersistent ?? true;
    _alarmTime = event?.alarmTime ?? _getDefaultAlarmTime();
    
    _recurrenceType = event?.recurrenceType ?? RecurrenceType.none;
    _recurrenceInterval = event?.recurrenceInterval ?? 1;
    _recurrenceEndDate = event?.recurrenceEndDate;
    _maxOccurrences = event?.maxOccurrences;
  }

  DateTime _getDefaultDateTime() {
    final now = DateTime.now();
    return now.add(const Duration(minutes: 30));
  }

  DateTime _getDefaultAlarmTime() {
    final now = DateTime.now();
    return now.add(const Duration(minutes: 45));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(BuildContext context, DateTime? initialDate, Function(DateTime) onPicked) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.accentCyan,
              surface: AppTheme.surfaceDark,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (date != null && context.mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate ?? now),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppTheme.accentCyan,
                surface: AppTheme.surfaceDark,
              ),
            ),
            child: child!,
          );
        },
      );
      
      if (time != null) {
        onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      }
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Not set';
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'''
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validate alarm time > notification time
    if (_hasAlarm && _hasNotification && _alarmTime != null && _notificationTime != null) {
      if (_alarmTime!.isBefore(_notificationTime!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alarm time must be after notification time'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    final event = Event(
      id: widget.event?.id,
      title: _titleController.text.isEmpty ? 'Blank Notifier' : _titleController.text,
      description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
      hasNotification: _hasNotification,
      isNotificationPersistent: _isNotificationPersistent,
      notificationTime: _hasNotification ? _notificationTime : null,
      hasAlarm: _hasAlarm,
      isAlarmPersistent: _isAlarmPersistent,
      alarmTime: _hasAlarm ? _alarmTime : null,
      recurrenceType: _recurrenceType,
      recurrenceInterval: _recurrenceInterval,
      recurrenceEndDate: _recurrenceEndDate,
      maxOccurrences: _maxOccurrences,
      createdAt: widget.event?.createdAt,
      updatedAt: DateTime.now(),
    );

    final provider = context.read<EventProvider>();
    
    try {
      if (widget.event == null) {
        await provider.createEvent(event);
      } else {
        await provider.updateEvent(event);
      }
      
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (context.mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          color: AppTheme.textSecondary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        isEditing ? 'Edit Event' : 'New Event',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_isSaving)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentCyan,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _saveEvent,
                          icon: const Icon(Icons.check),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentCyan,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Form content
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Basic Info Section
                          _buildSectionTitle('Event Details'),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _titleController,
                            label: 'Title',
                            hint: 'Blank Notifier',
                            icon: Icons.title,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _descriptionController,
                            label: 'Description (optional)',
                            hint: 'Add details about this event...',
                            icon: Icons.description,
                            maxLines: 3,
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Notification Section
                          _buildSectionHeader(
                            'Notification',
                            Icons.notifications_outlined,
                            _hasNotification,
                            (value) => setState(() => _hasNotification = value),
                          ),
                          if (_hasNotification) ...[
                            const SizedBox(height: 12),
                            _buildDateTimePicker(
                              label: 'Notification Time',
                              dateTime: _notificationTime,
                              onTap: () => _pickDateTime(context, _notificationTime, (dt) {
                                setState(() => _notificationTime = dt);
                              }),
                            ),
                            const SizedBox(height: 12),
                            _buildToggleRow(
                              'Persistent Notification',
                              'Cannot be swiped away',
                              _isNotificationPersistent,
                              (value) => setState(() => _isNotificationPersistent = value),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          
                          // Alarm Section
                          _buildSectionHeader(
                            'Alarm',
                            Icons.alarm_outlined,
                            _hasAlarm,
                            (value) => setState(() => _hasAlarm = value),
                          ),
                          if (_hasAlarm) ...[
                            const SizedBox(height: 12),
                            _buildDateTimePicker(
                              label: 'Alarm Time',
                              dateTime: _alarmTime,
                              onTap: () => _pickDateTime(context, _alarmTime, (dt) {
                                setState(() => _alarmTime = dt);
                              }),
                            ),
                            const SizedBox(height: 12),
                            _buildToggleRow(
                              'Persistent Alarm',
                              'Rings even in silent/airplane mode',
                              _isAlarmPersistent,
                              (value) => setState(() => _isAlarmPersistent = value),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          
                          // Recurrence Section
                          _buildSectionTitle('Recurrence'),
                          const SizedBox(height: 12),
                          _buildRecurrenceSelector(),
                          
                          if (_recurrenceType != RecurrenceType.none) ...[
                            const SizedBox(height: 12),
                            _buildNumberField(
                              label: 'Repeat every',
                              value: _recurrenceInterval,
                              onChanged: (value) => setState(() => _recurrenceInterval = value),
                              suffix: _getRecurrenceSuffix(),
                            ),
                            const SizedBox(height: 12),
                            _buildDateTimePicker(
                              label: 'End date (optional)',
                              dateTime: _recurrenceEndDate,
                              onTap: () => _pickDateTime(context, _recurrenceEndDate, (dt) {
                                setState(() => _recurrenceEndDate = dt);
                              }),
                              allowClear: true,
                              onClear: () => setState(() => _recurrenceEndDate = null),
                            ),
                            const SizedBox(height: 12),
                            _buildNumberField(
                              label: 'Max occurrences (optional)',
                              value: _maxOccurrences,
                              onChanged: (value) => setState(() => _maxOccurrences = value),
                              allowNull: true,
                            ),
                          ],
                          
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: AppTheme.textMuted.withOpacity(0.7),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value 
              ? AppTheme.accentCyan.withOpacity(0.3) 
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (value ? AppTheme.accentCyan : AppTheme.textMuted).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: value ? AppTheme.accentCyan : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: value ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value ? 'Enabled' : 'Disabled',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.accentCyan,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textMuted),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accentCyan),
        ),
        labelStyle: const TextStyle(color: AppTheme.textMuted),
        hintStyle: TextStyle(color: AppTheme.textMuted.withOpacity(0.5)),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    required DateTime? dateTime,
    required VoidCallback onTap,
    bool allowClear = false,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              color: AppTheme.accentCyan,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDateTime(dateTime),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (allowClear && dateTime != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                color: AppTheme.textMuted,
                onPressed: onClear,
              ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.accentCyan,
          ),
        ],
      ),
    );
  }

  Widget _buildRecurrenceSelector() {
    final types = [
      RecurrenceType.none,
      RecurrenceType.daily,
      RecurrenceType.weekly,
      RecurrenceType.monthly,
      RecurrenceType.yearly,
    ];
    
    final labels = {
      RecurrenceType.none: 'One-time',
      RecurrenceType.daily: 'Daily',
      RecurrenceType.weekly: 'Weekly',
      RecurrenceType.monthly: 'Monthly',
      RecurrenceType.yearly: 'Yearly',
    };
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((type) {
        final isSelected = _recurrenceType == type;
        return ChoiceChip(
          selected: isSelected,
          label: Text(labels[type]!),
          onSelected: (_) => setState(() => _recurrenceType = type),
          selectedColor: AppTheme.accentCyan.withOpacity(0.2),
          labelStyle: TextStyle(
            color: isSelected ? AppTheme.accentCyan : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          backgroundColor: Colors.white.withOpacity(0.05),
          side: isSelected 
              ? BorderSide(color: AppTheme.accentCyan.withOpacity(0.5))
              : BorderSide.none,
        );
      }).toList(),
    );
  }

  Widget _buildNumberField({
    required String label,
    required int? value,
    required Function(int) onChanged,
    String? suffix,
    bool allowNull = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                color: AppTheme.textMuted,
                onPressed: () {
                  if (value != null && value > 1) {
                    onChanged(value - 1);
                  }
                },
              ),
              SizedBox(
                width: 40,
                child: Text(
                  value?.toString() ?? '-',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                color: AppTheme.accentCyan,
                onPressed: () {
                  onChanged((value ?? 0) + 1);
                },
              ),
            ],
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 8),
          Text(
            suffix,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  String _getRecurrenceSuffix() {
    switch (_recurrenceType) {
      case RecurrenceType.daily:
        return 'days';
      case RecurrenceType.weekly:
        return 'weeks';
      case RecurrenceType.monthly:
        return 'months';
      case RecurrenceType.yearly:
        return 'years';
      default:
        return '';
    }
  }
}
