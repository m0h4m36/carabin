import 'package:flutter/material.dart';

/// Couleurs de sens (juste, partiel, faux, passé) : toujours accompagnées
/// d'une icône ou d'un mot, jamais la seule information.
@immutable
class StatusColors {
  const StatusColors._({
    required this.right,
    required this.partial,
    required this.wrong,
    required this.skipped,
  });

  final Color right;
  final Color partial;
  final Color wrong;
  final Color skipped;

  static const _light = StatusColors._(
    right: Color(0xFF2E7D32),
    partial: Color(0xFFB26A00),
    wrong: Color(0xFFC62828),
    skipped: Color(0xFF6B7280),
  );

  static const _dark = StatusColors._(
    right: Color(0xFF81C784),
    partial: Color(0xFFFFB74D),
    wrong: Color(0xFFEF9A9A),
    skipped: Color(0xFF9CA3AF),
  );

  static StatusColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}
