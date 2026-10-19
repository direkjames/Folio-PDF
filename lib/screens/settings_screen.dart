import 'package:material_ui/material_ui.dart';

import '../design/components.dart';
import '../services/recent_files.dart';
import '../services/settings.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final settings = SettingsStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                const SectionLabel('Appearance'),
                const SizedBox(height: 12),
                FolioCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 12),
                      _Choice<ThemeMode>(
                        value: settings.themeMode,
                        onChanged: settings.setThemeMode,
                        options: const [
                          (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
                          (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
                          (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionLabel('Reading'),
                const SizedBox(height: 12),
                FolioCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Page style', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        'How pages look while you read. Your files are never changed.',
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      _Choice<ReadingMode>(
                        value: settings.readingMode,
                        onChanged: settings.setReadingMode,
                        options: const [
                          (ReadingMode.normal, Icons.description_outlined, 'Normal'),
                          (ReadingMode.sepia, Icons.auto_stories_outlined, 'Sepia'),
                          (ReadingMode.dark, Icons.nights_stay_outlined, 'Dark'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionLabel('Data'),
                const SizedBox(height: 12),
                FolioCard(
                  shadow: false,
                  padding: EdgeInsets.zero,
                  onTap: () => _confirmClear(context),
                  child: ListTile(
                    leading: Icon(Icons.history_toggle_off_rounded, color: p.textSecondary),
                    title: const Text('Clear recent files', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Your PDFs are not deleted.', style: TextStyle(color: p.textSecondary)),
                  ),
                ),
                const SizedBox(height: 40),
                Center(
                  child: Column(
                    children: [
                      const FolioMark(size: 44),
                      const SizedBox(height: 12),
                      const FolioWordmark(size: 24),
                      const SizedBox(height: 4),
                      Text('Version 0.2.0', style: TextStyle(color: p.textSecondary, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text('Made by direk james', style: TextStyle(color: p.textSecondary, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text('Free. No ads. No sign-in.', style: TextStyle(color: p.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent files?'),
        content: const Text('This only clears the list. Your PDF files are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await RecentFilesStore.instance.clear();
      if (context.mounted) showToast(context, 'Recent files cleared.');
    }
  }
}

/// Segmented picker with icons; the selected option is gold.
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, IconData, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (final (v, icon, label) in options)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(v),
                haptic: true,
                scale: 0.96,
                child: AnimatedContainer(
                  duration: Dim.normal,
                  curve: Dim.curve,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: v == value ? p.accentGradient : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: v == value ? p.onAccent : p.textSecondary),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: v == value ? p.onAccent : p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
