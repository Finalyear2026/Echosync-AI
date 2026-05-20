import 'package:flutter/material.dart';
import '../models/event_filter.dart';
import '../models/event.dart';
import '../theme/app_theme.dart';

class EventFilterPanel extends StatefulWidget {
  final EventFilter filter;
  final Function(EventFilter) onFilterChanged;
  final VoidCallback? onClearFilters;

  const EventFilterPanel({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    this.onClearFilters,
  });

  @override
  State<EventFilterPanel> createState() => _EventFilterPanelState();
}

class _EventFilterPanelState extends State<EventFilterPanel> {
  late TextEditingController _searchController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filter.searchQuery ?? '');
  }

  @override
  void didUpdateWidget(EventFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter.searchQuery != widget.filter.searchQuery) {
      _searchController.text = widget.filter.searchQuery ?? '';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilter(EventFilter newFilter) {
    widget.onFilterChanged(newFilter);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field and expand button
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _updateFilter(widget.filter.copyWith(
                        searchQuery: value.isEmpty ? null : value,
                      ));
                    },
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search events...',
                      hintStyle: TextStyle(
                        color: AppTheme.textMuted.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppTheme.textMuted,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              color: AppTheme.textMuted,
                              onPressed: () {
                                _searchController.clear();
                                _updateFilter(widget.filter.copyWith(
                                  clearSearchQuery: true,
                                ));
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Filter count badge
                if (widget.filter.activeFilterCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.filter.activeFilterCount}',
                      style: const TextStyle(
                        color: AppTheme.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // Expand/collapse button
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  icon: AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Expanded filter options
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedFilters(),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),
          
          // Sort options
          _buildSectionTitle('Sort By'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSortChip('Event Date', SortField.eventDate),
              _buildSortChip('Created Date', SortField.createdDate),
              _buildSortChip('Title', SortField.title),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildSortOrderChip('Ascending', SortOrder.ascending),
              const SizedBox(width: 8),
              _buildSortOrderChip('Descending', SortOrder.descending),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Status filters
          _buildSectionTitle('Status'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToggleChip('Enabled', widget.filter.isEnabled == true, () {
                _updateFilter(widget.filter.copyWith(
                  isEnabled: widget.filter.isEnabled == true ? null : true,
                  clearIsEnabled: widget.filter.isEnabled == true,
                ));
              }),
              _buildToggleChip('Disabled', widget.filter.isEnabled == false, () {
                _updateFilter(widget.filter.copyWith(
                  isEnabled: widget.filter.isEnabled == false ? null : false,
                  clearIsEnabled: widget.filter.isEnabled == false,
                ));
              }),
              _buildToggleChip('Acknowledged', widget.filter.isAcknowledged == true, () {
                _updateFilter(widget.filter.copyWith(
                  isAcknowledged: widget.filter.isAcknowledged == true ? null : true,
                  clearIsAcknowledged: widget.filter.isAcknowledged == true,
                ));
              }),
              _buildToggleChip('Pending', widget.filter.isAcknowledged == false, () {
                _updateFilter(widget.filter.copyWith(
                  isAcknowledged: widget.filter.isAcknowledged == false ? null : false,
                  clearIsAcknowledged: widget.filter.isAcknowledged == false,
                ));
              }),
              _buildToggleChip('Expired', widget.filter.isExpired == true, () {
                _updateFilter(widget.filter.copyWith(
                  isExpired: widget.filter.isExpired == true ? null : true,
                  clearIsExpired: widget.filter.isExpired == true,
                ));
              }),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Notification/Alarm filters
          _buildSectionTitle('Notification & Alarm'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToggleChip('Has Notification', widget.filter.hasNotification == true, () {
                _updateFilter(widget.filter.copyWith(
                  hasNotification: widget.filter.hasNotification == true ? null : true,
                  clearHasNotification: widget.filter.hasNotification == true,
                ));
              }),
              _buildToggleChip('Has Alarm', widget.filter.hasAlarm == true, () {
                _updateFilter(widget.filter.copyWith(
                  hasAlarm: widget.filter.hasAlarm == true ? null : true,
                  clearHasAlarm: widget.filter.hasAlarm == true,
                ));
              }),
              _buildToggleChip('Persistent Notification', widget.filter.isNotificationPersistent == true, () {
                _updateFilter(widget.filter.copyWith(
                  isNotificationPersistent: widget.filter.isNotificationPersistent == true ? null : true,
                  clearIsNotificationPersistent: widget.filter.isNotificationPersistent == true,
                ));
              }),
              _buildToggleChip('Persistent Alarm', widget.filter.isAlarmPersistent == true, () {
                _updateFilter(widget.filter.copyWith(
                  isAlarmPersistent: widget.filter.isAlarmPersistent == true ? null : true,
                  clearIsAlarmPersistent: widget.filter.isAlarmPersistent == true,
                ));
              }),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Recurrence filters
          _buildSectionTitle('Recurrence'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToggleChip('One-time', widget.filter.isRecurring == false, () {
                _updateFilter(widget.filter.copyWith(
                  isRecurring: widget.filter.isRecurring == false ? null : false,
                  clearIsRecurring: widget.filter.isRecurring == false,
                ));
              }),
              _buildToggleChip('Recurring', widget.filter.isRecurring == true, () {
                _updateFilter(widget.filter.copyWith(
                  isRecurring: widget.filter.isRecurring == true ? null : true,
                  clearIsRecurring: widget.filter.isRecurring == true,
                ));
              }),
              _buildToggleChip('Daily', widget.filter.recurrenceType == RecurrenceType.daily, () {
                _updateFilter(widget.filter.copyWith(
                  recurrenceType: widget.filter.recurrenceType == RecurrenceType.daily 
                      ? null 
                      : RecurrenceType.daily,
                  clearRecurrenceType: widget.filter.recurrenceType == RecurrenceType.daily,
                ));
              }),
              _buildToggleChip('Weekly', widget.filter.recurrenceType == RecurrenceType.weekly, () {
                _updateFilter(widget.filter.copyWith(
                  recurrenceType: widget.filter.recurrenceType == RecurrenceType.weekly 
                      ? null 
                      : RecurrenceType.weekly,
                  clearRecurrenceType: widget.filter.recurrenceType == RecurrenceType.weekly,
                ));
              }),
              _buildToggleChip('Monthly', widget.filter.recurrenceType == RecurrenceType.monthly, () {
                _updateFilter(widget.filter.copyWith(
                  recurrenceType: widget.filter.recurrenceType == RecurrenceType.monthly 
                      ? null 
                      : RecurrenceType.monthly,
                  clearRecurrenceType: widget.filter.recurrenceType == RecurrenceType.monthly,
                ));
              }),
              _buildToggleChip('Yearly', widget.filter.recurrenceType == RecurrenceType.yearly, () {
                _updateFilter(widget.filter.copyWith(
                  recurrenceType: widget.filter.recurrenceType == RecurrenceType.yearly 
                      ? null 
                      : RecurrenceType.yearly,
                  clearRecurrenceType: widget.filter.recurrenceType == RecurrenceType.yearly,
                ));
              }),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Clear filters button
          if (widget.filter.isActive)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  widget.onClearFilters?.call();
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear All Filters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textMuted,
                  side: BorderSide(color: AppTheme.textMuted.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
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
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSortChip(String label, SortField field) {
    final isSelected = widget.filter.sortField == field;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (_) {
        _updateFilter(widget.filter.copyWith(sortField: field));
      },
      selectedColor: AppTheme.accentCyan.withOpacity(0.2),
      checkmarkColor: AppTheme.accentCyan,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.accentCyan : AppTheme.textSecondary,
        fontSize: 12,
      ),
      backgroundColor: Colors.white.withOpacity(0.05),
      side: BorderSide.none,
    );
  }

  Widget _buildSortOrderChip(String label, SortOrder order) {
    final isSelected = widget.filter.sortOrder == order;
    return ChoiceChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            order == SortOrder.ascending 
                ? Icons.arrow_upward 
                : Icons.arrow_downward,
            size: 14,
            color: isSelected ? AppTheme.accentCyan : AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      onSelected: (_) {
        _updateFilter(widget.filter.copyWith(sortOrder: order));
      },
      selectedColor: AppTheme.accentCyan.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.accentCyan : AppTheme.textSecondary,
        fontSize: 12,
      ),
      backgroundColor: Colors.white.withOpacity(0.05),
      side: BorderSide.none,
    );
  }

  Widget _buildToggleChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppTheme.accentCyan.withOpacity(0.2) 
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? AppTheme.accentCyan.withOpacity(0.5) 
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.accentCyan : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
