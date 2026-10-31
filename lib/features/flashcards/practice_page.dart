import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/flashcard_models.dart';
import '../../data/flashcards_repository.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import '../../ui/widgets.dart';
import 'card_text.dart';
import 'review_page.dart';

enum _Mode { review, test }

/// « S'entraîner » : plusieurs decks à la suite, pour réviser (les cartes sont
/// reprogrammées) ou pour se tester (une note sur 20, rien n'est reprogrammé).
class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final Set<int> _checked = {};
  _Mode _mode = _Mode.review;
  int? _count = 20; // null = tout
  bool _custom = false;
  final _customCount = TextEditingController(text: '30');
  bool _mixed = true;

  @override
  void dispose() {
    _customCount.dispose();
    _tabs.dispose();
    super.dispose();
  }

  FlashcardsRepository get _repo => context.read<FlashcardsRepository>();

  int? _effectiveCount() {
    if (!_custom) return _count;
    final n = int.tryParse(_customCount.text.trim());
    return n == null || n < 1 ? null : n;
  }

  Future<void> _start() async {
    final repo = _repo;
    final ids = repo.drawCards(
      _checked.toList(),
      count: _effectiveCount(),
      shuffled: _mixed,
    );
    if (ids.isEmpty) {
      showInfo(context, TxCards.nothingToDraw);
      return;
    }
    final names = [
      for (final d in repo.decks())
        if (_checked.contains(d.id)) d.name,
    ];
    if (_mode == _Mode.review) {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => ReviewPage(cardIds: ids)));
    } else {
      final history = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SelfTestPage(
            cardIds: ids,
            deckNames: names,
            redraw: () => repo.drawCards(
              _checked.toList(),
              count: _effectiveCount(),
              shuffled: _mixed,
            ),
          ),
        ),
      );
      if (history == true && mounted) _tabs.animateTo(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final canStart = _checked.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text(TxCards.practiceTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: TxCards.practiceNew),
            Tab(text: TxCards.practiceHistory),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: canStart ? _start : null,
              child: Text(
                _mode == _Mode.review ? TxCards.startReview : TxCards.startTest,
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_newSession(), const _History()],
      ),
    );
  }

  Widget _newSession() {
    final repo = _repo;
    final courses = context.read<CoursesRepository>();
    final decks = repo.decks();
    if (decks.isEmpty) {
      return const EmptyState(
        icon: Icons.style_outlined,
        title: TxCards.noDecks,
        message: TxCards.noDecksDetail,
      );
    }
    final subjects = {for (final (s, _, _) in courses.allSubjects()) s.id: s};
    final groups = <int?, List<Deck>>{};
    for (final d in decks) {
      final key = subjects.containsKey(d.subjectId) ? d.subjectId : null;
      groups.putIfAbsent(key, () => []).add(d);
    }
    final keys = [
      ...subjects.keys.where(groups.containsKey),
      if (groups.containsKey(null)) null,
    ];
    final theme = Theme.of(context);

    Widget settings() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TxCards.practiceMode, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.review, label: Text(TxCards.modeReview)),
            ButtonSegment(value: _Mode.test, label: Text(TxCards.modeTest)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 6),
        Text(
          _mode == _Mode.review
              ? TxCards.modeReviewDetail
              : TxCards.modeTestDetail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(TxCards.practiceCount, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in const [20, 50, 100])
              ChoiceChip(
                label: Text('$n'),
                selected: !_custom && _count == n,
                onSelected: (_) => setState(() {
                  _custom = false;
                  _count = n;
                }),
              ),
            ChoiceChip(
              label: const Text(TxCards.countAll),
              selected: !_custom && _count == null,
              onSelected: (_) => setState(() {
                _custom = false;
                _count = null;
              }),
            ),
            ChoiceChip(
              label: const Text(TxCards.countCustom),
              selected: _custom,
              onSelected: (_) => setState(() => _custom = true),
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _customCount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(TxCards.practiceOrder, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text(TxCards.orderMixed)),
            ButtonSegment(value: false, label: Text(TxCards.orderInCourse)),
          ],
          selected: {_mixed},
          onSelectionChanged: (s) => setState(() => _mixed = s.first),
        ),
      ],
    );

    Widget list() => ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        Wrap(
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _checked.addAll(decks.map((d) => d.id))),
              child: const Text(TxCards.selectAll),
            ),
            TextButton(
              onPressed: () => setState(_checked.clear),
              child: const Text(TxCards.selectNone),
            ),
          ],
        ),
        for (final key in keys) ...[
          _SubjectHeader(
            title: key == null ? TxCards.noSubject : subjects[key]!.name,
            color: key == null ? null : colorOf(subjects[key]!.color),
            state: _groupState(groups[key]!),
            onChanged: (v) => setState(() {
              for (final d in groups[key]!) {
                v ? _checked.add(d.id) : _checked.remove(d.id);
              }
            }),
          ),
          for (final d in groups[key]!)
            CheckboxListTile(
              key: ValueKey('practice-deck-${d.id}'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(left: 24, right: 8),
              title: Text(d.name),
              secondary: Text(
                TxCards.cardCount(repo.counts(deckId: d.id).total),
              ),
              value: _checked.contains(d.id),
              onChanged: (v) => setState(() {
                v == true ? _checked.add(d.id) : _checked.remove(d.id);
              }),
            ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 820) {
          return Row(
            children: [
              Expanded(child: list()),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: settings(),
                ),
              ),
            ],
          );
        }
        return ListView(
          children: [
            SizedBox(height: 360, child: list()),
            const Divider(),
            Padding(padding: const EdgeInsets.all(16), child: settings()),
            if (_checked.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(TxCards.pickAtLeastOne),
              ),
          ],
        );
      },
    );
  }

  bool? _groupState(List<Deck> ds) {
    final n = ds.where((d) => _checked.contains(d.id)).length;
    if (n == 0) return false;
    if (n == ds.length) return true;
    return null;
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({
    required this.title,
    required this.color,
    required this.state,
    required this.onChanged,
  });
  final String title;
  final Color? color;
  final bool? state;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    controlAffinity: ListTileControlAffinity.leading,
    tristate: true,
    value: state,
    onChanged: (v) => onChanged(v == true),
    title: Row(
      children: [
        if (color != null) ...[ColorDot(color!), const SizedBox(width: 8)],
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final repo = context.read<FlashcardsRepository>();
    final rows = repo.practiceHistory();
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: TxCards.noPractice,
        message: TxCards.noPracticeDetail,
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final r = rows[i];
        final at = DateTime.fromMillisecondsSinceEpoch(r.takenAtMs);
        final date =
            '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year}'
            ' ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        return ListTile(
          leading: SizedBox(
            width: 72,
            child: Text(
              TxCards.testScore(r.score20),
              style: theme.textTheme.titleMedium,
            ),
          ),
          title: Text('${r.correct} / ${r.total} · $date'),
          subtitle: Text(
            '${TxCards.duration(Duration(milliseconds: r.durationMs))} · ${r.deckNames}',
          ),
          trailing: IconButton(
            tooltip: TxCards.deletePractice,
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () => repo.deletePractice(r.id),
          ),
        );
      },
    );
  }
}

