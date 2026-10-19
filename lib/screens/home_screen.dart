import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import '../design/components.dart';
import '../services/file_opener.dart';
import '../services/open_intent.dart';
import '../services/recent_files.dart';
import '../services/unsaved_changes.dart';
import '../theme.dart';
import '../widgets/pdf_cover.dart';
import 'help_screen.dart';
import 'settings_screen.dart';
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
  final _search = TextEditingController();
  bool _dragging = false;
  bool _viewerOpen = false;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
    store.refreshAvailability();
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
    OpenIntentService.stopListening();
    _search.dispose();
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
    final navigator = Navigator.of(context);
    if (_viewerOpen) {
      // Another file arrived while one is open: never silently throw away edits.
      if (UnsavedChanges.hasUnsaved.value) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open another file?'),
            content: Text('The open document has unsaved changes. Opening "$name" will discard them.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay here')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard and open')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        UnsavedChanges.hasUnsaved.value = false;
      }
      navigator.popUntil((route) => route.isFirst);
    }
    await store.touch(path, name);
    if (!mounted) return;
    _viewerOpen = true;
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => ViewerScreen(filePath: path, displayName: name)),
    );
    _viewerOpen = false;
    UnsavedChanges.hasUnsaved.value = false;
    await store.flush();
    store.refreshAvailability();
  }

  Future<void> _openRecent(RecentFile file) async {
    if (store.isMissing(file.path)) {
      showToast(
        context,
        '"${file.name}" was moved or deleted.',
        icon: Icons.link_off_rounded,
        actionLabel: 'Remove',
        onAction: () => store.remove(file.path),
      );
      return;
    }
    await _openPath(file.path, file.name);
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final pdfs = details.files.where((f) => f.path.toLowerCase().endsWith('.pdf')).toList();
    if (pdfs.isEmpty) {
      if (mounted) showToast(context, 'Only PDF files can be opened.', icon: Icons.info_outline_rounded);
      return;
    }
    await _openPath(pdfs.first.path, fileNameOf(pdfs.first.path));
  }

  Future<void> _showFileMenu(RecentFile file, Offset? globalPosition) async {
    final choice = globalPosition != null
        ? await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
              globalPosition.dx,
              globalPosition.dy,
              globalPosition.dx,
              globalPosition.dy,
            ),
            items: const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'remove', child: Text('Remove from list')),
            ],
          )
        : await showActionSheet<String>(
            context,
            [
              [
                const SheetAction(value: 'open', icon: Icons.menu_book_rounded, label: 'Open'),
                const SheetAction(value: 'remove', icon: Icons.delete_outline_rounded, label: 'Remove from list'),
              ],
            ],
            title: file.name,
          );
    if (choice == 'open') await _openRecent(file);
    if (choice == 'remove') await store.remove(file.path);
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

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Working late?';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = store.files;
    final query = _search.text.trim().toLowerCase();
    final files = query.isEmpty ? all : all.where((f) => f.name.toLowerCase().contains(query)).toList();
    final width = MediaQuery.sizeOf(context).width;
    final grid = width >= Dim.wide;

    // The most recent file that still exists becomes the "Continue reading" card.
    final continueFile = all.where((f) => !store.isMissing(f.path)).firstOrNull;
    final listFiles = (query.isEmpty && continueFile != null)
        ? files.where((f) => f.path != continueFile.path).toList()
        : files;

    final content = Scaffold(
      body: Stack(
        children: [
          // Soft gold glow behind the header.
          Positioned(
            top: -140,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.9,
                    colors: [p.accent.withValues(alpha: p.isDark ? 0.14 : 0.18), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      sliver: SliverToBoxAdapter(child: _Header(greeting: _greeting())),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: _OpenCard(onOpen: _pickAndOpen, dragging: _dragging, showDropHint: Platform.isWindows),
                      ),
                    ),
                    if (all.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.auto_stories_rounded,
                          title: 'Your library is empty',
                          message: 'PDFs you open will appear here, ready to pick up right where you left off.',
                        ),
                      )
                    else ...[
                      if (query.isEmpty && continueFile != null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                          sliver: SliverToBoxAdapter(
                            child: _ContinueCard(
                              file: continueFile,
                              onTap: () => _openRecent(continueFile),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 14),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(child: SectionLabel('Recent')),
                                  TextButton(
                                    onPressed: _confirmClear,
                                    child: Text('Clear', style: TextStyle(color: p.textSecondary)),
                                  ),
                                ],
                              ),
                              if (all.length > 4) ...[
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _search,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'Search your files',
                                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                    suffixIcon: query.isEmpty
                                        ? null
                                        : IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 18),
                                            onPressed: () => setState(_search.clear),
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (files.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Center(child: Text('No files match "$query".', style: TextStyle(color: p.textSecondary))),
                          ),
                        )
                      else if (grid)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 20,
                              childAspectRatio: 0.66,
                            ),
                            itemCount: listFiles.length,
                            itemBuilder: (context, i) => _GridTile(
                              file: listFiles[i],
                              missing: store.isMissing(listFiles[i].path),
                              onTap: () => _openRecent(listFiles[i]),
                              onMenu: (pos) => _showFileMenu(listFiles[i], pos),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          sliver: SliverList.separated(
                            itemCount: listFiles.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final f = listFiles[i];
                              return Dismissible(
                                key: ValueKey(f.path),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => store.remove(f.path),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  decoration: BoxDecoration(
                                    color: p.danger.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(Dim.rLg),
                                  ),
                                  child: Icon(Icons.delete_outline_rounded, color: p.danger),
                                ),
                                child: _RowTile(
                                  file: f,
                                  missing: store.isMissing(f.path),
                                  onTap: () => _openRecent(f),
                                  onMenu: (pos) => _showFileMenu(f, pos),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!Platform.isWindows) return content;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: content,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        const FolioMark(size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FolioWordmark(size: 28),
              Text(greeting, style: TextStyle(color: p.textSecondary, fontSize: 13.5)),
            ],
          ),
        ),
        FolioIconButton(
          icon: Icons.help_outline_rounded,
          tooltip: 'How to use',
          onPressed: () => HelpScreen.open(context),
        ),
        FolioIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Settings',
          onPressed: () => SettingsScreen.open(context),
        ),
      ],
    );
  }
}

