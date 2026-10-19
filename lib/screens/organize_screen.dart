import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../design/components.dart';
import '../services/file_opener.dart';
import '../services/pdf_saver.dart';
import '../theme.dart';
import '../widgets/password_dialog.dart';

/// What the organize screen hands back to the viewer when the user taps Done.
class OrganizeResult {
  const OrganizeResult({required this.bytes, required this.pageCount});
  final Uint8List bytes;
  final int pageCount;
}

/// One page in the working list. Pages can come from the current PDF or from
/// PDFs the user adds (merge), and carry their own rotation.
class _PageItem {
  _PageItem({
    required this.uid,
    required this.doc,
    required this.pageNumber,
    required this.rotation,
    required this.sourceName,
    required this.fromOtherFile,
  });

  final int uid;
  final PdfDocument doc;
  final int pageNumber; // 1-based, inside [doc]
  final PdfPageRotation rotation;
  final String sourceName;
  final bool fromOtherFile;

  PdfPage get page => doc.pages[pageNumber - 1];

  /// The page as it should be written to the output, with rotation applied.
  PdfPage get outputPage => rotation == page.rotation ? page : page.rotatedTo(rotation);

  _PageItem rotated({required bool clockwise}) => _PageItem(
        uid: uid,
        doc: doc,
        pageNumber: pageNumber,
        rotation: clockwise ? rotation.rotateCW90 : rotation.rotateCCW90,
        sourceName: sourceName,
        fromOtherFile: fromOtherFile,
      );
}

