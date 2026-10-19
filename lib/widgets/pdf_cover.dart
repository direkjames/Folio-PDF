import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme.dart';

/// First-page preview of a PDF file, like a book cover.
class PdfCover extends StatelessWidget {
  const PdfCover({required this.path, this.missing = false, this.radius = 12, super.key});

  final String path;
  final bool missing;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget placeholder(IconData icon) => ColoredBox(
          color: p.surfaceHigh,
          child: Center(child: Icon(icon, color: p.textSecondary.withValues(alpha: 0.6), size: 28)),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.isDark ? 0.5 : 0.12), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: missing
            ? placeholder(Icons.link_off_rounded)
            : PdfDocumentViewBuilder.file(
                path,
                // Password-protected files can't be previewed without asking, so show a lock.
                passwordProvider: () => null,
                firstAttemptByEmptyPassword: true,
                loadingBuilder: (_) => placeholder(Icons.picture_as_pdf_rounded),
                errorBuilder: (_, _, _) => placeholder(Icons.lock_outline_rounded),
                builder: (context, document) {
                  if (document == null || document.pages.isEmpty) return placeholder(Icons.picture_as_pdf_rounded);
                  return ColoredBox(
                    color: Colors.white,
                    child: PdfPageView(
                      document: document,
                      pageNumber: 1,
                      maximumDpi: 110,
                      alignment: Alignment.topCenter,
                      decoration: const BoxDecoration(color: Colors.white),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
