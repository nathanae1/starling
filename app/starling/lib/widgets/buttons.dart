import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

enum _Variant { primary, secondary, ghost, accent }

class _StarlingButton extends StatelessWidget {
  const _StarlingButton({
    required this.variant,
    required this.onPressed,
    required this.child,
    this.block = false,
    this.padding,
  });

  final _Variant variant;
  final VoidCallback? onPressed;
  final Widget child;
  final bool block;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    final disabled = onPressed == null;

    final bg = switch (variant) {
      _Variant.primary => colors.sage,
      _Variant.secondary => colors.paper,
      _Variant.ghost => Colors.transparent,
      _Variant.accent => colors.clay,
    };
    final fg = switch (variant) {
      _Variant.primary => const Color(0xFFFDFBF5),
      _Variant.secondary => colors.ink,
      _Variant.ghost => colors.sageDeep,
      _Variant.accent => const Color(0xFFFDFBF5),
    };
    final border = variant == _Variant.secondary ? colors.hairline : null;

    final effectivePadding =
        padding ??
        (block
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 12));

    final textStyle =
        (block ? starling.typography.buttonBlock : starling.typography.button)
            .copyWith(color: fg, fontWeight: FontWeight.w500);

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          splashColor: colors.sageSoft.withValues(alpha: 0.3),
          highlightColor: colors.linen,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: border != null ? Border.all(color: border) : null,
            ),
            constraints: block
                ? const BoxConstraints(minWidth: double.infinity)
                : null,
            padding: effectivePadding,
            alignment: Alignment.center,
            child: DefaultTextStyle(
              style: textStyle,
              child: IconTheme(
                data: IconThemeData(color: fg, size: 18),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.block = false,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool block;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return _StarlingButton(
      variant: _Variant.primary,
      onPressed: onPressed,
      block: block,
      child: _labelWithOptionalIcon(leading, label),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.block = false,
    this.leading,
    this.padding,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool block;
  final Widget? leading;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return _StarlingButton(
      variant: _Variant.secondary,
      onPressed: onPressed,
      block: block,
      padding: padding,
      child: _labelWithOptionalIcon(leading, label),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.padding,
  });

  final String label;
  final VoidCallback? onPressed;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return _StarlingButton(
      variant: _Variant.ghost,
      onPressed: onPressed,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(label),
    );
  }
}

class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.block = false,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool block;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return _StarlingButton(
      variant: _Variant.accent,
      onPressed: onPressed,
      block: block,
      child: _labelWithOptionalIcon(leading, label),
    );
  }
}

class StarlingIconButton extends StatelessWidget {
  const StarlingIconButton({
    super.key,
    required this.child,
    this.onPressed,
    this.size = 44,
    this.semanticLabel,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double size;

  /// Screen-reader label for this icon-only control. Without it, an icon
  /// button announces nothing meaningful. Falls back to [tooltip].
  final String? semanticLabel;

  /// Long-press / hover tooltip. Also used as the semantic label when
  /// [semanticLabel] is not given.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    Widget result = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        splashColor: starling.colors.sageSoft.withValues(alpha: 0.3),
        highlightColor: starling.colors.hairline,
        hoverColor: starling.colors.linen,
        child: SizedBox(
          width: size,
          height: size,
          child: IconTheme(
            data: IconThemeData(color: starling.colors.ink, size: 20),
            child: Center(child: child),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      result = Tooltip(message: tooltip!, child: result);
    }
    final label = semanticLabel ?? tooltip;
    if (label != null) {
      result = Semantics(button: true, label: label, child: result);
    }
    return result;
  }
}

Widget _labelWithOptionalIcon(Widget? leading, String label) {
  if (leading == null) return Text(label);
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [leading, const SizedBox(width: 8), Text(label)],
  );
}
