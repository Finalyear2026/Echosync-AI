import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../theme/app_theme.dart';

class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Function(bool)? onToggleEnabled;

  const EventCard({
    super.key,
    required this.event,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Not set';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (eventDay == today) {
      return 'Today ${DateFormat('HH:mm').format(dateTime)}';
    } else if (eventDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow ${DateFormat('HH:mm').format(dateTime)}';
    } else {
      return DateFormat('MMM dd, HH:mm').format(dateTime);
    }
  }

  Color _getStatusColor() {
    if (!event.isEnabled) return AppTheme.textMuted;
    if (event.isExpired) return AppTheme.error;
    if (event.isUpcoming) return AppTheme.accentCyan;
    return AppTheme.success;
  }

  IconData _getStatusIcon() {
    if (!event.isEnabled) return Icons.pause_circle_outline;
    if (event.isExpired) return Icons.check_circle_outline;
    if (event.isUpcoming) return Icons.access_time;
    return Icons.event_available;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    
    return Opacity(
      opacity: event.isEnabled ? 1.0 : 0.6,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: event.isEnabled 
                  ? AppTheme.accentCyan.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with title and status
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getStatusIcon(),
                        size: 16,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: TextStyle(
                              color: event.isEnabled 
                                  ? AppTheme.textPrimary 
                                  : AppTheme.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (event.description != null && event.description!.isNotEmpty)
                            Text(
                              event.description!,
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    // Enable/Disable toggle
                    if (onToggleEnabled != null)
                      Switch(
                        value: event.isEnabled,
                        onChanged: (value) => onToggleEnabled!(value),
                        activeColor: AppTheme.accentCyan,
                        activeTrackColor: AppTheme.accentCyan.withOpacity(0.3),
                        inactiveThumbColor: AppTheme.textMuted,
                        inactiveTrackColor: AppTheme.textMuted.withOpacity(0.3),
                      ),
                  ],
                ),
              ),
              
              // Event timing chips
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (event.hasNotification)
                      _buildChip(
                        icon: Icons.notifications_outlined,
                        label: _formatDateTime(event.notificationTime),
                        color: event.isNotificationPersistent 
                            ? AppTheme.primaryPurple 
                            : AppTheme.accentCyan,
                        isPersistent: event.isNotificationPersistent,
                      ),
                    if (event.hasAlarm)
                      _buildChip(
                        icon: Icons.alarm_outlined,
                        label: _formatDateTime(event.alarmTime),
                        color: event.isAlarmPersistent 
                            ? AppTheme.warning 
                            : AppTheme.success,
                        isPersistent: event.isAlarmPersistent,
                      ),
                    if (event.isRecurring)
                      _buildChip(
                        icon: Icons.repeat,
                        label: event.recurrenceType.name.toUpperCase(),
                        color: AppTheme.accentCyan,
                      ),
                  ],
                ),
              ),
              
              // Action buttons
              if (onEdit != null || onDelete != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onEdit != null)
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accentCyan,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      if (onDelete != null)
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Delete'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
    bool isPersistent = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          if (isPersistent) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.lock_outline,
              size: 10,
              color: color.withOpacity(0.7),
            ),
          ],
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
