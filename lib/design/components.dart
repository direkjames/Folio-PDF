import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'palette.dart';

/// Wraps [child] so it gently scales down while pressed or hovered-and-pressed.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.borderRadius,
    this.scale = 0.97,
    this.haptic = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final BorderRadius? borderRadius;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        onSecondaryTap: widget.onSecondaryTap,
        child: AnimatedScale(
          scale: _down ? widget.scale : (_hover && enabled ? 1.012 : 1),
          duration: Dim.fast,
          curve: Dim.curve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Frosted-glass panel: blurs whatever is behind it.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.border = true,
    this.blur = 22,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool border;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.glass,
            borderRadius: borderRadius,
            border: border ? Border.all(color: p.border.withValues(alpha: 0.8)) : null,
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

/// The primary call-to-action: gold gradient with a soft glow.
class GoldButton extends StatelessWidget {
  const GoldButton({required this.label, required this.onPressed, this.icon, this.compact = false, super.key});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Pressable(
        onTap: onPressed,
        haptic: true,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24, vertical: compact ? 10 : 15),
          decoration: BoxDecoration(
            gradient: p.accentGradient,
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            boxShadow: enabled && !compact ? p.glow : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: p.onAccent), const SizedBox(width: 8)],
              Text(
                label,
                style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700, fontSize: compact ? 14 : 15.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon button with a soft hover/active background. Gold when [active].
class FolioIconButton extends StatelessWidget {
  const FolioIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 22,
    this.badge = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  /// Small gold dot in the corner (used for "unsaved changes").
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onPressed != null;
    final color = !enabled ? p.textSecondary.withValues(alpha: 0.4) : (active ? p.accentText : p.textPrimary);
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onPressed,
        scale: 0.9,
        child: AnimatedContainer(
          duration: Dim.fast,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: size, color: color),
              if (badge)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.surface, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded square with a tinted icon.
class IconTile extends StatelessWidget {
  const IconTile({required this.icon, this.size = 40, this.filled = false, super.key});

  final IconData icon;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: filled ? p.accentGradient : null,
        color: filled ? null : p.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: filled ? p.onAccent : p.accentText),
    );
  }
}

/// A surface card with a hairline border and soft shadow.
class FolioCard extends StatelessWidget {
  const FolioCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
    this.radius = Dim.rLg,
    this.shadow = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final card = AnimatedContainer(
      duration: Dim.normal,
      curve: Dim.curve,
      padding: padding,
      decoration: BoxDecoration(
        gradient: selected ? null : p.cardGradient,
        color: selected ? p.accent.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: selected ? p.accent : p.border, width: selected ? 1.5 : 1),
        boxShadow: shadow ? p.softShadow : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.98, child: card);
  }
}

/// "Folio" wordmark in the display serif.
class FolioWordmark extends StatelessWidget {
  const FolioWordmark({this.size = 26, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Folio',
      style: TextStyle(
        fontFamily: FolioFonts.display,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: context.pal.textPrimary,
      ),
    );
  }
}

/// App logo mark: gold rounded square with a page glyph.
class FolioMark extends StatelessWidget {
  const FolioMark({this.size = 40, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: p.accentGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: p.glow,
      ),
      child: Icon(Icons.auto_stories_rounded, size: size * 0.52, color: p.onAccent),
    );
  }
}

/// Small uppercase label above a group.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.trailing, super.key});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: context.pal.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Shows a styled floating message. Replaces any message already showing.
void showToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final p = context.pal;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: actionLabel == null ? 3 : 6),
        content: Row(
          children: [
            Icon(icon, size: 20, color: p.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}

/// One row in an action sheet.
class SheetAction<T> {
  const SheetAction({required this.value, required this.icon, required this.label, this.enabled = true});
  final T value;
  final IconData icon;
  final String label;
  final bool enabled;
}

/// Bottom sheet of actions (phones). Returns the chosen value.
Future<T?> showActionSheet<T>(BuildContext context, List<List<SheetAction<T>>> groups, {String? title}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final p = context.pal;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              for (var g = 0; g < groups.length; g++) ...[
                if (g > 0) Divider(color: p.border, height: 16),
                for (final a in groups[g])
                  ListTile(
                    enabled: a.enabled,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: Icon(a.icon, color: a.enabled ? p.textPrimary : p.textSecondary),
                    title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                    onTap: () => Navigator.pop(context, a.value),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Phone-style centered empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, required this.message, this.action, super.key});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent.withValues(alpha: 0.10),
              border: Border.all(color: p.accent.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 40, color: p.accentText),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FolioFonts.display,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, height: 1.45),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}
