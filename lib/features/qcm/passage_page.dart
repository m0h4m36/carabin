import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/qcm_models.dart';
import '../../data/qcm_repository.dart';
import '../../domain/qcm/exam.dart';
import '../../domain/qcm/grading.dart';
import '../../domain/qcm/passage.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/status_colors.dart';
import 'article_view.dart';
import 'attempt_page.dart';
import 'question_view.dart';
import 'verdict_badge.dart';

/// Tailles de texte proposées pendant un passage.
const passageZooms = [1.0, 1.2, 1.4, 1.7];

/// Passage d'une épreuve : une question à la fois, panneau des questions,
/// minuteur, correction à la fin ou après chaque question. À la fin, la copie
/// est enregistrée et sa page s'ouvre.
class PassagePage extends StatefulWidget {
  const PassagePage({
    super.key,
    required this.plan,
    required this.settings,
    required this.title,
    this.examId,
    this.practice = false,
    this.handwritten = true,
    this.examTotal,
    this.clock,
  });

  final List<PlannedQuestion> plan;
  final PassageSettings settings;
  final String title;

  /// Épreuve passée, ou null (entraînement sur plusieurs épreuves).
  final int? examId;
  final bool practice;
  final bool handwritten;

  /// Questions prêtes de l'épreuve (pour la part d'un entraînement).
  final int? examTotal;

  /// Horloge, remplaçable par les tests.
  final DateTime Function()? clock;

  @override
  State<PassagePage> createState() => _PassagePageState();
}

class _PassagePageState extends State<PassagePage> {
  late final Passage _passage = Passage(
    widget.plan,
    widget.settings,
    clock: widget.clock,
  );
  final _scroll = ScrollController();
  Timer? _ticker;
  double _zoom = 1.2;
  bool _zoomChosen = false;
  bool _bannerOpen = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.settings.timerMinutes != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  QcmRepository get _repo => context.read<QcmRepository>();

  void _tick() {
    if (!mounted || _saving || _passage.finished) return;
    if (_passage.remaining() == Duration.zero) {
      _passage.expire();
      _save();
      return;
    }
    setState(() {});
  }

  void _scrollTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _open(int i) {
    if (!_passage.canOpen(i)) return;
    setState(() {
      _passage.open(i);
      // Une question validée qu'on rouvre repart de sa réponse : on peut la
      // modifier ou l'effacer.
      if (_passage.status[i] == QStatus.validated &&
          _passage.canEdit(i) &&
          _passage.draft(i) == null) {
        _passage.setDraft(i, _passage.answers[i]);
      }
    });
    _scrollTop();
  }

  int get _current => _passage.current;

  /// Réponse montrée : la validée si elle est figée, sinon celle en cours de
  /// saisie (vide si l'étudiant l'a effacée).
  Answer? _shownAnswer(int i) =>
      _passage.status[i] == QStatus.validated && !_passage.canEdit(i)
      ? _passage.answers[i]
      : _passage.draft(i);

  bool _answerable(Answer? a) => switch (a) {
    null => false,
    ChoiceAnswer c => c.ticked.isNotEmpty,
    TextAnswer t => t.text.trim().isNotEmpty,
    TcsAnswer() => true,
    PointAnswer() => true,
  };

  /// La correction de la question est-elle visible maintenant ?
  bool _reveal(int i) =>
      widget.settings.correction == Correction.each &&
      _passage.status[i] == QStatus.validated;

  void _validate() {
    final a = _passage.draft(_current);
    if (a == null || !_answerable(a) || !_passage.canEdit(_current)) return;
    setState(() => _passage.validate(a));
    if (widget.settings.correction == Correction.end) _next();
  }

  void _skip() {
    if (!_passage.canEdit(_current)) return;
    setState(_passage.skip);
    _next();
  }

  void _next() {
    final t = _passage.nextTarget();
    if (t == null) {
      _endOfQuestions();
      return;
    }
    _open(t);
  }

