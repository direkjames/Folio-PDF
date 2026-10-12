import 'package:material_ui/material_ui.dart';

/// Inverts page colors for night reading (white paper becomes black).
///
/// Uses a color matrix instead of BlendMode.difference to avoid a Flutter
/// rendering bug that draws a grey diagonal line on some Android devices.
class ReadingFilter extends StatelessWidget {
  const ReadingFilter({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  static const _invert = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
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
    // Keep the same widget tree in both modes so the viewer is not rebuilt
    // (and does not lose its scroll position) when toggling.
    return ColorFiltered(colorFilter: enabled ? _invert : _identity, child: child);
  }

  /// Returns the color that will *appear* as [c] after inversion.
  /// Used for things drawn inside the inverted area (search highlights, scroll thumb).
  static Color preInvert(Color c, bool enabled) {
    if (!enabled) return c;
    return Color.fromARGB(
      (c.a * 255).round(),
      255 - (c.r * 255).round(),
      255 - (c.g * 255).round(),
      255 - (c.b * 255).round(),
    );
  }
}
