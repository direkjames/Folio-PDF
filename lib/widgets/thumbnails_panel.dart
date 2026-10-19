import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/settings.dart';
import '../design/components.dart';
import '../theme.dart';
import 'reading_filter.dart';

/// Vertical list of page thumbnails. Tapping one jumps to that page.
class ThumbnailsPanel extends StatefulWidget {
  const ThumbnailsPanel({
    required this.documentRef,
    required this.currentPage,
    required this.onPageSelected,
    required this.mode,
    super.key,
  });

  final PdfDocumentRef documentRef;
  final int currentPage;
  final ValueChanged<int> onPageSelected;
  final ReadingMode mode;

  @override
  State<ThumbnailsPanel> createState() => _ThumbnailsPanelState();
}

class _ThumbnailsPanelState extends State<ThumbnailsPanel> {
  static const _itemExtent = 214.0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent(animate: false));
  }

  @override
  void didUpdateWidget(covariant ThumbnailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) _revealCurrent();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current page's thumbnail in view as the user scrolls the document.
  void _revealCurrent({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final top = (widget.currentPage - 1) * _itemExtent;
    final bottom = top + _itemExtent;
    if (top >= pos.pixels && bottom <= pos.pixels + pos.viewportDimension) return;
    final target = (top - pos.viewportDimension / 2 + _itemExtent / 2).clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ColoredBox(
      color: p.surface,
      child: PdfDocumentViewBuilder(
        documentRef: widget.documentRef,
        builder: (context, document) {
          if (document == null) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          return ListView.builder(
            controller: _scroll,
            itemExtent: _itemExtent,
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: document.pages.length,
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              final selected = pageNumber == widget.currentPage;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Pressable(
                  onTap: () => widget.onPageSelected(pageNumber),
                  scale: 0.96,
                  child: Column(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: Dim.normal,
                          curve: Dim.curve,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: selected ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
                            border: Border.all(color: selected ? p.accent : Colors.transparent, width: 2),
                          ),
                          child: ReadingFilter(
                            mode: widget.mode,
                            child: PdfPageView(
                              key: ValueKey('thumb_${document.hashCode}_$index'),
                              document: document,
                              pageNumber: pageNumber,
                              maximumDpi: 72,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: ReadingFilter.preFilter(Colors.black.withValues(alpha: 0.35), widget.mode),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$pageNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? p.accentText : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