  /// Plus aucune question à traiter : la copie est rendue, sauf s'il reste des
  /// questions passées qu'on peut encore reprendre.
  Future<void> _endOfQuestions() async {
    final reopenable = [
      for (var i = 0; i < _passage.count; i++)
        if (_passage.status[i] == QStatus.skipped && _passage.canOpen(i)) i,
    ];
    if (reopenable.isEmpty) {
      await _handIn();
      return;
    }
    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(TxQcm.endOfQuestionsTitle),
        content: Text(TxQcm.skippedLeft(reopenable.length)),
        actions: [
          TextButton(
            key: const ValueKey('end-hand-in'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(TxQcm.handIn),
          ),
          FilledButton(
            key: const ValueKey('end-resume'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(TxQcm.resumeSkipped),
          ),
        ],
      ),
    );
    if (!mounted || resume == null) return;
    if (resume) {
      _open(reopenable.first);
    } else {
      await _handIn();
    }
  }

  /// Demande confirmation (s'il reste des questions sans réponse) puis rend
  /// la copie.
  Future<void> _handInWithConfirm() async {
    final open = _passage.count - _passage.validatedCount;
    if (open > 0) {
      final ok = await confirm(
        context,
        title: TxQcm.handInTitle,
        message: TxQcm.handInUnanswered(open),
        confirmLabel: TxQcm.handIn,
      );
      if (!ok || !mounted) return;
    }
    await _handIn();
  }

  Future<void> _handIn() async {
    if (_saving) return;
    _passage.finish();
    await _save();
  }

