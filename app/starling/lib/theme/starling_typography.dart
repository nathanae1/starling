import 'package:flutter/material.dart';

import 'starling_colors.dart';

class StarlingTypography {
  const StarlingTypography({required this.colors});

  final StarlingColors colors;

  static const String fontDisplay = 'Fraunces';
  static const String fontUi = 'IBMPlexSans';
  static const String fontMono = 'IBMPlexMono';

  TextStyle get display => TextStyle(
    fontFamily: fontDisplay,
    fontSize: 48,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.96,
    color: colors.ink,
  );

  TextStyle get displayLarge => TextStyle(
    fontFamily: fontDisplay,
    fontSize: 38,
    fontWeight: FontWeight.w500,
    height: 1.08,
    letterSpacing: -0.76,
    color: colors.ink,
  );

  TextStyle get h1 => TextStyle(
    fontFamily: fontDisplay,
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.48,
    color: colors.ink,
  );

  TextStyle get h2 => TextStyle(
    fontFamily: fontDisplay,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: -0.24,
    color: colors.ink,
  );

  TextStyle get h3 => TextStyle(
    fontFamily: fontUi,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: colors.ink,
  );

  TextStyle get body => TextStyle(
    fontFamily: fontUi,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: colors.ink,
  );

  TextStyle get small => TextStyle(
    fontFamily: fontUi,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: colors.graphite,
  );

  TextStyle get caption => TextStyle(
    fontFamily: fontUi,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.13,
    color: colors.graphite,
  );

  TextStyle get micro => TextStyle(
    fontFamily: fontUi,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.24,
    color: colors.stone,
  );

  TextStyle get mono => TextStyle(
    fontFamily: fontMono,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: colors.ink,
  );

  TextStyle get monoSmall => TextStyle(
    fontFamily: fontMono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: colors.stone,
  );

  TextStyle get quote => TextStyle(
    fontFamily: fontDisplay,
    fontSize: 24,
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: colors.graphite,
  );

  TextStyle get label => TextStyle(
    fontFamily: fontUi,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.24,
    color: colors.graphite,
  );

  TextStyle get button => TextStyle(
    fontFamily: fontUi,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: colors.ink,
  );

  TextStyle get buttonBlock => TextStyle(
    fontFamily: fontUi,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: colors.ink,
  );
}
