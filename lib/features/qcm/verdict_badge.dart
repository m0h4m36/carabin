import 'package:flutter/material.dart';

import '../../domain/qcm/grading.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/status_colors.dart';

/// Couleur et icône d'un verdict (jamais la couleur seule : le mot suit).
(Color, IconData) verdictStyle(BuildContext context, Verdict v) {
  final status = StatusColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  return switch (v) {
    Verdict.right => (status.right, Icons.check_circle_outline),
    Verdict.partial => (status.partial, Icons.timelapse),
    Verdict.wrong => (status.wrong, Icons.cancel_outlined),
    Verdict.skipped => (status.skipped, Icons.redo),
    Verdict.pending => (scheme.primary, Icons.rate_review_outlined),
  };
}

/// « Juste · 1 / 1 » : verdict d'une question et points gagnés.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge(this.grade, {super.key});

  final Grade grade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = verdictStyle(context, grade.verdict);
    final points = grade.verdict == Verdict.pending
        ? ''
        : ' · ${TxQcm.scoreOf(grade.score, grade.max)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${TxQcm.verdictName(grade.verdict)}$points',
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