/// « Se tester » : je savais / je ne savais pas, note sur 20 à la fin.
class SelfTestPage extends StatefulWidget {
  const SelfTestPage({
    super.key,
    required this.cardIds,
    required this.deckNames,
    required this.redraw,
  });

  final List<int> cardIds;
  final List<String> deckNames;

  /// Nouveau tirage (« Refaire un tirage »).
  final List<int> Function() redraw;

  @override
  State<SelfTestPage> createState() => _SelfTestPageState();
}

class _SelfTestPageState extends State<SelfTestPage> {
  late List<int> _ids = widget.cardIds;
  int _index = 0;
  int _right = 0;
  bool _revealed = false;
  bool _saved = false;
  final _watch = Stopwatch()..start();
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _finished => _index >= _ids.length;

  void _answer(bool knew) {
    if (_finished || !_revealed) return;
    setState(() {
      if (knew) _right++;
      _index++;
      _revealed = false;
    });
    if (_finished) _save();
  }

  void _save() {
    if (_saved) return;
    _saved = true;
    _watch.stop();
    context.read<FlashcardsRepository>().recordPractice(
      total: _ids.length,
      correct: _right,
      durationMs: _watch.elapsedMilliseconds,
      deckNames: widget.deckNames,
    );
  }

  void _redo() {
    final ids = widget.redraw();
    if (ids.isEmpty) {
      showInfo(context, TxCards.nothingToDraw);
      return;
    }
    setState(() {
      _ids = ids;
      _index = 0;
      _right = 0;
      _revealed = false;
      _saved = false;
      _watch
        ..reset()
        ..start();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (_finished) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      setState(() => _revealed = !_revealed);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _answer(false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyV) {
      _answer(true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _finished
                ? TxCards.modeTest
                : TxCards.testProgress(_index + 1, _ids.length, _right),
          ),
        ),
        body: _finished ? _result() : _card(),
      ),
    );
  }

  Widget _card() {
    final repo = context.read<FlashcardsRepository>();
    final theme = Theme.of(context);
    final sc = repo.studyCard(_ids[_index]);
    final face = sc.face;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaceText(face.question),
                    if (_revealed) ...[
                      const SizedBox(height: 20),
                      Divider(color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 20),
                      FaceText(face.answer),
                      if (face.extra.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        RichFieldText(
                          face.extra,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _revealed
                ? Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              key: const ValueKey('test-no'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                              ),
                              onPressed: () => _answer(false),
                              child: const Text('${TxCards.didntKnow} (F)'),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(
                              key: const ValueKey('test-yes'),
                              onPressed: () => _answer(true),
                              child: const Text('${TxCards.knew} (V)'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      key: const ValueKey('test-reveal'),
                      onPressed: () => setState(() => _revealed = true),
                      child: const Text(TxCards.showAnswer),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _result() {
    final theme = Theme.of(context);
    final total = _ids.length;
    final score = total == 0 ? 0.0 : (_right / total * 40).round() / 2;
    final percent = total == 0 ? 0 : (_right * 100 / total).round();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                TxCards.testScore(score),
                style: theme.textTheme.displaySmall,
                key: const ValueKey('test-score'),
              ),
              const SizedBox(height: 4),
              Text(
                TxCards.appreciation(score),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(TxCards.testRight(_right, total, percent)),
              const SizedBox(height: 12),
              Text(
                TxCards.nothingReprogrammed,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: _redo,
                    child: const Text(TxCards.redraw),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(TxCards.seeHistory),
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
