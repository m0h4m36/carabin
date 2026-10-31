import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/errors.dart';
import '../../data/qcm_models.dart';
import '../../data/qcm_repository.dart';
import '../../domain/qcm/exam.dart';
import '../../domain/qcm/grading.dart';
import '../../domain/qcm/plain_text.dart';
import '../../domain/qcm/question.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/status_colors.dart';
import 'article_view.dart';
import 'passage_flows.dart';
import 'question_view.dart';
import 'verdict_badge.dart';

/// Une copie rendue : note, résultats par question, auto-évaluation des QROC
/// et façons de recommencer.
class AttemptPage extends StatefulWidget {
  const AttemptPage({super.key, required this.attemptId});

  final int attemptId;

  @override
  State<AttemptPage> createState() => _AttemptPageState();
}

class _AttemptPageState extends State<AttemptPage> {
  /// 0 : toutes les questions, 1 : celles à reprendre.
  int _tab = 0;
  final Set<int> _open = {};
  final Map<int, GlobalKey> _keys = {};

  QcmRepository get _repo => context.read<QcmRepository>();

  GlobalKey _keyOf(int answerId) =>
      _keys.putIfAbsent(answerId, () => GlobalKey());

  /// Déplie une question et y amène la vue.
  void _reveal(AnswerRow row) {
    setState(() {
      _tab = _tab == 1 && !_toReview(row) ? 0 : _tab;
      _open.add(row.id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyOf(row.id).currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.05,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  void _toggle(AnswerRow row) => setState(() {
    if (!_open.remove(row.id)) _open.add(row.id);
  });

  static bool _toReview(AnswerRow a) => a.verdict != Verdict.right || a.doubt;

  Future<void> _selfEvaluate(AnswerRow row, double value) async {
    await guarded(context, () => _repo.setSelfScore(row.id, value));
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: TxQcm.copyDeleteTitle,
      message: TxQcm.copyDeleteMessage,
      confirmLabel: TxQcm.copyDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    final done = await guarded(
      context,
      () => _repo.deleteAttempt(widget.attemptId),
    );
    if (done && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final AttemptDetail detail;
    try {
      detail = _repo.attempt(widget.attemptId);
    } on NotFoundError {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text(TxQcm.copyUnavailable)),
      );
    }
    final a = detail.attempt;
    final answers = detail.answers;
    final totals = detail.totals;
    final missed = [
      for (final r in answers)
        if (r.verdict != Verdict.right) r,
    ];

    final summary = _Summary(attempt: a, totals: totals);
    final actions = _Actions(
      missed: missed.length,
      onRedo: () => replayAttempt(context, detail, onlyMissed: true),
      onReplay: () => replayAttempt(context, detail, onlyMissed: false),
      onAnother: () => startNextExam(context, except: a.examId),
      practice: a.practice,
    );
    final dots = Wrap(
      key: const ValueKey('attempt-dots'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in answers)
          _Dot(row: r, number: r.position + 1, onTap: () => _reveal(r)),
      ],
    );
    final details = _Details(
      answers: answers,
      scoring: a.settings.scoring,
      tab: _tab,
      onTab: (t) => setState(() => _tab = t),
      open: _open,
      keyOf: _keyOf,
      onToggle: _toggle,
      onSelfEvaluate: _selfEvaluate,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<int>(
            key: const ValueKey('attempt-menu'),
            onSelected: (_) => _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 0,
                child: Text(TxQcm.copyDelete, key: ValueKey('attempt-delete')),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        const SizedBox(height: 16),
                        actions,
                        const SizedBox(height: 16),
                        dots,
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('attempt-scroll'),
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: details,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            key: const ValueKey('attempt-scroll'),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    const SizedBox(height: 16),
                    actions,
                    const SizedBox(height: 16),
                    dots,
                    const SizedBox(height: 24),
                    details,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ résumé

class _Summary extends StatelessWidget {
  const _Summary({required this.attempt, required this.totals});

  final AttemptRow attempt;
  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final part = attempt.part;
    final tags = <String>[
      TxQcm.dateTime(attempt.startedAt),
      if (attempt.handwritten) TxQcm.handwritten,
      if (attempt.practice)
        part == null ? TxQcm.copyPractice : TxQcm.copyPartOf(part),
    ];
    Widget tile(String key, String label, int n, Color color) =>
        _Tile(tileKey: ValueKey(key), label: label, value: '$n', color: color);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  TxQcm.formatNumber(attempt.note),
                  key: const ValueKey('attempt-note'),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(' / 20', style: theme.textTheme.titleLarge),
                const Spacer(),
                Flexible(
                  child: Text(
                    TxQcm.pointsOutOf(attempt.score, attempt.max),
                    key: const ValueKey('attempt-points'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: attempt.max <= 0
                    ? 0
                    : (attempt.score / attempt.max).clamp(0.0, 1.0),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tags.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                tile('tile-right', TxQcm.copyRight, totals.right, status.right),
                tile(
                  'tile-partial',
                  TxQcm.copyPartial,
                  totals.partial,
                  status.partial,
                ),
                tile('tile-wrong', TxQcm.copyWrong, totals.wrong, status.wrong),
                tile(
                  'tile-skipped',
                  TxQcm.copySkipped,
                  totals.skipped,
                  status.skipped,
                ),
                if (totals.pending > 0)
                  tile(
                    'tile-pending',
                    TxQcm.copyPending,
                    totals.pending,
                    theme.colorScheme.primary,
                  ),
                _Tile(
                  tileKey: const ValueKey('tile-duration'),
                  label: TxQcm.copyDuration,
                  value: TxQcm.durationLabel(attempt.duration),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (attempt.timedOut) ...[
              const SizedBox(height: 12),
              _Notice(
                key: const ValueKey('timed-out'),
                icon: Icons.alarm,
                text: TxQcm.copyTimedOut,
                color: status.wrong,
              ),
            ],
            if (totals.pending > 0) ...[
              const SizedBox(height: 12),
              _Notice(
                key: const ValueKey('pending-note'),
                icon: Icons.rate_review_outlined,
                text: TxQcm.copyPendingNote(totals.pending),
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tileKey,
    required this.label,
    required this.value,
    required this.color,
  });

  final Key tileKey;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: tileKey,
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- actions

class _Actions extends StatelessWidget {
  const _Actions({
    required this.missed,
    required this.onRedo,
    required this.onReplay,
    required this.onAnother,
    required this.practice,
  });

  final int missed;
  final VoidCallback onRedo;
  final VoidCallback onReplay;
  final VoidCallback onAnother;
  final bool practice;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const ValueKey('redo-missed'),
          onPressed: missed == 0 ? null : onRedo,
          icon: const Icon(Icons.replay),
          label: Text(
            missed == 0
                ? TxQcm.copyRedoMissed
                : '${TxQcm.copyRedoMissed} · $missed',
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('replay'),
          onPressed: onReplay,
          icon: const Icon(Icons.restart_alt),
          label: Text(practice ? TxQcm.copyReplayPractice : TxQcm.copyReplay),
        ),
        OutlinedButton.icon(
          key: const ValueKey('another-exam'),
          onPressed: onAnother,
          icon: const Icon(Icons.skip_next_outlined),
          label: const Text(TxQcm.copyAnother),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- pastilles

class _Dot extends StatelessWidget {
  const _Dot({required this.row, required this.number, required this.onTap});

  final AnswerRow row;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = verdictStyle(context, row.verdict);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: TxQcm.copyQuestionLine(number, row.verdict, row.score, row.max),
      child: InkWell(
        key: ValueKey('attempt-dot-${row.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$number',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(icon, size: 12, color: color),
                ],
              ),
              if (row.doubt)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(Icons.flag, size: 12, color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ détail

class _Details extends StatelessWidget {
  const _Details({
    required this.answers,
    required this.scoring,
    required this.tab,
    required this.onTab,
    required this.open,
    required this.keyOf,
    required this.onToggle,
    required this.onSelfEvaluate,
  });

  final List<AnswerRow> answers;
  final Scoring scoring;
  final int tab;
  final ValueChanged<int> onTab;
  final Set<int> open;
  final GlobalKey Function(int answerId) keyOf;
  final ValueChanged<AnswerRow> onToggle;
  final Future<void> Function(AnswerRow row, double value) onSelfEvaluate;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final r in answers)
        if (tab == 0 || _AttemptPageState._toReview(r)) r,
    ];
    final children = <Widget>[];
    var lastGroup = -2;
    for (final r in shown) {
      final info = r.info;
      if (info != null && r.caseGroup >= 0 && r.caseGroup != lastGroup) {
        children.add(
          _CaseHeader(info: info, index: r.caseGroup + 1, anchor: r.id),
        );
      }
      lastGroup = info != null ? r.caseGroup : -2;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _AnswerCard(
            key: keyOf(r.id),
            row: r,
            number: r.position + 1,
            scoring: scoring,
            expanded: open.contains(r.id),
            onToggle: () => onToggle(r),
            onSelfEvaluate: (v) => onSelfEvaluate(r, v),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            key: const ValueKey('attempt-tabs'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 44)),
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text(TxQcm.copyAll)),
              ButtonSegment(value: 1, label: Text(TxQcm.copyReview)),
            ],
            selected: {tab},
            onSelectionChanged: (s) => onTab(s.first),
          ),
        ),
        const SizedBox(height: 12),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              TxQcm.copyNothingToReview,
              key: ValueKey('nothing-to-review'),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...children,
      ],
    );
  }
}

class _CaseHeader extends StatelessWidget {
  const _CaseHeader({
    required this.info,
    required this.index,
    required this.anchor,
  });

  final CaseInfo info;
  final int index;
  final int anchor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = TxQcm.caseName(info, index);
    final hasContext = info.context.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Card(
        key: ValueKey('case-header-$anchor'),
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerLow,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(name, style: theme.textTheme.titleSmall),
          subtitle: hasContext ? const Text(TxQcm.copyCaseContext) : null,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasContext) QcmText(info.context),
            if (info.genre == CaseGenre.lca && info.hasArticle)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ArticlePage(info: info, title: name),
                    ),
                  ),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text(TxQcm.caseOpenArticle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    super.key,
    required this.row,
    required this.number,
    required this.scoring,
    required this.expanded,
    required this.onToggle,
    required this.onSelfEvaluate,
  });

  final AnswerRow row;
  final int number;
  final Scoring scoring;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<double> onSelfEvaluate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = row.question;
    final grade = Grade(row.score, row.max, row.verdict);
    final selfEvaluable =
        q is QrocQuestion && !q.autoGraded && row.answer is TextAnswer;
    return Card(
      key: ValueKey('answer-${row.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('answer-head-${row.id}'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text('$number', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snippet(q.body, max: 140),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            TxQcm.kindBadge(q),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (row.doubt)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.flag,
                          size: 18,
                          color: StatusColors.of(context).partial,
                        ),
                      ),
                    VerdictBadge(grade),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: QuestionView(
                question: q,
                order: row.order,
                answer: row.answer,
                reveal: true,
                scoring: scoring,
                onSelfEvaluate: selfEvaluable ? onSelfEvaluate : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
