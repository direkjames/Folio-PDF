import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/file_opener.dart';
import '../services/pdf_saver.dart';
import '../services/recent_files.dart';
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
  static const _wideLayoutBreakpoint = 760.0;
  static const _darkReadingKey = 'dark_reading';

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
  bool _darkReading = false;

  @override
  void initState() {
    super.initState();
    _path = widget.filePath;
    _name = widget.displayName ?? fileNameOf(widget.filePath);
    _openPage = RecentFilesStore.instance.find(_path)?.lastPage ?? 1;
    _currentPage = _openPage;
    _loadDarkReading();
    _loadFile();
  }

  @override
  void dispose() {
    _disposeSearcher();
    super.dispose();
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

  Future<void> _loadDarkReading() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _darkReading = prefs.getBool(_darkReadingKey) ?? false);
  }

  Future<void> _toggleDarkReading() async {
    setState(() => _darkReading = !_darkReading);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkReadingKey, _darkReading);
  }

  // ---------------------------------------------------------------- navigation

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _currentPage) return;
    setState(() => _currentPage = page);
    if (!_dirty) RecentFilesStore.instance.updateProgress(_path, lastPage: page);
  }

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
    if (_searcher != null) setState(() => _showSearch = true);
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
    _dirty = true;
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
      setState(() => _dirty = false);
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
        _dirty = false;
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: action == null ? 3 : 6),
          action: action == null
              ? null
              : SnackBarAction(label: action.$1, textColor: AppColors.accent, onPressed: action.$2),
        ),
      );
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final docRef = _docRef;

    final thumbnails = docRef == null
        ? const SizedBox()
        : ThumbnailsPanel(
            documentRef: docRef,
            currentPage: _currentPage,
            darkReading: _darkReading,
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
          drawer: wide || docRef == null ? null : Drawer(width: 200, child: SafeArea(child: thumbnails)),
          appBar: _buildAppBar(wide),
          body: _buildBody(wide, thumbnails),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool wide) {
    final ready = _bytes != null && !_busy;
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          if (_dirty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Unsaved changes',
                child: CircleAvatar(radius: 4, backgroundColor: AppColors.accent),
              ),
            ),
          Expanded(child: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Pages',
          onPressed: ready ? () => _toggleThumbnails(wide) : null,
          icon: Icon(Icons.view_sidebar_outlined, color: wide && _showThumbnails ? AppColors.accent : null),
        ),
        IconButton(
          tooltip: 'Find (Ctrl+F)',
          onPressed: _searcher == null ? null : (_showSearch ? _closeSearch : _openSearch),
          icon: Icon(Icons.search_rounded, color: _showSearch ? AppColors.accent : null),
        ),
        IconButton(
          tooltip: _darkReading ? 'Normal pages' : 'Dark pages',
          onPressed: _toggleDarkReading,
          icon: Icon(
            _darkReading ? Icons.dark_mode_rounded : Icons.dark_mode_outlined,
            color: _darkReading ? AppColors.accent : null,
          ),
        ),
        IconButton(
          tooltip: 'Organize pages',
          onPressed: ready ? _openOrganize : null,
          icon: const Icon(Icons.auto_awesome_mosaic_outlined),
        ),
        IconButton(
          tooltip: 'Save (Ctrl+S)',
          onPressed: ready && _dirty ? _save : null,
          icon: Icon(Icons.save_outlined, color: _dirty ? AppColors.accent : null),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) {
            switch (v) {
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
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'saveAs',
              enabled: ready,
              child: Text(PdfSaver.canChooseSaveLocation ? 'Save as…' : 'Export…'),
            ),
            if (!PdfSaver.canChooseSaveLocation)
              PopupMenuItem(value: 'share', enabled: ready, child: const Text('Share')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'goto', child: Text('Go to page…')),
            const PopupMenuItem(value: 'fitWidth', child: Text('Fit width')),
            const PopupMenuItem(value: 'fitPage', child: Text('Fit page')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'first', child: Text('First page')),
            const PopupMenuItem(value: 'last', child: Text('Last page')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'help', child: Text('How to use')),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: _busy ? const LinearProgressIndicator(minHeight: 2) : const Divider(height: 2),
      ),
    );
  }

  Widget _buildBody(bool wide, Widget thumbnails) {
    if (_openError != null) {
      return _ErrorView(message: 'This file could not be read.', details: _openError!);
    }
    if (_docRef == null) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        if (_showSearch && _searcher != null) PdfSearchBar(searcher: _searcher!, onClose: _closeSearch),
        Expanded(
          child: Row(
            children: [
              if (wide)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: SizedBox(
                    width: _showThumbnails ? 180 : 0,
                    child: _showThumbnails
                        ? DecoratedBox(
                            decoration: const BoxDecoration(
                              border: Border(right: BorderSide(color: AppColors.border)),
                            ),
                            child: thumbnails,
                          )
                        : null,
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    ReadingFilter(enabled: _darkReading, child: _buildViewer(_docRef!)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(child: _buildBottomPill()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewer(PdfDocumentRef docRef) {
    // Colors drawn inside the inverted area are pre-inverted so they show up as intended.
    Color c(Color color) => ReadingFilter.preInvert(color, _darkReading);

    return PdfViewer(
      docRef,
      controller: _controller,
      initialPageNumber: _openPage,
      params: PdfViewerParams(
        backgroundColor: c(AppColors.viewerBackdrop),
        margin: 10,
        pageDropShadow: null,
        matchTextColor: c(AppColors.accent.withValues(alpha: 0.35)),
        activeMatchTextColor: c(const Color(0xFFFF9F1A).withValues(alpha: 0.55)),
        keyHandlerParams: PdfViewerKeyHandlerParams(autofocus: true),
        sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(maxScale: 8),
        pagePaintCallbacks: [if (_searcher != null) _searcher!.pageTextMatchPaintCallback],
        onPageChanged: _onPageChanged,
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
            thumbSize: const Size(6, 48),
            thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
              decoration: BoxDecoration(
                color: c(AppColors.accent.withValues(alpha: 0.7)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPill() {
    return Material(
      color: AppColors.surfaceHigh.withValues(alpha: 0.94),
      elevation: 6,
      shadowColor: Colors.black,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              customBorder: const StadiumBorder(),
              onTap: _showGoToPageDialog,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  _pageCount == null ? '–' : '$_currentPage / $_pageCount',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
            Container(width: 1, height: 20, color: AppColors.border),
            IconButton(
              tooltip: 'Zoom out (Ctrl+-)',
              visualDensity: VisualDensity.compact,
              onPressed: _zoomOut,
              icon: const Icon(Icons.remove_rounded, size: 20),
            ),
            ListenableBuilder(
              // The controller notifies on every scroll/zoom change; only this label rebuilds.
              listenable: _controller,
              builder: (context, _) {
                final zoom = _controller.isReady ? (_controller.currentZoom * 100).round() : null;
                return InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _fitWidth,
                  child: SizedBox(
                    width: 52,
                    child: Text(
                      zoom == null ? '' : '$zoom%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Zoom in (Ctrl++)',
              visualDensity: VisualDensity.compact,
              onPressed: _zoomIn,
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.accent),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              details,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
