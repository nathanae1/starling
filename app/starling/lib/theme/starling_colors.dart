import 'package:flutter/material.dart';

class StarlingColors {
  const StarlingColors({
    required this.paper,
    required this.linen,
    required this.hairline,
    required this.stone,
    required this.graphite,
    required this.ink,
    required this.sage,
    required this.sageDeep,
    required this.sageSoft,
    required this.clay,
    required this.clayDeep,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadowInk,
  });

  final Color paper;
  final Color linen;
  final Color hairline;
  final Color stone;
  final Color graphite;
  final Color ink;

  final Color sage;
  final Color sageDeep;
  final Color sageSoft;

  final Color clay;
  final Color clayDeep;

  final Color success;
  // Pick by intent, not interchangeably: [warning] (clay) for caution /
  // attention states (e.g. "Probing"), [danger] (deeper clay) for destructive
  // or error states (e.g. failed sends, delete/clear actions).
  final Color warning;
  final Color danger;

  final Color shadowInk;

  static const StarlingColors light = StarlingColors(
    paper: Color(0xFFF5F0E6),
    linen: Color(0xFFEDE6D6),
    hairline: Color(0xFFE1D8C3),
    stone: Color(0xFFA09684),
    graphite: Color(0xFF6B6559),
    ink: Color(0xFF2E2A24),
    sage: Color(0xFF7A8B6F),
    sageDeep: Color(0xFF5C6C52),
    sageSoft: Color(0xFFDCE3D3),
    clay: Color(0xFFC96F4A),
    clayDeep: Color(0xFFA6513A),
    success: Color(0xFF6B8762),
    warning: Color(0xFFC96F4A),
    danger: Color(0xFFA6513A),
    shadowInk: Color(0xFF2E2A24),
  );

  List<BoxShadow> get shadowSoft => [
    BoxShadow(
      color: shadowInk.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];

  List<BoxShadow> get shadowLift => [
    BoxShadow(
      color: shadowInk.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 4),
    ),
  ];
}
