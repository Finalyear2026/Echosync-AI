import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/event_provider.dart';
import '../models/event_filter.dart';
import '../theme/app_theme.dart';
import '../widgets/event_card.dart';
import '../widgets/event_filter_panel.dart';
import 'event_form_screen.dart';
import 'event_detail_screen.dart';

class EventManagerScreen extends StatefulWidget {
  const EventManagerScreen({super.key});

  @override
  State<EventManagerScreen> createState() => _EventManagerScreenState();
}

class _EventManagerScreenState extends State<EventManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventProvider>().loadEvents();
    });
  }

  Future<void> _showDeleteConfirmation(BuildContext context, EventProvider provider, String eventId) async {
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
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Delete',
                style: TextStyle(color: AppTheme.error),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await provider.deleteEvent(eventId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Event deleted'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          ),
          
          // Decorative Background Glows
          Positioned(
            top: -100,
            right: -50,
            child: _BackgroundGlow(
              size: 300,
              color: AppTheme.primaryPurple.withOpacity(0.12),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -100,
            child: _BackgroundGlow(
              size: 400,
              color: AppTheme.accentCyan.withOpacity(0.08),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // App bar
                _buildAppBar(context),
                
                // Main content
                Expanded(
                  child: Consumer<EventProvider>(
                    builder: (context, provider, child) {
                      if (provider.isLoading && provider.events.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.accentCyan,
                          ),
                        );
                      }

                      if (provider.error != null && provider.events.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: AppTheme.error.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Failed to load events',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => provider.loadEvents(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }

                      return CustomScrollView(
                        slivers: [
                          // Filter panel
                          SliverToBoxAdapter(
                            child: EventFilterPanel(
                              filter: provider.currentFilter,
                              onFilterChanged: (filter) {
                                provider.setFilter(filter);
                              },
                              onClearFilters: () {
                                provider.clearAllFilters();
                              },
                            ),
                          ),
                          
                          // Event count header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                              child: Row(
                                children: [
                                  Text(
                                    '${provider.events.length} ${provider.events.length == 1 ? 'Event' : 'Events'}',
                                    style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (provider.hasActiveFilter) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentCyan.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Filtered',
                                        style: TextStyle(
                                          color: AppTheme.accentCyan,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          
                          // Event list
                          if (provider.events.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmptyState(provider.hasActiveFilter),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final event = provider.events[index];
                                  return EventCard(
                                    event: event,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => EventDetailScreen(
                                            eventId: event.id,
                                            showAcknowledge: false,
                                          ),
                                        ),
                                      );
                                    },
                                    onEdit: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => EventFormScreen(
                                            event: event,
                                          ),
                                        ),
                                      );
                                    },
                                    onDelete: () {
                                      _showDeleteConfirmation(context, provider, event.id);
                                    },
                                    onToggleEnabled: (enabled) {
                                      provider.toggleEventEnabled(event.id);
                                    },
                                  );
                                },
                                childCount: provider.events.length,
                              ),
                            ),
                          
                          // Bottom padding
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 80),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Floating Action Button
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const EventFormScreen(),
                  ),
                );
              },
              backgroundColor: AppTheme.accentCyan,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'New Event',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Back button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event Manager',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Consumer<EventProvider>(
                  builder: (context, provider, child) {
                    return Text(
                      '${provider.upcomingEventCount} upcoming',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Refresh button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: AppTheme.accentCyan,
              onPressed: () {
                context.read<EventProvider>().loadEvents();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool hasFilter) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFilter ? Icons.filter_list_off : Icons.event_note_outlined,
              size: 40,
              color: AppTheme.accentCyan.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            hasFilter ? 'No events match your filters' : 'No events yet',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? 'Try adjusting your filter settings'
                : 'Create your first event to get started',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _BackgroundGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size * 0.5,
            spreadRadius: size * 0.2,
          ),
        ],
      ),
    );
  }
}
