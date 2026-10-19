import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../design/components.dart';
import '../theme.dart';

/// Find-in-document bar shown under the app bar.
class PdfSearchBar extends StatefulWidget {
  const PdfSearchBar({required this.searcher, required this.onClose, super.key});

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  @override
  State<PdfSearchBar> createState() => _PdfSearchBarState();
}

class _PdfSearchBarState extends State<PdfSearchBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searcher.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    widget.searcher.removeListener(_refresh);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _next() {
    if (widget.searcher.hasMatches) widget.searcher.goToNextMatch();
  }

  void _prev() {
    if (widget.searcher.hasMatches) widget.searcher.goToPrevMatch();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.searcher;
    final count = s.matches.length;
    final String status;
    if (_text.text.isEmpty) {
      status = '';
    } else if (count == 0) {
      status = s.isSearching ? 'Searching…' : 'No results';
    } else {
      status = '${(s.currentIndex ?? 0) + 1} / $count${s.isSearching ? '+' : ''}';
    }

    final p = context.pal;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(22),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true): _prev,
                const SingleActivator(LogicalKeyboardKey.f3): _next,
                const SingleActivator(LogicalKeyboardKey.f3, shift: true): _prev,
              },
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Find in document',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                      onChanged: (value) {
                        s.startTextSearch(value, caseInsensitive: true);
                        setState(() {});
                      },
                      onSubmitted: (_) {
                        _next();
                        _focus.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 56),
                    child: Text(
                      status,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  FolioIconButton(
                    tooltip: 'Previous (Shift+Enter)',
                    onPressed: count > 0 ? _prev : null,
                    icon: Icons.keyboard_arrow_up_rounded,
                  ),
                  FolioIconButton(
                    tooltip: 'Next (Enter)',
                    onPressed: count > 0 ? _next : null,
                    icon: Icons.keyboard_arrow_down_rounded,
                  ),
                  FolioIconButton(
                    tooltip: 'Close (Esc)',
                    onPressed: widget.onClose,
                    icon: Icons.close_rounded,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: s.isSearching ? LinearProgressIndicator(value: s.searchProgress, minHeight: 2) : null,
            ),
          ],
        ),
      ),
    );
  }
}