  Future<void> _confirmLeave() async {
    if (_saving) return;
    final ok = await confirm(
      context,
      title: TxQcm.leaveTitle,
      message: TxQcm.leaveMessage,
      confirmLabel: TxQcm.leaveConfirm,
      destructive: true,
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    _ticker?.cancel();
    final p = _passage;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    final draft = AttemptDraft(
      title: widget.title,
      examId: widget.examId,
      practice: widget.practice,
      handwritten: widget.handwritten,
      settings: p.settings,
      startedAt: p.startedAt,
      duration: p.duration,
      timedOut: p.timedOut,
      examTotal: widget.examTotal,
      answers: [
        for (var i = 0; i < p.count; i++)
          AnswerDraft(
            question: p.plan[i].question,
            grade: p.gradeOf(i),
            info: p.plan[i].info,
            caseGroup: p.plan[i].caseGroup,
            order: p.plan[i].order,
            answer: p.status[i] == QStatus.validated ? p.answers[i] : null,
            doubt: p.doubt[i],
            subjectId: p.plan[i].subjectId,
            topicId: p.plan[i].topicId,
            examId: p.plan[i].examId,
          ),
      ],
    );
    final int id;
    try {
      id = _repo.saveAttempt(draft);
    } on Object {
      _saving = false;
      if (mounted) showInfo(context, TxQcm.savedFailed);
      return;
    }
    if (!mounted) return;
    // Le temps peut finir pendant une boîte de dialogue : on la ferme pour
    // remplacer bien l'écran de passage.
    if (route != null) navigator.popUntil((r) => r == route);
    navigator.pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => AttemptPage(attemptId: id)),
    );
  }

  // ----------------------------------------------------------------- vue

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _passage.remaining();
    final low = remaining != null && remaining < const Duration(minutes: 1);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          // Taille de texte : plus grande par défaut sur grand écran.
          final zoom = _zoomChosen ? _zoom : (wide ? 1.2 : 1.0);
          final status = StatusColors.of(context);
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                key: const ValueKey('passage-close'),
                tooltip: TxQcm.leaveConfirm,
                icon: const Icon(Icons.close),
                onPressed: _confirmLeave,
              ),
              title: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (remaining != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      key: const ValueKey('passage-timer'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          low ? Icons.alarm : Icons.timer_outlined,
                          size: 20,
                          color: low ? status.wrong : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          TxQcm.timerLabel(remaining),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: low ? status.wrong : null,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuButton<double>(
                  key: const ValueKey('passage-zoom'),
                  tooltip: TxQcm.zoom,
                  icon: const Icon(Icons.text_fields),
                  initialValue: zoom,
                  onSelected: (z) => setState(() {
                    _zoom = z;
                    _zoomChosen = true;
                  }),
                  itemBuilder: (_) => [
                    for (final z in passageZooms)
                      CheckedPopupMenuItem(
                        value: z,
                        checked: z == zoom,
                        child: Text(TxQcm.zoomPercent((z * 100).round())),
                      ),
                  ],
                ),
                TextButton(
                  key: const ValueKey('passage-hand-in'),
                  onPressed: _saving ? null : _handInWithConfirm,
                  child: const Text(TxQcm.handIn),
                ),
              ],
            ),
            body: wide
                ? Row(
                    children: [
                      SizedBox(
                        width: 260,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _Panel(
                            passage: _passage,
                            onOpen: _open,
                            wrap: true,
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _main(zoom)),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: 64,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: _Panel(
                            passage: _passage,
                            onOpen: _open,
                            wrap: false,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(child: _main(zoom)),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _main(double zoom) {
    final i = _current;
    final planned = _passage.plan[i];
    final reveal = _reveal(i);
    final editable = _passage.canEdit(i);
    final shown = _shownAnswer(i);
    final validated = _passage.status[i] == QStatus.validated;
    final last = _passage.nextTarget() == null;
    final media = MediaQuery.of(context);
    final scaled = media.copyWith(
      textScaler: TextScaler.linear(media.textScaler.scale(1) * zoom),
    );
    return MediaQuery(
      data: scaled,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('passage-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (planned.info != null) ...[
                        _CaseBanner(
                          passage: _passage,
                          index: i,
                          open: _bannerOpen,
                          onToggle: () =>
                              setState(() => _bannerOpen = !_bannerOpen),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (reveal) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: KeyedSubtree(
                            key: const ValueKey('verdict'),
                            child: VerdictBadge(_passage.gradeOf(i)),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      QuestionView(
                        key: ValueKey('question-view-$i'),
                        question: planned.question,
                        order: planned.order,
                        heading: TxQcm.position(i + 1, _passage.count),
                        answer: shown,
                        reveal: reveal,
                        scoring: widget.settings.scoring,
                        onChanged: (editable && !reveal)
                            ? (a) => setState(() => _passage.setDraft(i, a))
                            : null,
                        onSelfEvaluate: reveal
                            ? (v) => setState(() {
                                final a = _passage.answers[i];
                                if (a is TextAnswer) {
                                  _passage.answers[i] = a.withSelf(v);
                                }
                              })
                            : null,
                        trailing: IconButton(
                          key: const ValueKey('doubt'),
                          tooltip: _passage.doubt[i]
                              ? TxQcm.removeDoubt
                              : TxQcm.doubt,
                          isSelected: _passage.doubt[i],
                          icon: const Icon(Icons.flag_outlined),
                          selectedIcon: Icon(
                            Icons.flag,
                            color: StatusColors.of(context).partial,
                          ),
                          onPressed: () =>
                              setState(() => _passage.toggleDoubt()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (reveal || (validated && !editable))
                    FilledButton(
                      key: const ValueKey('next'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(140, 48),
                      ),
                      onPressed: _next,
                      child: Text(last ? TxQcm.finish : TxQcm.nextQuestion),
                    )
                  else ...[
                    OutlinedButton(
                      key: const ValueKey('skip'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: validated ? _next : _skip,
                      child: Text(validated ? TxQcm.seeNext : TxQcm.skip),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      key: const ValueKey('validate'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(140, 48),
                      ),
                      onPressed:
                          editable && _answerable(_passage.draft(i)) && !_saving
                          ? _validate
                          : null,
                      child: const Text(TxQcm.validate),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- panneau

class _Panel extends StatelessWidget {
  const _Panel({
    required this.passage,
    required this.onOpen,
    required this.wrap,
  });

  final Passage passage;
  final ValueChanged<int> onOpen;

  /// Plusieurs lignes (grand écran) ou une seule rangée qui défile.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final dots = [
      for (var i = 0; i < passage.count; i++)
        _Dot(passage: passage, index: i, onOpen: onOpen),
    ];
    if (!wrap) {
      return Row(
        children: [
          for (final d in dots)
            Padding(padding: const EdgeInsets.only(right: 6), child: d),
        ],
      );
    }
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TxQcm.progress, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          TxQcm.treated(passage.validatedCount, passage.count),
          key: const ValueKey('treated'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: dots),
        const SizedBox(height: 16),
        _Legend(
          icon: Icons.check,
          color: theme.colorScheme.primary,
          label: TxQcm.legendDone,
        ),
        _Legend(
          icon: Icons.redo,
          color: status.partial,
          label: TxQcm.legendSkipped,
        ),
        _Legend(
          icon: Icons.radio_button_unchecked,
          color: theme.colorScheme.outline,
          label: TxQcm.legendTodo,
        ),
        _Legend(
          icon: Icons.flag,
          color: status.partial,
          label: TxQcm.legendDoubt,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.passage,
    required this.index,
    required this.onOpen,
  });

  final Passage passage;
  final int index;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final st = passage.status[index];
    final current = passage.current == index;
    final openable = passage.canOpen(index);
    final doubt = passage.doubt[index];

    final (Color bg, Color fg, IconData? icon, String state) = switch (st) {
      QStatus.validated => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check,
        TxQcm.legendDone,
      ),
      QStatus.skipped => (
        status.partial.withValues(alpha: 0.18),
        scheme.onSurface,
        Icons.redo,
        TxQcm.legendSkipped,
      ),
      QStatus.fresh => (
        Colors.transparent,
        scheme.onSurface,
        null,
        TxQcm.legendTodo,
      ),
    };
    return Semantics(
      button: true,
      selected: current,
      enabled: openable,
      label: TxQcm.dotLabel(index + 1, state, doubt),
      excludeSemantics: true,
      child: Tooltip(
        message: openable ? '' : TxQcm.lockedTooltip,
        child: InkWell(
          key: ValueKey('dot-$index'),
          borderRadius: BorderRadius.circular(8),
          onTap: openable ? () => onOpen(index) : null,
          child: Opacity(
            opacity: openable ? 1 : 0.4,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: current ? scheme.primary : bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: current ? scheme.primary : scheme.outlineVariant,
                  width: current ? 2 : 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: current ? scheme.onPrimary : fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (icon != null)
                        Icon(
                          icon,
                          size: 12,
                          color: current ? scheme.onPrimary : fg,
                        ),
                    ],
                  ),
                  if (doubt)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Icon(
                        Icons.flag,
                        size: 13,
                        color: current ? scheme.onPrimary : status.partial,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ cas

class _CaseBanner extends StatelessWidget {
  const _CaseBanner({
    required this.passage,
    required this.index,
    required this.open,
    required this.onToggle,
  });

  final Passage passage;
  final int index;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planned = passage.plan[index];
    final info = planned.info!;
    final group = planned.caseGroup;
    final members = [
      for (var j = 0; j < passage.count; j++)
        if (passage.plan[j].caseGroup == group) j,
    ];
    final n = members.indexOf(index) + 1;
    final name = TxQcm.caseName(info, group + 1);
    final isArticle = info.genre == CaseGenre.lca;
    final heading = isArticle ? TxQcm.articleBanner(n, members.length) : name;
    return Card(
      key: const ValueKey('case-banner'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(heading, style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  key: const ValueKey('case-toggle'),
                  tooltip: open ? TxQcm.caseHideArticle : TxQcm.caseShowArticle,
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                  onPressed: onToggle,
                ),
              ],
            ),
            if (open) ...[
              if (isArticle && name != heading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(name, style: theme.textTheme.bodyMedium),
                ),
              if (info.context.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: QcmText(info.context),
                ),
              if (isArticle && info.hasArticle)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('open-article'),
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
          ],
        ),
      ),
    );
  }
}
