import 'package:flutter/material.dart';

import '../../data/qcm_models.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/status_colors.dart';
import '../../ui/widgets.dart';

/// Ce qu'on peut faire d'une série depuis sa carte.
enum ExamAction {
  edit,
  subject,
  pastPaper,
  attach,
  detach,
  duplicate,
  share,
  select,
  delete,
}

/// Une série dans la liste : titre, matière, effectifs, dernière note.
class ExamCard extends StatelessWidget {
  const ExamCard({
    super.key,
    required this.summary,
    required this.onOpen,
    required this.onAction,
    this.subjectName,
    this.subjectColor,
    this.polyTitle,
    this.primaryLabel,
    this.onPrimary,
    this.selecting = false,
    this.selected = false,
  });

  final ExamSummary summary;
  final String? subjectName;
  final Color? subjectColor;

  /// Titre du poly rattaché, s'il y en a un.
  final String? polyTitle;

  /// Appelé par un toucher sur la carte (ouvrir, ou cocher en sélection).
  final VoidCallback onOpen;
  final ValueChanged<ExamAction> onAction;

  /// Bouton principal (« Composer »), s'il y en a un.
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final exam = summary.exam;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final canCompose = summary.ready > 0;
    return Card(
      key: ValueKey('exam-${exam.id}'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        onLongPress: selecting ? null : () => onAction(ExamAction.select),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    key: ValueKey('exam-check-${exam.id}'),
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subjectColor != null) ...[
                              ColorDot(subjectColor!, size: 10),
                              const SizedBox(width: 6),
                            ],
                            Text(subjectName ?? TxQcm.noSubject, style: muted),
                          ],
                        ),
                        Text(
                          exam.imported ? TxQcm.received : TxQcm.handwritten,
                          style: muted,
                        ),
                        if (polyTitle != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.menu_book_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: Text(
                                  polyTitle!,
                                  style: muted,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          TxQcm.questionCount(summary.questions),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (summary.unfinished > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 16,
                                color: status.partial,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                TxQcm.unfinished(summary.unfinished),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: status.partial,
                                ),
                              ),
                            ],
                          ),
                        Text(
                          summary.lastNote == null
                              ? TxQcm.passedTimes(summary.attempts)
                              : '${TxQcm.passedTimes(summary.attempts)} · '
                                    '${TxQcm.lastNoteValue(summary.lastNote!)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    if (primaryLabel != null && !selecting) ...[
                      const SizedBox(height: 10),
                      FilledButton(
                        key: ValueKey('exam-primary-${exam.id}'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: canCompose ? onPrimary : null,
                        child: Text(primaryLabel!),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selecting)
                PopupMenuButton<ExamAction>(
                  key: ValueKey('exam-menu-${exam.id}'),
                  tooltip: Tx.more,
                  onSelected: onAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: ExamAction.edit,
                      child: Text(TxQcm.menuEdit),
                    ),
                    const PopupMenuItem(
                      value: ExamAction.subject,
                      child: Text(TxQcm.menuSubject),
                    ),
                    // Rangée dans les annales à cause de son titre : seul un
                    // renommage l'en sort.
                    if (!exam.isPastPaper || exam.pastPaper)
                      PopupMenuItem(
                        value: ExamAction.pastPaper,
                        child: Text(
                          exam.pastPaper
                              ? TxQcm.menuFromPastPapers
                              : TxQcm.menuToPastPapers,
                        ),
                      ),
                    const PopupMenuItem(
                      value: ExamAction.attach,
                      child: Text(TxQcm.menuAttach),
                    ),
                    if (exam.documentId != null)
                      const PopupMenuItem(
                        value: ExamAction.detach,
                        child: Text(TxQcm.detachPoly),
                      ),
                    const PopupMenuItem(
                      value: ExamAction.duplicate,
                      child: Text(TxQcm.menuDuplicate),
                    ),
                    const PopupMenuItem(
                      value: ExamAction.share,
                      child: Text(TxQcm.menuShare),
                    ),
                    const PopupMenuItem(
                      value: ExamAction.select,
                      child: Text(TxQcm.menuSelect),
                    ),
                    const PopupMenuItem(
                      value: ExamAction.delete,
                      child: Text(TxQcm.menuDelete),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