class _OpenCard extends StatelessWidget {
  const _OpenCard({required this.onOpen, required this.dragging, required this.showDropHint});

  final VoidCallback onOpen;
  final bool dragging;
  final bool showDropHint;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Pressable(
      onTap: onOpen,
      haptic: true,
      scale: 0.985,
      child: AnimatedContainer(
        duration: Dim.normal,
        curve: Dim.curve,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: dragging
              ? p.accentGradient
              : LinearGradient(colors: [p.accent.withValues(alpha: 0.7), p.border, p.accent.withValues(alpha: 0.25)]),
          borderRadius: BorderRadius.circular(Dim.rXl),
          boxShadow: dragging ? p.glow : p.softShadow,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Dim.rXl - 2),
          ),
          child: Row(
            children: [
              const IconTile(icon: Icons.folder_open_rounded, size: 54, filled: true),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dragging ? 'Drop to open' : 'Open a PDF',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      showDropHint ? 'Choose a file, or drag one here.' : 'Choose a file from your device.',
                      style: TextStyle(color: p.textSecondary, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: p.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.file, required this.onTap});

  final RecentFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = file.pageCount;
    final progress = total == null || total == 0 ? null : (file.lastPage / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Continue reading'),
        const SizedBox(height: 14),
        FolioCard(
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                height: 116,
                child: PdfCover(path: file.path, radius: 10),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (total != null) 'Page ${file.lastPage} of $total',
                        _relativeTime(file.lastOpened),
                      ].join('  ·  '),
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 14),
                      _ProgressLine(value: progress),
                    ],
                    const SizedBox(height: 16),
                    GoldButton(label: 'Continue', icon: Icons.play_arrow_rounded, onPressed: onTap, compact: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(height: 4, color: p.border),
          FractionallySizedBox(
            widthFactor: value,
            child: Container(height: 4, decoration: BoxDecoration(gradient: p.accentGradient)),
          ),
        ],
      ),
    );
  }
}

/// Grid card with a big cover (Windows / tablets).
class _GridTile extends StatelessWidget {
  const _GridTile({required this.file, required this.missing, required this.onTap, required this.onMenu});

  final RecentFile file;
  final bool missing;
  final VoidCallback onTap;
  final void Function(Offset? position) onMenu;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = file.pageCount;
    final progress = total == null || total == 0 ? null : (file.lastPage / total).clamp(0.0, 1.0);
    return GestureDetector(
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      child: Pressable(
        onTap: onTap,
        onLongPress: () => onMenu(null),
        child: Opacity(
          opacity: missing ? 0.5 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SizedBox.expand(child: PdfCover(path: file.path, missing: missing, radius: 14))),
              const SizedBox(height: 12),
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                missing ? 'Moved or deleted' : _relativeTime(file.lastOpened),
                style: TextStyle(color: missing ? p.danger : p.textSecondary, fontSize: 12),
              ),
              if (progress != null && !missing) ...[const SizedBox(height: 8), _ProgressLine(value: progress)],
            ],
          ),
        ),
      ),
    );
  }
}

/// List row with a small cover (phones).
class _RowTile extends StatelessWidget {
  const _RowTile({required this.file, required this.missing, required this.onTap, required this.onMenu});

  final RecentFile file;
  final bool missing;
  final VoidCallback onTap;
  final void Function(Offset? position) onMenu;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = file.pageCount;
    final progress = total == null || total == 0 ? null : (file.lastPage / total).clamp(0.0, 1.0);
    final subtitle = [
      if (missing) 'File moved or deleted' else if (total != null) 'Page ${file.lastPage} of $total',
      _relativeTime(file.lastOpened),
    ].join('  ·  ');

    return GestureDetector(
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      child: Opacity(
        opacity: missing ? 0.55 : 1,
        child: FolioCard(
          onTap: onTap,
          shadow: false,
          radius: Dim.rLg,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 50, height: 68, child: PdfCover(path: file.path, missing: missing, radius: 8)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                    if (progress != null && !missing) ...[const SizedBox(height: 10), _ProgressLine(value: progress)],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz_rounded, color: p.textSecondary),
                onPressed: () => onMenu(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