/// Reorder, rotate, delete, extract and merge pages.
class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({
    required this.bytes,
    required this.fileName,
    this.password,
    super.key,
  });

  final Uint8List bytes;
  final String fileName;
  final String? password;

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  PdfDocument? _baseDoc;
  final _otherDocs = <PdfDocument>[];
  List<_PageItem> _items = [];
  final _history = <List<_PageItem>>[];
  final _selected = <int>{}; // uids
  int _nextUid = 0;
  bool _busy = false;
  final _scroll = ScrollController();
  final _gridKey = GlobalKey();
  int? _dragUid;
  int? _hoverUid;
  double _pointerY = 0;
  Timer? _autoScroll;
  String? _loadError;

  bool get _hasChanges => _history.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    _baseDoc?.dispose();
    for (final d in _otherDocs) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await PdfDocument.openData(
        widget.bytes,
        sourceName: 'organize:${widget.fileName}:${DateTime.now().microsecondsSinceEpoch}',
        passwordProvider: () => widget.password,
      );
      if (!mounted) {
        doc.dispose();
        return;
      }
      setState(() {
        _baseDoc = doc;
        _items = _itemsFor(doc, widget.fileName, fromOtherFile: false);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  List<_PageItem> _itemsFor(PdfDocument doc, String name, {required bool fromOtherFile}) => [
        for (var i = 0; i < doc.pages.length; i++)
          _PageItem(
            uid: _nextUid++,
            doc: doc,
            pageNumber: i + 1,
            rotation: doc.pages[i].rotation,
            sourceName: name,
            fromOtherFile: fromOtherFile,
          ),
      ];

  /// Records the current state so it can be undone, then applies [change].
  void _edit(void Function() change) {
    _history.add(List.of(_items));
    if (_history.length > 50) _history.removeAt(0);
    setState(change);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _items = _history.removeLast();
      _selected.removeWhere((uid) => !_items.any((p) => p.uid == uid));
    });
  }

  void _rotate(Set<int> uids, {required bool clockwise}) {
    if (uids.isEmpty) return;
    _edit(() {
      _items = [for (final p in _items) uids.contains(p.uid) ? p.rotated(clockwise: clockwise) : p];
    });
  }

  void _delete(Set<int> uids) {
    if (uids.isEmpty) return;
    if (uids.length >= _items.length) {
      _snack('A PDF needs at least one page.');
      return;
    }
    _edit(() {
      _items = _items.where((p) => !uids.contains(p.uid)).toList();
      _selected.removeAll(uids);
    });
  }

  void _duplicate(_PageItem item) {
    final i = _items.indexWhere((p) => p.uid == item.uid);
    _edit(() {
      _items.insert(
        i + 1,
        _PageItem(
          uid: _nextUid++,
          doc: item.doc,
          pageNumber: item.pageNumber,
          rotation: item.rotation,
          sourceName: item.sourceName,
          fromOtherFile: item.fromOtherFile,
        ),
      );
    });
  }

  /// Moves the page with [uid] so it ends up at [target] in the list.
  void _moveTo(int uid, int target) {
    final from = _items.indexWhere((p) => p.uid == uid);
    if (from < 0 || target < 0 || target >= _items.length || from == target) return;
    _edit(() {
      final item = _items.removeAt(from);
      _items.insert(target, item);
    });
  }

  // Scrolls the grid while a page is dragged near its top or bottom edge.
  void _startAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !_scroll.hasClients) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final y = _pointerY - top;
      const edge = 90.0;
      var delta = 0.0;
      if (y < edge) {
        delta = -(edge - y) / edge * 14;
      } else if (y > box.size.height - edge) {
        delta = (y - (box.size.height - edge)) / edge * 14;
      }
      if (delta == 0) return;
      final pos = _scroll.position;
      _scroll.jumpTo((pos.pixels + delta).clamp(0.0, pos.maxScrollExtent));
    });
  }

  void _stopDrag() {
    _autoScroll?.cancel();
    setState(() {
      _dragUid = null;
      _hoverUid = null;
    });
  }

  void _toggleSelect(int uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  void _selectAll() => setState(() {
        if (_selected.length == _items.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(_items.map((p) => p.uid));
        }
      });

  /// Merge: append all pages of one or more other PDFs.
  Future<void> _addPdfs() async {
    final files = await fs.openFiles(
      acceptedTypeGroups: const [
        fs.XTypeGroup(
          label: 'PDF files',
          extensions: <String>['pdf'],
          mimeTypes: <String>['application/pdf'],
          uniformTypeIdentifiers: <String>['com.adobe.pdf'],
        ),
      ],
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final added = <_PageItem>[];
    for (final f in files) {
      final name = f.name.isNotEmpty ? f.name : fileNameOf(f.path);
      try {
        final bytes = await File(f.path).readAsBytes();
        if (!mounted) return;
        final doc = await PdfDocument.openData(
          bytes,
          sourceName: 'merge:$name:${DateTime.now().microsecondsSinceEpoch}',
          passwordProvider: () => showPasswordDialog(context),
        );
        _otherDocs.add(doc);
        added.addAll(_itemsFor(doc, name, fromOtherFile: true));
      } catch (e) {
        _snack('Could not add "$name".');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (added.isNotEmpty) {
      _edit(() => _items.addAll(added));
      _snack('Added ${added.length} page${added.length == 1 ? '' : 's'}.');
    }
  }

  /// Split: save the selected pages as a new, separate PDF.
  Future<void> _extractSelected() async {
    final pages = _items.where((p) => _selected.contains(p.uid)).toList();
    if (pages.isEmpty) return;
    setState(() => _busy = true);
    try {
      final out = await PdfDocument.createNew(sourceName: 'extract:${DateTime.now().microsecondsSinceEpoch}');
      out.pages = pages.map((p) => p.outputPage).toList();
      final bytes = await out.encodePdf();
      out.dispose();
      final positions = [for (var i = 0; i < _items.length; i++) if (_selected.contains(_items[i].uid)) i + 1];
      final saved = await PdfSaver.saveAs(
        bytes,
        suggestedName: PdfSaver.withSuffix(widget.fileName, 'pages ${_describeRange(positions)}'),
      );
      if (saved != null) _snack('Saved ${pages.length} page${pages.length == 1 ? '' : 's'} to ${fileNameOf(saved)}.');
    } catch (e) {
      _snack('Could not extract pages: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "1,2,3,5,7,8" -> "1-3, 5, 7-8"
  static String _describeRange(List<int> nums) {
    final parts = <String>[];
    var i = 0;
    while (i < nums.length) {
      var j = i;
      while (j + 1 < nums.length && nums[j + 1] == nums[j] + 1) {
        j++;
      }
      parts.add(i == j ? '${nums[i]}' : '${nums[i]}-${nums[j]}');
      i = j + 1;
    }
    final s = parts.join(', ');
    return s.length > 40 ? '${nums.length} pages' : s;
  }

  Future<void> _done() async {
    final base = _baseDoc;
    if (base == null) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List bytes;
      if (_onlyRotationsChanged(base)) {
        // Same pages in the same order: edit the original document in place,
        // which keeps its bookmarks, form fields and other document-level data.
        base.pages = _items.map((p) => p.outputPage).toList();
        bytes = await base.encodePdf();
      } else {
        // Pages were moved, deleted, duplicated or added. pdfrx 2.6.5 doesn't
        // apply reordering/deletion when assembling a document in place, so
        // build a fresh PDF and import every page into it (this path works).
        final out = await PdfDocument.createNew(sourceName: 'organized:${DateTime.now().microsecondsSinceEpoch}');
        try {
          out.pages = _items.map((p) => p.outputPage).toList();
          bytes = await out.encodePdf();
        } finally {
          out.dispose();
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(OrganizeResult(bytes: bytes, pageCount: _items.length));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not apply changes: $e');
    }
  }

  /// True when every original page is still there, once, in its original position.
  bool _onlyRotationsChanged(PdfDocument base) {
    if (_items.length != base.pages.length) return false;
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      if (p.fromOtherFile || !identical(p.doc, base) || p.pageNumber != i + 1) return false;
    }
    return true;
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard page changes?'),
        content: const Text('Your reordering, rotations and deletions will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  void _snack(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _history.clear();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: FolioIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Organize pages', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${_items.length} pages', style: TextStyle(fontSize: 12, color: p.textSecondary, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: [
            FolioIconButton(
              icon: Icons.undo_rounded,
              tooltip: 'Undo',
              onPressed: _history.isEmpty || _busy ? null : _undo,
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: GoldButton(
                  label: 'Done',
                  compact: true,
                  onPressed: _baseDoc == null || _busy ? null : _done,
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _busy ? const LinearProgressIndicator(minHeight: 2) : const Divider(height: 2),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final p = context.pal;
    if (_loadError != null) {
      return Center(child: Text('Could not open pages.\n$_loadError', textAlign: TextAlign.center));
    }
    if (_baseDoc == null) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: [
        Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: Listener(
                onPointerMove: (e) => _pointerY = e.position.dy,
                onPointerDown: (e) => _pointerY = e.position.dy,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: GridView.builder(
                      key: _gridKey,
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(20, 8, 20, _selected.isEmpty ? 32 : 110),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.66,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) => _buildTile(index),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Center(
              child: AnimatedSlide(
                duration: Dim.normal,
                curve: Dim.curve,
                offset: _selected.isEmpty ? const Offset(0, 1.8) : Offset.zero,
                child: AnimatedOpacity(
                  duration: Dim.normal,
                  opacity: _selected.isEmpty ? 0 : 1,
                  child: IgnorePointer(ignoring: _selected.isEmpty, child: _buildSelectionBar(p)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final p = context.pal;
    final all = _selected.length == _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Pressable(
            onTap: _busy ? null : _selectAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: p.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: all ? p.accent : p.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    all ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    size: 19,
                    color: all ? p.accentText : p.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selected.isEmpty ? 'Select all' : '${_selected.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Pressable(
            onTap: _busy ? null : _addPdfs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.note_add_outlined, size: 19, color: p.accentText),
                  const SizedBox(width: 8),
                  Text('Add PDF', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: p.accentText)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(FolioPalette p) {
    final sel = Set.of(_selected);
    return GlassPanel(
      borderRadius: BorderRadius.circular(28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FolioIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Clear selection',
            onPressed: () => setState(_selected.clear),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('${sel.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Container(width: 1, height: 22, color: p.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
          FolioIconButton(
            icon: Icons.rotate_left_rounded,
            tooltip: 'Rotate left',
            onPressed: _busy ? null : () => _rotate(sel, clockwise: false),
          ),
          FolioIconButton(
            icon: Icons.rotate_right_rounded,
            tooltip: 'Rotate right',
            onPressed: _busy ? null : () => _rotate(sel, clockwise: true),
          ),
          FolioIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            onPressed: _busy ? null : () => _delete(sel),
          ),
          FolioIconButton(
            icon: Icons.call_split_rounded,
            tooltip: PdfSaver.canChooseSaveLocation ? 'Save selected as new PDF' : 'Share selected as new PDF',
            onPressed: _busy ? null : _extractSelected,
          ),
        ],
      ),
    );
  }

  Widget _buildTile(int index) {
    final p = context.pal;
    final item = _items[index];
    final selected = _selected.contains(item.uid);
    final rotatedBy = (item.rotation.index - item.page.rotation.index + 4) % 4 * 90;
    final hovered = _hoverUid == item.uid && _dragUid != item.uid;

    Widget card({bool floating = false}) => Container(
          decoration: BoxDecoration(
            gradient: selected ? null : p.cardGradient,
            color: selected ? p.accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(Dim.rMd),
            border: Border.all(
              color: hovered ? p.accent : (selected ? p.accent : p.border),
              width: selected || hovered ? 2 : 1,
            ),
            boxShadow: floating ? p.softShadow : null,
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: PdfPageView(
                        key: ValueKey('org_${item.uid}_${item.rotation.index}'),
                        document: item.doc,
                        pageNumber: item.pageNumber,
                        rotationOverride: item.rotation,
                        maximumDpi: 80,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(gradient: p.accentGradient, shape: BoxShape.circle),
                          child: Icon(Icons.check_rounded, size: 17, color: p.onAccent),
                        ),
                      ),
                    if (item.fromOtherFile)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Tooltip(
                          message: 'From ${item.sourceName}, page ${item.pageNumber}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(gradient: p.accentGradient, borderRadius: BorderRadius.circular(8)),
                            child: Text('ADDED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: p.onAccent, letterSpacing: 0.6)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rotatedBy == 0 ? 'Page ${index + 1}' : 'Page ${index + 1} · $rotatedBy°',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      tooltip: 'More',
                      padding: EdgeInsets.zero,
                      enabled: !_busy,
                      icon: Icon(Icons.more_horiz_rounded, size: 20, color: p.textSecondary),
                      onSelected: (v) {
                        switch (v) {
                          case 'left':
                            _rotate({item.uid}, clockwise: false);
                          case 'right':
                            _rotate({item.uid}, clockwise: true);
                          case 'dup':
                            _duplicate(item);
                          case 'first':
                            _moveTo(item.uid, 0);
                          case 'last':
                            _moveTo(item.uid, _items.length - 1);
                          case 'delete':
                            _delete({item.uid});
                        }
                      },
                      itemBuilder: (context) => [
                        _menuItem('right', Icons.rotate_right_rounded, 'Rotate right'),
                        _menuItem('left', Icons.rotate_left_rounded, 'Rotate left'),
                        _menuItem('dup', Icons.copy_rounded, 'Duplicate'),
                        _menuItem('first', Icons.vertical_align_top_rounded, 'Move to start'),
                        _menuItem('last', Icons.vertical_align_bottom_rounded, 'Move to end'),
                        const PopupMenuDivider(),
                        _menuItem('delete', Icons.delete_outline_rounded, 'Delete', danger: true),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final tile = Pressable(
      key: ValueKey('tap_${item.uid}'),
      onTap: () => _toggleSelect(item.uid),
      scale: 0.97,
      child: card(),
    );

    // Touch: press and hold to pick a page up. Mouse: drag straight away.
    final feedbackSize = MediaQuery.sizeOf(context).width < 500 ? 140.0 : 160.0;
    final draggable = _dragFor(
      uid: item.uid,
      feedback: SizedBox(
        width: feedbackSize,
        height: feedbackSize / 0.66,
        child: Material(color: Colors.transparent, child: Opacity(opacity: 0.92, child: card(floating: true))),
      ),
      child: tile,
      ghost: Opacity(opacity: 0.35, child: card()),
    );

    return DragTarget<int>(
      key: ValueKey(item.uid),
      onWillAcceptWithDetails: (d) {
        if (d.data == item.uid) return false;
        setState(() => _hoverUid = item.uid);
        return true;
      },
      onLeave: (_) {
        if (_hoverUid == item.uid) setState(() => _hoverUid = null);
      },
      onAcceptWithDetails: (d) {
        _moveTo(d.data, index);
        setState(() => _hoverUid = null);
      },
      builder: (context, _, _) => draggable,
    );
  }

  Widget _dragFor({
    required int uid,
    required Widget feedback,
    required Widget child,
    required Widget ghost,
  }) {
    void onStart() {
      setState(() => _dragUid = uid);
      _startAutoScroll();
    }

    if (Platform.isWindows) {
      return Draggable<int>(
        data: uid,
        feedback: feedback,
        childWhenDragging: ghost,
        onDragStarted: onStart,
        onDragEnd: (_) => _stopDrag(),
        child: child,
      );
    }
    return LongPressDraggable<int>(
      data: uid,
      feedback: feedback,
      childWhenDragging: ghost,
      hapticFeedbackOnStart: true,
      delay: const Duration(milliseconds: 220),
      onDragStarted: onStart,
      onDragEnd: (_) => _stopDrag(),
      child: child,
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {bool danger = false}) {
    final p = context.pal;
    final color = danger ? p.danger : p.textPrimary;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: danger ? p.danger : p.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
