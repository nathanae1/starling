import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

class StarlingInput extends StatelessWidget {
  const StarlingInput({
    super.key,
    this.controller,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction,
    this.style,
    this.padding,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final EdgeInsets? padding;

  /// Hard character cap enforced on input. The built-in counter is
  /// suppressed (like [StarlingTextarea]); callers render their own where
  /// a count matters.
  final int? maxLength;

  /// Line behavior — defaults to a single line; pass e.g. `maxLines: 4,
  /// minLines: 1` for a growing multiline field (comment input).
  final int? maxLines;
  final int? minLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final textStyle = style ?? starling.typography.body;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      autofocus: autofocus,
      textInputAction: textInputAction,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      textCapitalization: textCapitalization,
      buildCounter: maxLength == null
          ? null
          : (
              _, {
              required currentLength,
              required maxLength,
              required isFocused,
            }) => null,
      cursorColor: starling.colors.sage,
      style: textStyle,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: starling.colors.paper,
        hintText: placeholder,
        hintStyle: textStyle.copyWith(color: starling.colors.stone),
        contentPadding:
            padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: starling.colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: starling.colors.sage, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: starling.colors.hairline),
        ),
      ),
    );
  }
}

class StarlingTextarea extends StatelessWidget {
  const StarlingTextarea({
    super.key,
    this.controller,
    this.placeholder,
    this.onChanged,
    this.minLines = 4,
    this.maxLines = 8,
    this.maxLength,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;

  /// Hard character cap enforced on input (counts grapheme clusters, matching
  /// `String.characters.length`). Callers that render their own counter should
  /// pass this so the field and the counter agree; the built-in counter is
  /// suppressed to avoid a duplicate.
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      buildCounter:
          (
            _, {
            required currentLength,
            required maxLength,
            required isFocused,
          }) => null,
      cursorColor: starling.colors.sage,
      style: starling.typography.body,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: starling.colors.paper,
        hintText: placeholder,
        hintStyle: starling.typography.body.copyWith(
          color: starling.colors.stone,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: starling.colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: starling.colors.sage, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: starling.colors.hairline),
        ),
      ),
    );
  }
}

class StarlingFieldLabel extends StatelessWidget {
  const StarlingFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Text(text, style: starling.typography.label);
  }
}
