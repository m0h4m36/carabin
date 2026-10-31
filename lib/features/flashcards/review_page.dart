import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/flashcards_repository.dart';
import '../../domain/note_types.dart';
import '../../domain/scheduling.dart';
import '../../domain/study_options.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';
import '../../ui/widgets.dart';
import 'card_text.dart';
import 'occlusion_view.dart';
import 'note_editor_page.dart';
import 'review_session.dart';

/// Une séance de révision : les cartes du jour d'un ou plusieurs decks, ou une
/// liste de cartes imposée (entraînement).
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.deckIds, this.cardIds, this.order});

  final List<int>? deckIds;
  final List<int>? cardIds;
  final StudyOrder? order;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late ReviewSession _session;
  final _stopwatch = Stopwatch();
  final _typed = TextEditingController();
  final _typedFocus = FocusNode();
  final _rootFocus = FocusNode(debugLabel: 'révision');
  bool _revealed = false;
  bool _showContext = false;
  int _everReviewed = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _session = ReviewSession(
      context.read<FlashcardsRepository>(),
      deckIds: widget.deckIds,
      cardIds: widget.cardIds,
      order: widget.order,
    );
    _resetCardState();
  }

  void _resetCardState() {
    _revealed = false;
    _showContext = false;
    _typed.clear();
    _stopwatch
      ..reset()
      ..start();
  }

  @override
  void dispose() {
    _typed.dispose();
    _typedFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  FlashcardsRepository get _repo => context.read<FlashcardsRepository>();

  // -------------------------------------------------------------- actions

  void _reveal() {
    if (_session.finished) return;
    setState(() => _revealed = true);
    _typedFocus.unfocus();
    _rootFocus.requestFocus();
  }

  void _toggleReveal() {
    if (_session.finished) return;
    if (_revealed) {
      setState(() => _revealed = false);
    } else {
      _reveal();
    }
  }

  void _grade(Grade g) {
    if (_session.finished || !_revealed) return;
    final ms = _stopwatch.elapsedMilliseconds;
    final result = _session.answer(g, durationMs: ms);
    _everReviewed++;
    setState(_resetCardState);
    if (result.becameLeech) {
      final suspended = _repo.card(result.undo.cardId).suspended;
      showInfo(
        context,
        suspended ? TxCards.leechNotice : TxCards.leechNoticeKept,
      );
    }
  }

  void _undo() {
    if (_session.undo()) {
      setState(_resetCardState);
      showInfo(context, TxCards.undone);
    } else {
      showInfo(context, TxCards.nothingToUndo);
    }
  }

  void _suspend() {
    if (_session.finished) return;
    _session.suspendCurrent();
    setState(_resetCardState);
    showInfo(context, TxCards.suspendedNotice);
  }

  void _bury() {
    if (_session.finished) return;
    _session.buryCurrent();
    setState(_resetCardState);
    showInfo(context, TxCards.buried);
  }

  Future<void> _delete() async {
    if (_session.finished) return;
    final ok = await confirm(
      context,
      title: TxCards.deleteCard,
      message: TxCards.deleteCardAsk,
      confirmLabel: Tx.delete,
      destructive: true,
    );
    if (!ok || !mounted || _session.finished) return;
    _session.deleteCurrent();
    setState(_resetCardState);
    showInfo(context, TxCards.cardDeleted);
  }

  Future<void> _addNote() async {
    final c = _session.current;
    final deckId = c == null
        ? widget.deckIds?.firstOrNull
        : _repo.studyCard(c).note.deckId;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => NoteEditorPage(deckId: deckId)),
    );
    _rootFocus.requestFocus();
  }

  void _restart() => setState(() {
    _start();
  });

  // ---------------------------------------------------------------- clavier

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx?.findAncestorWidgetOfExactType<EditableText>() != null ||
        ctx?.widget is EditableText;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final typing = _typing;

    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      _undo();
      return KeyEventResult.handled;
    }
    if (ctrl &&
        (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace)) {
      _delete();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (typing && _revealed) return KeyEventResult.ignored;
      _toggleReveal();
      return KeyEventResult.handled;
    }
    if (typing) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.space) {
      _toggleReveal();
      return KeyEventResult.handled;
    }
    final grade = switch (k) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => Grade.again,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => Grade.hard,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => Grade.good,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => Grade.easy,
      _ => null,
    };
    if (grade != null) {
      _grade(grade);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyH) {
      setState(() => _showContext = !_showContext);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyS) {
      _suspend();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _bury();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------ vue

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(child: _session.finished ? _doneView() : _sessionView()),
              if (wide && !_session.finished) _sidePanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: TxCards.quit,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Center(
              child: Text(
                TxCards.position(
                  _session.position,
                  _session.initialTotal < _session.position
                      ? _session.position
                      : _session.initialTotal,
                ),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: '${TxCards.undo} (Ctrl+Z)',
            icon: const Icon(Icons.undo),
            onPressed: _session.canUndo ? _undo : null,
          ),
          IconButton(
            tooltip: TxCards.addNote,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _addNote,
          ),
          IconButton(
            tooltip: '${TxCards.bury} (−)',
            icon: const Icon(Icons.snooze_outlined),
            onPressed: _bury,
          ),
          IconButton(
            tooltip: '${TxCards.suspend} (S)',
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: _suspend,
          ),
          IconButton(
            tooltip: '${TxCards.deleteCard} (Ctrl+Suppr)',
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: _delete,
          ),
        ],
      ),
    );
  }

  Widget _pills() {
    final p = _session.pills;
    final kind = _session.currentKind;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Pill(TxCards.pillNew, p.fresh, kind?.fresh ?? false),
        _Pill(TxCards.pillLearning, p.learning, kind?.learning ?? false),
        _Pill(TxCards.pillReview, p.review, kind?.review ?? false),
      ],
    );
  }

  Widget _sessionView() {
    final repo = _repo;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sc = repo.studyCard(_session.current!);
    final face = sc.face;
    final options = repo.effectiveOptions(sc.note.deckId);
    final delays = _revealed ? repo.preview(sc.card.id) : null;

    final meta = StringBuffer(TxCards.typeName(sc.note.type));
    if (options.showPassCounter) {
      meta.write(' · ');
      meta.write(
        sc.card.schedule.reps == 0
            ? TxCards.firstTime()
            : TxCards.seenTimes(sc.card.schedule.reps, sc.card.schedule.lapses),
      );
      if (sc.note.cardCount > 1) {
        meta.write(' · ');
        meta.write(switch (sc.note.type) {
          NoteType.cloze => TxCards.clozeOrdinal(sc.card.ord),
          NoteType.occlusion => TxCards.cardOrdinal(
            repo
                .cardsOfNote(sc.note.id)
                .indexWhere((c) => c.ord == sc.card.ord),
          ),
          _ => TxCards.cardOrdinal(sc.card.ord),
        });
      }
    }

    final contextBlock = <Widget>[
      if (face.context.isNotEmpty)
        if (_showContext)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: RichFieldText(
              face.context,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          TextButton(
            onPressed: () => setState(() => _showContext = true),
            child: const Text(TxCards.showContext),
          ),
    ];
    final extraBlock = <Widget>[
      if (face.extra.isNotEmpty) ...[
        const SizedBox(height: 16),
        RichFieldText(
          face.extra,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    ];

    Widget content;
    if (sc.note.type == NoteType.occlusion) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...contextBlock,
          OcclusionView(
            key: ValueKey('occlusion-${sc.card.id}'),
            fields: sc.note.fields,
            ord: sc.card.ord,
            revealed: _revealed,
          ),
          if (_revealed) ...extraBlock,
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...contextBlock,
          FaceText(face.question),
          if (face.typed) ..._typedBlock(face),
          if (_revealed) ...[
            const SizedBox(height: 20),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 20),
            if (!face.typed) FaceText(face.answer),
            ...extraBlock,
          ],
        ],
      );
    }

    return Column(
      children: [
        _topBar(),
        const SizedBox(height: 8),
        _pills(),
        const SizedBox(height: 12),
        Text(
          meta.toString(),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: content,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _revealed ? _gradeButtons(delays!) : _revealButton(),
          ),
        ),
      ],
    );
  }

  List<Widget> _typedBlock(CardFace face) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!_revealed) {
      return [
        const SizedBox(height: 20),
        TextField(
          controller: _typed,
          focusNode: _typedFocus,
          autofocus: true,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: TxCards.typeYourAnswer,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _reveal(),
        ),
      ];
    }
    final right = typedAnswerMatches(_typed.text, face.expected);
    return [
      const SizedBox(height: 20),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            right ? Icons.check_circle_outline : Icons.highlight_off,
            color: right ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 8),
          Text(
            right ? TxCards.typedRight : TxCards.typedWrong,
            style: theme.textTheme.titleSmall?.copyWith(
              color: right ? scheme.primary : scheme.error,
            ),
          ),
        ],
      ),
      if (_typed.text.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          _typed.text.trim(),
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: right ? null : TextDecoration.lineThrough,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        TxCards.expected,
        style: theme.textTheme.labelMedium?.copyWith(color: scheme.outline),
      ),
      const SizedBox(height: 4),
      FaceText(face.answer),
    ];
  }

  Widget _revealButton() => SizedBox(
    width: double.infinity,
    height: 56,
    child: FilledButton(
      onPressed: _reveal,
      child: const Text(TxCards.showAnswer),
    ),
  );

  Widget _gradeButtons(Map<Grade, Duration> delays) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(Grade g, int key) {
      final label = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TxCards.gradeLabel(g),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(Tx.interval(delays[g]!), style: const TextStyle(fontSize: 12)),
        ],
      );
      void onPressed() => _grade(g);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 64,
            child: g == Grade.good
                ? FilledButton(
                    key: ValueKey('grade-$key'),
                    onPressed: onPressed,
                    child: label,
                  )
                : OutlinedButton(
                    key: ValueKey('grade-$key'),
                    style: g == Grade.again
                        ? OutlinedButton.styleFrom(
                            foregroundColor: scheme.error,
                          )
                        : null,
                    onPressed: onPressed,
                    child: label,
                  ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(Grade.again, 1),
        button(Grade.hard, 2),
        button(Grade.good, 3),
        button(Grade.easy, 4),
      ],
    );
  }

  Widget _sidePanel() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = _repo;
    final sc = repo.studyCard(_session.current!);
    final delays = repo.preview(sc.card.id);
    final secs = _session.answered == 0
        ? null
        : _session.spent.inSeconds / _session.answered;
    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              l,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        t,
        style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
      ),
    );
    return Container(
      width: 260,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          head(TxCards.sessionPanel),
          row(TxCards.reviewed, '${_session.answered}'),
          row(TxCards.remaining, '${_session.remaining}'),
          row(TxCards.minutes, '${_session.spent.inMinutes}'),
          row(
            TxCards.secondsPerCard,
            secs == null ? '–' : secs.toStringAsFixed(1).replaceAll('.', ','),
          ),
          head(TxCards.cardPanel),
          row(TxCards.typeLabel, TxCards.typeName(sc.note.type)),
          row(TxCards.passes, '${sc.card.schedule.reps}'),
          row(TxCards.lapsesLabel, '${sc.card.schedule.lapses}'),
          head(TxCards.nextPanel),
          for (final g in Grade.values)
            row(TxCards.gradeLabel(g), Tx.interval(delays[g]!)),
          head(TxCards.shortcuts),
          Text(
            TxCards.shortcutsLine,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneView() {
    final repo = _repo;
    final next = repo.nextDue(deckIds: widget.deckIds);
    String nextText = TxCards.nothingScheduled;
    if (next != null) {
      final now = repo.now();
      final a = studyDayStart(next.at);
      final b = studyDayStart(now);
      final diff = DateTime.utc(
        a.year,
        a.month,
        a.day,
      ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
      nextText = TxCards.nextReview(
        TxCards.relativeDay(next.at, diff),
        next.count,
      );
    }
    return Column(
      children: [
        _topBarDone(),
        Expanded(
          child: EmptyState(
            icon: Icons.check_circle_outline,
            title: TxCards.done,
            message: '${TxCards.doneSummary(_everReviewed)}\n$nextText',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: _restart,
                  child: const Text(TxCards.reviewAgain),
                ),
                OutlinedButton.icon(
                  onPressed: _session.canUndo ? _undo : null,
                  icon: const Icon(Icons.undo),
                  label: const Text(TxCards.undo),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(TxCards.backToDecks),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBarDone() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: TxCards.quit,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.count, this.active);
  final String label;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '$label $count',
          style: theme.textTheme.bodySmall?.copyWith(
            color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
