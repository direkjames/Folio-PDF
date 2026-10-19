import 'package:material_ui/material_ui.dart';

/// Colors for one brightness. Reach it with `context.pal`.
@immutable
class FolioPalette extends ThemeExtension<FolioPalette> {
  const FolioPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentDeep,
    required this.accentText,
    required this.onAccent,
    required this.viewerBackdrop,
    required this.glass,
    required this.danger,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// Warm gold used for fills (buttons, selection).
  final Color accent;
  final Color accentDeep;

  /// Gold that stays readable as text/icon color on [surface].
  final Color accentText;
  final Color onAccent;
  final Color viewerBackdrop;

  /// Translucent fill of frosted-glass bars.
  final Color glass;
  final Color danger;

  bool get isDark => brightness == Brightness.dark;

  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accentDeep],
      );

  /// Subtle top-lit gradient for cards.
  LinearGradient get cardGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(surface, textPrimary, isDark ? 0.045 : 0.0)!, surface],
      );

  List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  List<BoxShadow> get glow => [
        BoxShadow(color: accent.withValues(alpha: isDark ? 0.28 : 0.35), blurRadius: 22, offset: const Offset(0, 6)),
      ];

  static const dark = FolioPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0C0C0F),
    surface: Color(0xFF16161B),
    surfaceHigh: Color(0xFF202027),
    border: Color(0xFF2B2B34),
    textPrimary: Color(0xFFF4F1EA),
    textSecondary: Color(0xFF9D9BA6),
    accent: Color(0xFFEBC265),
    accentDeep: Color(0xFFC99A33),
    accentText: Color(0xFFEBC265),
    onAccent: Color(0xFF1D1500),
    viewerBackdrop: Color(0xFF07070A),
    glass: Color(0xCC16161B),
    danger: Color(0xFFFF7A70),
  );

  static const light = FolioPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6F3EC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFEBE0),
    border: Color(0xFFE1DCCE),
    textPrimary: Color(0xFF1B1A17),
    textSecondary: Color(0xFF6B675D),
    accent: Color(0xFFE3B74F),
    accentDeep: Color(0xFFC2922A),
    accentText: Color(0xFF8E6710),
    onAccent: Color(0xFF1D1500),
    viewerBackdrop: Color(0xFFE6E2D6),
    glass: Color(0xD9FFFFFF),
    danger: Color(0xFFC8372D),
  );

  @override
  FolioPalette copyWith() => this;

  @override
  FolioPalette lerp(ThemeExtension<FolioPalette>? other, double t) {
    if (other is! FolioPalette) return this;
    // Both palettes are fixed sets of colors, so switch halfway through the theme animation.
    return t < 0.5 ? this : other;
  }
}

extension FolioPaletteContext on BuildContext {
  FolioPalette get pal => Theme.of(this).extension<FolioPalette>() ?? FolioPalette.dark;
}

/// Spacing, radii and motion shared by every screen.
class Dim {
  static const rSm = 10.0;
  static const rMd = 16.0;
  static const rLg = 22.0;
  static const rXl = 28.0;

  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);
  static const curve = Curves.easeOutCubic;

  /// Width at which the layout switches from phone to desktop style.
  static const wide = 760.0;
}

class FolioFonts {
  static const ui = 'Inter';
  static const display = 'Fraunces';
}
