import 'package:material_ui/material_ui.dart';

import '../services/file_opener.dart';
import '../services/open_intent.dart';
import '../services/recent_files.dart';
import '../theme.dart';
import 'help_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({this.initialFile, super.key});

  /// A file passed on launch (e.g. "Open with" on Windows).
  final String? initialFile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final store = RecentFilesStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
    final initial = widget.initialFile;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPath(initial, fileNameOf(initial)));
    }
    // Android: a PDF opened from another app ("Open with" / "Share").
    OpenIntentService.initialFile().then((path) {
      if (path != null && mounted) _openPath(path, fileNameOf(path));
    });
    OpenIntentService.listen((path) {
      if (mounted) _openPath(path, fileNameOf(path));
    });
  }

  @override
  void dispose() {
    store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _pickAndOpen() async {
    final picked = await pickPdf();
    if (picked == null) return;
    await _openPath(picked.path, picked.name);
  }

  Future<void> _openPath(String path, String name) async {
    await store.touch(path, name);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ViewerScreen(filePath: path, displayName: name)),
    );
  }

  Future<void> _openRecent(RecentFile file) async {
    if (!file.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${file.name}" was moved or deleted.'),
          action: SnackBarAction(
            label: 'Remove',
            textColor: AppColors.accent,
            onPressed: () => store.remove(file.path),
          ),
        ),
      );
      return;
    }
    await _openPath(file.path, file.name);
  }

  @override
  Widget build(BuildContext context) {
    final files = store.files;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                  sliver: SliverToBoxAdapter(child: _Header(onOpen: _pickAndOpen)),
                ),
                if (files.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 12, 8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          const Text(
                            'Recent',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _confirmClear,
                            child: const Text('Clear', style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverList.builder(
                      itemCount: files.length,
                      itemBuilder: (context, i) => _RecentTile(
                        file: files[i],
                        onTap: () => _openRecent(files[i]),
                        onRemove: () => store.remove(files[i].path),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
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
    if (ok == true) await store.clear();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.description_rounded, color: AppColors.onAccent),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Folio PDF', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Free. No ads. No sign-in.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'How to use',
          onPressed: () => HelpScreen.open(context),
          icon: const Icon(Icons.help_outline_rounded, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Open PDF'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_outlined, size: 64, color: AppColors.border),
          SizedBox(height: 16),
          Text('No recent files', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            'PDFs you open will show up here.',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.file, required this.onTap, required this.onRemove});

  final RecentFile file;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final exists = file.exists;
    final progress = file.pageCount != null ? 'Page ${file.lastPage} of ${file.pageCount}' : null;
    final subtitle = [
      if (!exists) 'File moved or deleted' else if (progress != null) progress,
      _relativeTime(file.lastOpened),
    ].join('  ·  ');

    return Opacity(
      opacity: exists ? 1 : 0.45,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.accent, size: 22),
        ),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        trailing: IconButton(
          tooltip: 'Remove from list',
          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
          onPressed: onRemove,
        ),
        onTap: onTap,
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
