import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../design/components.dart';
import '../services/file_opener.dart';
import '../services/pdf_saver.dart';
import '../services/recent_files.dart';
import '../services/settings.dart';
import '../services/unsaved_changes.dart';
import '../theme.dart';
import '../widgets/password_dialog.dart';
import '../widgets/reading_filter.dart';
import '../widgets/search_bar.dart';
import '../widgets/thumbnails_panel.dart';
import 'help_screen.dart';
import 'organize_screen.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({required this.filePath, this.displayName, super.key});

  final String filePath;
  final String? displayName;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  static const _wideLayoutBreakpoint = Dim.wide;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _controller = PdfViewerController();

  // Created in onViewerReady: it needs the loaded document.
  PdfTextSearcher? _searcher;

  // The PDF is held in memory, so the file on disk is never locked and can be
  // overwritten on Save. Each edit produces new bytes and a new version.
  late String _path;
  late String _name;
  Uint8List? _bytes;
  PdfDocumentRef? _docRef;
  int _version = 0;
  int _openPage = 1;
  String? _openError;

  // Password of a protected PDF, kept so edited versions reopen without asking again.
  String? _password;
  bool _passwordConfirmed = false;

  int _currentPage = 1;
  int? _pageCount;
  bool _dirty = false;
  bool _busy = false;
  bool _showSearch = false;
  bool _showThumbnails = true; // used on wide screens only
  bool _chromeVisible = true; // phones hide the bars while reading

  final _settings = SettingsStore.instance;
  ReadingMode get _mode => _settings.readingMode;

  void _setDirty(bool value) {
    _dirty = value;
    UnsavedChanges.hasUnsaved.value = value;
  }

  @override
  void initState() {
    super.initState();
    _path = widget.filePath;
    _name = widget.displayName ?? fileNameOf(widget.filePath);
    _openPage = RecentFilesStore.instance.find(_path)?.lastPage ?? 1;
    _currentPage = _openPage;
    _settings.addListener(_onSettingsChanged);
    _loadFile();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    UnsavedChanges.hasUnsaved.value = false;
    RecentFilesStore.instance.flush();
    _disposeSearcher();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- loading

  Future<void> _loadFile() async {
    try {
      final bytes = await File(_path).readAsBytes();
      if (!mounted) return;
      _showBytes(bytes, page: _openPage);
    } catch (e) {
      if (mounted) setState(() => _openError = e.toString());
    }
  }

  /// Shows [bytes] in the viewer, starting at [page].
  void _showBytes(Uint8List bytes, {required int page}) {
    _disposeSearcher();
    setState(() {
      _bytes = bytes;
      _version++;
      _openPage = page;
      _currentPage = page;
      _pageCount = null;
      _docRef = PdfDocumentRefData(
        bytes,
        // A new name per version makes the viewer reload the document.
        sourceName: '$_path#v$_version',
        passwordProvider: _providePassword,
      );
    });
  }

  Future<String?> _providePassword() async {
    if (_passwordConfirmed) return _password;
    _password = await showPasswordDialog(context);
    return _password;
  }

  void _disposeSearcher() {
    _searcher?.removeListener(_onSearchChanged);
    _searcher?.dispose();
    _searcher = null;
    _showSearch = false;
  }

  // ---------------------------------------------------------------- navigation

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _currentPage) return;
    setState(() {
      _currentPage = page;
      // Reading on a phone: get the bars out of the way.
      if (_chromeVisible && !_showSearch && _isPhone) _chromeVisible = false;
    });
    if (!_dirty) RecentFilesStore.instance.updateProgress(_path, lastPage: page);
  }

  bool get _isPhone => MediaQuery.sizeOf(context).width < _wideLayoutBreakpoint;

  void _goToPage(int page) {
    if (!_controller.isReady) return;
    _controller.goToPage(pageNumber: page.clamp(1, _controller.pageCount), anchor: PdfPageAnchor.top);
  }

  void _zoomIn() {
    if (_controller.isReady) _controller.zoomUp();
  }

  void _zoomOut() {
    if (_controller.isReady) _controller.zoomDown();
  }

  void _fitWidth() {
    if (!_controller.isReady) return;
    final fits = _controller.calcFitZoomMatrices();
    if (fits.isNotEmpty) _controller.goTo(fits.first.matrix);
  }

  void _fitPage() {
    if (!_controller.isReady) return;
    _controller.goToPage(pageNumber: _currentPage, anchor: PdfPageAnchor.all);
  }

  void _openSearch() {
    if (_searcher != null) {
      setState(() {
        _showSearch = true;
        _chromeVisible = true;
      });
    }
  }

  void _closeSearch() {
    _searcher?.resetTextSearch();
    setState(() => _showSearch = false);
  }

  void _toggleThumbnails(bool wide) {
    if (wide) {
      setState(() => _showThumbnails = !_showThumbnails);
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  Future<void> _showGoToPageDialog() async {
    if (!_controller.isReady) return;
    final input = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '1 – ${_controller.pageCount}'),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(input.text)), child: const Text('Go')),
        ],
      ),
    );
    input.dispose();
    if (page != null) _goToPage(page);
  }

  // ---------------------------------------------------------------- editing

  Future<void> _openOrganize() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    final result = await Navigator.of(context).push<OrganizeResult>(
      MaterialPageRoute(
        builder: (_) => OrganizeScreen(bytes: bytes, fileName: _name, password: _password),
      ),
    );
    if (result == null || !mounted) return;
    _setDirty(true);
    _showBytes(result.bytes, page: _currentPage.clamp(1, result.pageCount));
    _snack('Pages updated. Save to keep the changes.');
  }

  // ---------------------------------------------------------------- saving

  /// Save over the current file.
  /// On Android the "current file" is the app's own copy, so it's also offered for export.
  Future<bool> _save() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return false;
    setState(() => _busy = true);
    try {
      await PdfSaver.writeTo(_path, bytes);
      if (!mounted) return true;
      setState(() => _setDirty(false));
      await RecentFilesStore.instance.updateProgress(_path, lastPage: _currentPage, pageCount: _pageCount);
      if (PdfSaver.canChooseSaveLocation) {
        _snack('Saved.');
      } else {
        _snack('Saved in Folio. Use Export to save it to your files or send it.', action: ('Export', _share));
      }
      return true;
    } catch (e) {
      _snack('Could not save here ($e). Try Save as.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Save to a new file (Windows) or export via the share sheet (Android).
  Future<void> _saveAs() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    if (!PdfSaver.canChooseSaveLocation) {
      // Keep the app's copy up to date too, so reopening from Recent shows the edits.
      if (_dirty) await _save();
      await _share();
      return;
    }
    setState(() => _busy = true);
    try {
      final newPath = await PdfSaver.saveAs(bytes, suggestedName: _name);
      if (newPath == null || !mounted) return;
      setState(() {
        _path = newPath;
        _name = fileNameOf(newPath);
        _setDirty(false);
      });
      await RecentFilesStore.instance.touch(newPath, _name);
      await RecentFilesStore.instance.updateProgress(newPath, lastPage: _currentPage, pageCount: _pageCount);
      _snack('Saved as $_name.');
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final bytes = _bytes;
    if (bytes == null) return;
    await PdfSaver.share(bytes, name: _name);
  }

  /// Asked when leaving with unsaved changes. Returns true if it's OK to leave.
  Future<bool> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save changes?'),
        content: Text('"$_name" has unsaved changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text("Don't save")),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    switch (choice) {
      case 'discard':
        return true;
      case 'save':
        return _save();
      default:
        return false;
    }
  }

  void _snack(String message, {(String, VoidCallback)? action}) {
    if (!mounted) return;
    showToast(context, message, actionLabel: action?.$1, onAction: action?.$2);
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final docRef = _docRef;
    final p = context.pal;

    final thumbnails = docRef == null
        ? const SizedBox()
        : ThumbnailsPanel(
            documentRef: docRef,
            currentPage: _currentPage,
            mode: _mode,
            onPageSelected: (page) {
              _goToPage(page);
              if (!wide) Navigator.of(context).maybePop(); // close the drawer
            },
          );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openSearch,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): _saveAs,
          const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
          const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): _zoomOut,
          const SingleActivator(LogicalKeyboardKey.digit0, control: true): _fitWidth,
          const SingleActivator(LogicalKeyboardKey.keyG, control: true): _showGoToPageDialog,
        },
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: p.background,
          drawer: wide || docRef == null
              ? null
              : Drawer(
                  width: 224,
                  backgroundColor: p.surface,
                  child: SafeArea(child: thumbnails),
                ),
          body: _buildBody(wide, thumbnails),
        ),
      ),
    );
  }

  Widget _buildBody(bool wide, Widget thumbnails) {
    final p = context.pal;
    if (_openError != null) {
      return Column(
        children: [
          SafeArea(bottom: false, child: _buildTopBar(wide)),
          Expanded(child: _ErrorView(message: 'This file could not be read.', details: _openError!)),
        ],
      );
    }

    final reader = Stack(
      children: [
        Positioned.fill(
          child: _docRef == null
              ? const Center(child: CircularProgressIndicator())
              : ReadingFilter(mode: _mode, child: _buildViewer(_docRef!)),
        ),
        if (_docRef != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                  child: AnimatedSlide(
                    duration: Dim.normal,
                    curve: Dim.curve,
                    offset: _chromeVisible || wide ? Offset.zero : const Offset(0, 1.6),
                    child: AnimatedOpacity(
                      duration: Dim.normal,
                      opacity: _chromeVisible || wide ? 1 : 0,
                      child: IgnorePointer(ignoring: !_chromeVisible && !wide, child: _buildDock(wide)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (wide) {
      return Column(
        children: [
          SafeArea(bottom: false, child: _buildTopBar(wide)),
          if (_showSearch && _searcher != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Align(alignment: Alignment.centerRight, child: PdfSearchBar(searcher: _searcher!, onClose: _closeSearch)),
            ),
          Expanded(
            child: Row(
              children: [
                AnimatedSize(
                  duration: Dim.normal,
                  curve: Dim.curve,
                  child: SizedBox(
                    width: _showThumbnails && _docRef != null ? 188 : 0,
                    child: _showThumbnails && _docRef != null
                        ? DecoratedBox(
                            decoration: BoxDecoration(border: Border(right: BorderSide(color: p.border))),
                            child: thumbnails,
                          )
                        : null,
                  ),
                ),
                Expanded(child: reader),
              ],
            ),
          ),
        ],
      );
    }

    // Phones: the bars float over the page and slide away while reading.
    return Stack(
      children: [
        Positioned.fill(child: reader),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            duration: Dim.normal,
            curve: Dim.curve,
            offset: _chromeVisible ? Offset.zero : const Offset(0, -1.2),
            child: AnimatedOpacity(
              duration: Dim.normal,
              opacity: _chromeVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopBar(wide),
                    if (_showSearch && _searcher != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: PdfSearchBar(searcher: _searcher!, onClose: _closeSearch),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- actions shared by the menu on both layouts

  List<List<SheetAction<String>>> _menuActions(bool wide) {
    final ready = _bytes != null && !_busy;
    return [
      [
        if (!wide) SheetAction(value: 'pages', icon: Icons.view_sidebar_outlined, label: 'Page thumbnails', enabled: ready),
        SheetAction(
          value: 'saveAs',
          icon: PdfSaver.canChooseSaveLocation ? Icons.save_as_outlined : Icons.ios_share_rounded,
          label: PdfSaver.canChooseSaveLocation ? 'Save as…' : 'Export…',
          enabled: ready,
        ),
        if (!PdfSaver.canChooseSaveLocation)
          SheetAction(value: 'share', icon: Icons.share_outlined, label: 'Share', enabled: ready),
      ],
      [
        const SheetAction(value: 'goto', icon: Icons.input_rounded, label: 'Go to page…'),
        const SheetAction(value: 'fitWidth', icon: Icons.width_normal_outlined, label: 'Fit width'),
        const SheetAction(value: 'fitPage', icon: Icons.fit_screen_outlined, label: 'Fit page'),
        const SheetAction(value: 'first', icon: Icons.first_page_rounded, label: 'First page'),
        const SheetAction(value: 'last', icon: Icons.last_page_rounded, label: 'Last page'),
      ],
      [const SheetAction(value: 'help', icon: Icons.help_outline_rounded, label: 'How to use')],
    ];
  }

  void _onMenuChoice(String v, bool wide) {
    switch (v) {
      case 'pages':
        _toggleThumbnails(wide);
      case 'saveAs':
        _saveAs();
      case 'share':
        _share();
      case 'goto':
        _showGoToPageDialog();
      case 'fitWidth':
        _fitWidth();
      case 'fitPage':
        _fitPage();
      case 'first':
        _goToPage(1);
      case 'last':
        if (_controller.isReady) _goToPage(_controller.pageCount);
      case 'help':
        HelpScreen.open(context);
    }
  }

  Future<void> _openMenuSheet(bool wide) async {
    final choice = await showActionSheet<String>(context, _menuActions(wide));
    if (choice != null) _onMenuChoice(choice, wide);
  }

  Widget _buildMoreButton(bool wide) {
    final p = context.pal;
    if (!wide) {
      return FolioIconButton(icon: Icons.more_horiz_rounded, tooltip: 'More', onPressed: () => _openMenuSheet(wide));
    }
    return PopupMenuButton<String>(
      tooltip: 'More',
      offset: const Offset(0, 46),
      onSelected: (v) => _onMenuChoice(v, wide),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        child: Icon(Icons.more_horiz_rounded, color: p.textPrimary),
      ),
      itemBuilder: (context) => [
        for (var g = 0; g < _menuActions(wide).length; g++) ...[
          if (g > 0) const PopupMenuDivider(),
          for (final a in _menuActions(wide)[g])
            PopupMenuItem<String>(
              value: a.value,
              enabled: a.enabled,
              child: Row(children: [Icon(a.icon, size: 19, color: p.textSecondary), const SizedBox(width: 12), Text(a.label)]),
            ),
        ],
      ],
    );
  }

  Widget _buildReadingModeButton() {
    final p = context.pal;
    final icon = switch (_mode) {
      ReadingMode.normal => Icons.description_outlined,
      ReadingMode.sepia => Icons.auto_stories_outlined,
      ReadingMode.dark => Icons.nights_stay_rounded,
    };
    return PopupMenuButton<ReadingMode>(
      tooltip: 'Page style',
      offset: const Offset(0, -150),
      onSelected: _settings.setReadingMode,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _mode == ReadingMode.normal ? Colors.transparent : p.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: _mode == ReadingMode.normal ? p.textPrimary : p.accentText, size: 22),
      ),
      itemBuilder: (context) => [
        for (final (m, icon, label) in const [
          (ReadingMode.normal, Icons.description_outlined, 'Normal'),
          (ReadingMode.sepia, Icons.auto_stories_outlined, 'Sepia'),
          (ReadingMode.dark, Icons.nights_stay_rounded, 'Dark pages'),
        ])
          PopupMenuItem<ReadingMode>(
            value: m,
            child: Row(
              children: [
                Icon(icon, size: 19, color: m == _mode ? p.accentText : p.textSecondary),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontWeight: m == _mode ? FontWeight.w700 : FontWeight.w500))),
                if (m == _mode) Icon(Icons.check_rounded, size: 18, color: p.accentText),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar(bool wide) {
    final p = context.pal;
    final ready = _bytes != null && !_busy;
    final progress = (_pageCount == null || _pageCount == 0) ? 0.0 : (_currentPage / _pageCount!).clamp(0.0, 1.0);

    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                const SizedBox(width: 6),
                FolioIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                      ),
                      Text(
                        _dirty ? 'Unsaved changes' : (_pageCount == null ? 'Opening…' : '$_pageCount pages'),
                        style: TextStyle(fontSize: 12, color: _dirty ? p.accentText : p.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  FolioIconButton(
                    icon: Icons.view_sidebar_outlined,
                    tooltip: 'Pages',
                    active: _showThumbnails,
                    onPressed: ready ? () => _toggleThumbnails(wide) : null,
                  ),
                  FolioIconButton(
                    icon: Icons.search_rounded,
                    tooltip: 'Find (Ctrl+F)',
                    active: _showSearch,
                    onPressed: _searcher == null ? null : (_showSearch ? _closeSearch : _openSearch),
                  ),
                  _buildReadingModeButton(),
                ] else
                  FolioIconButton(
                    icon: Icons.search_rounded,
                    tooltip: 'Find',
                    active: _showSearch,
                    onPressed: _searcher == null ? null : (_showSearch ? _closeSearch : _openSearch),
                  ),
                FolioIconButton(
                  icon: Icons.auto_awesome_mosaic_outlined,
                  tooltip: 'Organize pages',
                  onPressed: ready ? _openOrganize : null,
                ),
                FolioIconButton(
                  icon: _dirty ? Icons.save_rounded : Icons.save_outlined,
                  tooltip: 'Save (Ctrl+S)',
                  active: _dirty,
                  onPressed: ready && _dirty ? _save : null,
                ),
                _buildMoreButton(wide),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
        // Reading progress; becomes a busy indicator while saving.
        SizedBox(
          height: 2,
          child: _busy
              ? const LinearProgressIndicator(minHeight: 2)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: Dim.normal,
                    curve: Dim.curve,
                    widthFactor: progress,
                    child: Container(decoration: BoxDecoration(gradient: p.accentGradient)),
                  ),
                ),
        ),
      ],
    );

    if (wide) {
      return DecoratedBox(
        decoration: BoxDecoration(color: p.background, border: Border(bottom: BorderSide(color: p.border))),
        child: bar,
      );
    }
    return GlassPanel(border: false, child: bar);
  }

  Widget _buildViewer(PdfDocumentRef docRef) {
    final p = context.pal;
    // Colors drawn inside the filtered area are pre-inverted so they show up as intended.
    Color c(Color color) => ReadingFilter.preFilter(color, _mode);

    return PdfViewer(
      docRef,
      controller: _controller,
      initialPageNumber: _openPage,
      params: PdfViewerParams(
        backgroundColor: c(p.viewerBackdrop),
        margin: 14,
        pageDropShadow: BoxShadow(
          color: c(Colors.black.withValues(alpha: p.isDark ? 0.55 : 0.22)),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        matchTextColor: c(p.accent.withValues(alpha: 0.4)),
        activeMatchTextColor: c(const Color(0xFFFF9F1A).withValues(alpha: 0.6)),
        keyHandlerParams: const PdfViewerKeyHandlerParams(autofocus: true),
        sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(maxScale: 8),
        pagePaintCallbacks: [if (_searcher != null) _searcher!.pageTextMatchPaintCallback],
        onPageChanged: _onPageChanged,
        onGeneralTap: (context, controller, details) {
          if (details.type == PdfViewerGeneralTapType.tap && _isPhone) {
            setState(() => _chromeVisible = !_chromeVisible);
          }
          return false;
        },
        onViewerReady: (document, controller) {
          _passwordConfirmed = true;
          _searcher ??= PdfTextSearcher(controller)..addListener(_onSearchChanged);
          setState(() => _pageCount = document.pages.length);
          if (!_dirty) {
            RecentFilesStore.instance.updateProgress(_path, pageCount: document.pages.length);
          }
        },
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
            const Center(child: CircularProgressIndicator()),
        errorBannerBuilder: (context, error, stackTrace, documentRef) => _ErrorView(
          message: 'This PDF could not be opened.',
          details: error.toString(),
        ),
        viewerOverlayBuilder: (context, size, handleLinkTap) => [
          PdfViewerScrollThumb(
            controller: _controller,
            orientation: ScrollbarOrientation.right,
            thumbSize: const Size(6, 52),
            thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
              decoration: BoxDecoration(
                color: c(p.accent.withValues(alpha: 0.75)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDock(bool wide) {
    final p = context.pal;
    Widget divider() => Container(width: 1, height: 22, color: p.border, margin: const EdgeInsets.symmetric(horizontal: 2));

    return GlassPanel(
      borderRadius: BorderRadius.circular(30),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!wide) ...[
            FolioIconButton(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'Pages',
              onPressed: _bytes == null ? null : () => _toggleThumbnails(wide),
            ),
            divider(),
          ],
          Pressable(
            onTap: _showGoToPageDialog,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                _pageCount == null ? '–' : '$_currentPage / $_pageCount',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          divider(),
          FolioIconButton(icon: Icons.remove_rounded, tooltip: 'Zoom out (Ctrl+-)', size: 20, onPressed: _zoomOut),
          ListenableBuilder(
            // The controller notifies on every scroll/zoom change; only this label rebuilds.
            listenable: _controller,
            builder: (context, _) {
              final zoom = _controller.isReady ? (_controller.currentZoom * 100).round() : null;
              return Pressable(
                onTap: _fitWidth,
                child: SizedBox(
                  width: 48,
                  child: Text(
                    zoom == null ? '' : '$zoom%',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: p.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              );
            },
          ),
          FolioIconButton(icon: Icons.add_rounded, tooltip: 'Zoom in (Ctrl++)', size: 20, onPressed: _zoomIn),
          if (!wide) ...[divider(), _buildReadingModeButton()],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.details});

  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.danger.withValues(alpha: 0.12)),
                child: Icon(Icons.error_outline_rounded, size: 36, color: p.danger),
              ),
              const SizedBox(height: 18),
              Text(message, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'The file may be damaged or not a real PDF.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text(
                details,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary.withValues(alpha: 0.7), fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
