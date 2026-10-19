import 'package:material_ui/material_ui.dart';

import '../services/settings.dart';

/// Tints PDF pages for comfortable reading: sepia for warm paper, dark for
/// night reading (white paper becomes black).
///
/// Uses a color matrix instead of BlendMode.difference to avoid a Flutter
/// rendering bug that draws a grey diagonal line on some Android devices.
class ReadingFilter extends StatelessWidget {
  const ReadingFilter({required this.mode, required this.child, super.key});

  final ReadingMode mode;
  final Widget child;

  static const _invert = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  // Multiplies the page by a warm paper tone, so white becomes cream and
  // black text stays black.
  static const _sepia = ColorFilter.matrix(<double>[
    0.96, 0, 0, 0, 0, //
    0, 0.89, 0, 0, 0, //
    0, 0, 0.74, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  static const _identity = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    // Keep the same widget tree in every mode so the viewer is not rebuilt
    // (and does not lose its scroll position) when switching.
    return ColorFiltered(
      colorFilter: switch (mode) {
        ReadingMode.dark => _invert,
        ReadingMode.sepia => _sepia,
        ReadingMode.normal => _identity,
      },
      child: child,
    );
  }

  /// Returns the color that will *appear* as [c] after the filter.
  /// Used for things drawn inside the filtered area (search highlights, scroll thumb).
  static Color preFilter(Color c, ReadingMode mode) {
    if (mode != ReadingMode.dark) return c;
    return Color.fromARGB(
      (c.a * 255).round(),
      255 - (c.r * 255).round(),
      255 - (c.g * 255).round(),
      255 - (c.b * 255).round(),
    );
  }
}
