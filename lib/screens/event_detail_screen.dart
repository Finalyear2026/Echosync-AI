import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../providers/event_provider.dart';
import '../theme/app_theme.dart';
import 'event_form_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  final bool showAcknowledge;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.showAcknowledge = false,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Event? _event;
  bool _isLoading = true;
  bool _isAcknowledging = false;

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    final event = await context.read<EventProvider>().getEvent(widget.eventId);
    setState(() {
      _event = event;
      _isLoading = false;
    });
  }

  Future<void> _acknowledge() async {
    setState(() => _isAcknowledging = true);
    
    await context.read<EventProvider>().acknowledgeEvent(widget.eventId);
    
    setState(() => _isAcknowledging = false);
    
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showDeleteConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Delete Event',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: const Text(
            'Are you sure you want to delete this event? This action cannot be undone.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text(
                'Delete',
                style: TextStyle(color: AppTheme.error),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await context.read<EventProvider>().deleteEvent(widget.eventId);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Not set';
    return DateFormat('EEEE, MMMM d, y • HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
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
                _buildAppBar(),
                
                // Content
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.accentCyan,
                          ),
                        )
                      : _event == null
                          ? _buildNotFound()
                          : _buildEventDetails(),
                ),
                
                // Acknowledge button (only when opened from notification)
                if (widget.showAcknowledge && _event != null)
                  _buildAcknowledgeBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppTheme.textSecondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.showAcknowledge ? 'Event Alert' : 'Event Details',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (_event != null && !widget.showAcknowledge) ...[
            // Edit button
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.edit_outlined),
                color: AppTheme.accentCyan,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => EventFormScreen(event: _event),
                    ),
                  ).then((_) => _loadEvent());
                },
              ),
            ),
            const SizedBox(width: 8),
            // Delete button
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                color: AppTheme.error,
                onPressed: _showDeleteConfirmation,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventDetails() {
    final event = _event!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: event.isEnabled
                    ? AppTheme.accentCyan.withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (event.isEnabled ? AppTheme.accentCyan : AppTheme.textMuted).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        event.isEnabled ? Icons.event_available : Icons.event_busy,
                        color: event.isEnabled ? AppTheme.accentCyan : AppTheme.textMuted,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: event.isEnabled ? AppTheme.textPrimary : AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: event.isEnabled ? AppTheme.success : AppTheme.textMuted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                event.isEnabled ? 'Enabled' : 'Disabled',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Enable/Disable toggle (when not from notification)
                    if (!widget.showAcknowledge)
                      Switch(
                        value: event.isEnabled,
                        onChanged: (value) {
                          context.read<EventProvider>().toggleEventEnabled(event.id);
                          setState(() {
                            _event = event.copyWith(isEnabled: value);
                          });
                        },
                        activeColor: AppTheme.accentCyan,
                      ),
                  ],
                ),
                
                if (event.description != null && event.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  Text(
                    event.description!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Notification section
          if (event.hasNotification)
            _buildSection(
              title: 'Notification',
              icon: Icons.notifications_outlined,
              color: AppTheme.accentCyan,
              items: [
                _buildInfoRow('Time', _formatDateTime(event.notificationTime)),
                _buildInfoRow('Persistent', event.isNotificationPersistent ? 'Yes' : 'No'),
                _buildInfoRow('Status', event.isNotificationAcknowledged ? 'Acknowledged' : 'Pending'),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Alarm section
          if (event.hasAlarm)
            _buildSection(
              title: 'Alarm',
              icon: Icons.alarm_outlined,
              color: event.isAlarmPersistent ? AppTheme.warning : AppTheme.success,
              items: [
                _buildInfoRow('Time', _formatDateTime(event.alarmTime)),
                _buildInfoRow('Persistent', event.isAlarmPersistent ? 'Yes' : 'No'),
                _buildInfoRow('Status', event.isAlarmAcknowledged ? 'Acknowledged' : 'Pending'),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Recurrence section
          if (event.isRecurring)
            _buildSection(
              title: 'Recurrence',
              icon: Icons.repeat,
              color: AppTheme.primaryPurple,
              items: [
                _buildInfoRow('Type', event.recurrenceType.name.capitalize()),
                _buildInfoRow('Interval', 'Every ${event.recurrenceInterval} ${event.recurrenceType.name}'),
                if (event.recurrenceEndDate != null)
                  _buildInfoRow('End Date', _formatDateTime(event.recurrenceEndDate)),
                if (event.maxOccurrences != null)
                  _buildInfoRow('Max Occurrences', '${event.maxOccurrences}'),
                _buildInfoRow('Current Count', '${event.occurrenceCount}'),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Metadata section
          _buildSection(
            title: 'Metadata',
            icon: Icons.info_outline,
            color: AppTheme.textMuted,
            items: [
              _buildInfoRow('Created', _formatDateTime(event.createdAt)),
              _buildInfoRow('Last Updated', _formatDateTime(event.updatedAt)),
              _buildInfoRow('Event ID', event.id.substring(0, 8) + '...'),
            ],
          ),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 64,
            color: AppTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Event not found',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This event may have been deleted',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcknowledgeBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isAcknowledging ? null : _acknowledge,
            icon: _isAcknowledging
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_isAcknowledging ? 'Acknowledging...' : 'Acknowledge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
