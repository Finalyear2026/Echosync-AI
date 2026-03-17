import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/processing_state.dart';
import '../theme/app_theme.dart';


/// Settings screen with dictionary, snippets, style/tone, and model management.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: Consumer<AppProvider>(
                  builder: (context, provider, child) {
                    return ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                         _SectionHeader(title: 'Transcription', icon: Icons.subtitles_rounded),
                         _TranscriptionSettings(provider: provider),
                         const SizedBox(height: 24),

                         _SectionHeader(title: 'Personal Dictionary', icon: Icons.spellcheck_rounded),
                         _DictionarySection(provider: provider),
                         const SizedBox(height: 24),


                        _SectionHeader(title: 'Personal Dictionary', icon: Icons.spellcheck_rounded),
                        _DictionarySection(provider: provider),
                        const SizedBox(height: 24),

                        _SectionHeader(title: 'Snippet Library', icon: Icons.text_snippet_rounded),
                        _SnippetSection(provider: provider),
                        const SizedBox(height: 40),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppTheme.textPrimary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Text(
            'Settings',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Section Header ---
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentCyan, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Transcription Settings ---
class _TranscriptionSettings extends StatelessWidget {
  final AppProvider provider;

  const _TranscriptionSettings({required this.provider});

  @override
  Widget build(BuildContext context) {
    final settings = provider.appSettings;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Style toggle
          _SettingsRow(
            label: 'Transcription Style',
            child: SegmentedButton<TranscriptionStyle>(
              segments: const [
                ButtonSegment(
                  value: TranscriptionStyle.raw,
                  label: Text('Raw', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: TranscriptionStyle.smart,
                  label: Text('Smart', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {settings.transcriptionStyle},
              onSelectionChanged: (value) {
                provider.setTranscriptionStyle(value.first);
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppTheme.primaryPurple.withOpacity(0.3);
                  }
                  return Colors.transparent;
                }),
              ),
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.06)),

          // Tone toggle
          _SettingsRow(
            label: 'Transcription Tone',
            child: SegmentedButton<TranscriptionTone>(
              segments: const [
                ButtonSegment(
                  value: TranscriptionTone.formal,
                  label: Text('Formal', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: TranscriptionTone.casual,
                  label: Text('Casual', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {settings.transcriptionTone},
              onSelectionChanged: (value) {
                provider.setTranscriptionTone(value.first);
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppTheme.primaryPurple.withOpacity(0.3);
                  }
                  return Colors.transparent;
                }),
              ),
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.06)),

          // Noise filter toggle
          _SettingsRow(
            label: 'Noise Filtering',
            child: Switch(
              value: settings.noiseFilterEnabled,
              onChanged: (value) => provider.setNoiseFilterEnabled(value),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          child,
        ],
      ),
    );
  }
}



// --- Dictionary Section ---
class _DictionarySection extends StatelessWidget {
  final AppProvider provider;

  const _DictionarySection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final entries = provider.dictionary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No dictionary entries yet.\nAdd words the AI often mishears.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ),
          ...entries.map((entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '"${entry.misheardWord}" → "${entry.correctWord}"',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppTheme.textMuted,
                  onPressed: () => provider.deleteDictionaryEntry(entry.id),
                ),
              )),
          const SizedBox(height: 8),
          _AddButton(
            label: 'Add Word',
            onTap: () => _showAddDictionaryDialog(context, provider),
          ),
        ],
      ),
    );
  }

  void _showAddDictionaryDialog(BuildContext context, AppProvider provider) {
    final misheardController = TextEditingController();
    final correctController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Dictionary Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: misheardController,
              decoration: const InputDecoration(
                labelText: 'Misheard Word',
                hintText: 'e.g., "pak stan"',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: correctController,
              decoration: const InputDecoration(
                labelText: 'Correct Word',
                hintText: 'e.g., "Pakistan"',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (misheardController.text.isNotEmpty &&
                  correctController.text.isNotEmpty) {
                provider.addDictionaryEntry(
                    misheardController.text, correctController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// --- Snippet Section ---
class _SnippetSection extends StatelessWidget {
  final AppProvider provider;

  const _SnippetSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final snippets = provider.snippets;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          if (snippets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No snippets yet.\nAdd text templates triggered by phrases.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ),
          ...snippets.map((snippet) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '"${snippet.triggerPhrase}"',
                  style: const TextStyle(
                    color: AppTheme.accentCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  snippet.templateContent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppTheme.textMuted,
                  onPressed: () => provider.deleteSnippet(snippet.id),
                ),
              )),
          const SizedBox(height: 8),
          _AddButton(
            label: 'Add Snippet',
            onTap: () => _showAddSnippetDialog(context, provider),
          ),
        ],
      ),
    );
  }

  void _showAddSnippetDialog(BuildContext context, AppProvider provider) {
    final triggerController = TextEditingController();
    final templateController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Snippet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: triggerController,
              decoration: const InputDecoration(
                labelText: 'Trigger Phrase',
                hintText: 'e.g., "my email"',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: templateController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Template Content',
                hintText: 'e.g., "contact@example.com"',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (triggerController.text.isNotEmpty &&
                  templateController.text.isNotEmpty) {
                provider.addSnippet(
                    triggerController.text, templateController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.accentCyan,
          side: BorderSide(color: AppTheme.accentCyan.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
