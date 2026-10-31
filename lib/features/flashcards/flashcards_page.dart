import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/flashcard_models.dart';
import '../../data/flashcards_repository.dart';
import '../../data/models.dart';
import '../../data/names.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import '../../ui/widgets.dart';
import '../courses/document_viewer_page.dart';
import 'deck_actions.dart';
import 'deck_cards_page.dart';
import 'note_editor_page.dart';
import 'practice_page.dart';
import 'review_page.dart';
import 'study_options_page.dart';

enum _DeckAction {
  newCard,
  seeCards,
  rename,
  subject,
  linkCourse,
  openCourse,
  unlinkCourse,
  settings,
  deadline,
  catchUp,
  delete,
}

/// Accueil des flashcards : compteurs du jour, S'entraîner, liste des decks.
class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage({super.key});

  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  final _search = TextEditingController();
  bool _byCourse = true;
  bool _onlyDue = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _push(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final repo = context.read<FlashcardsRepository>();
    final courses = context.read<CoursesRepository>();
    final theme = Theme.of(context);
    final decks = repo.decks();
    final totals = repo.counts();
    final minutes = ((totals.todayTotal) * repo.averageSecondsPerCard() / 60)
        .round();
    final hard = repo.hardCardCount();
    final subjects = courses.allSubjects();
    final subjectName = {for (final (s, _, _) in subjects) s.id: s.name};
    final q = normalize(_search.text.trim());

    final counts = {for (final d in decks) d.id: repo.counts(deckId: d.id)};
    final visible = [
      for (final d in decks)
        if ((q.isEmpty ||
                normalize(d.name).contains(q) ||
                normalize(subjectName[d.subjectId] ?? '').contains(q)) &&
            (!_onlyDue || counts[d.id]!.todayTotal > 0))
          d,
    ];

    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              _header(repo, decks, totals),
              if (decks.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Counter(
                      key: const ValueKey('counter-today'),
                      label: TxCards.counterToday,
                      value: '${totals.todayTotal}',
                      detail:
                          '${TxCards.todayDetail(totals.due, totals.newToday)}${totals.todayTotal == 0 ? '' : ' · ${TxCards.estimate(minutes)}'}',
                      onTap: totals.todayTotal == 0
                          ? null
                          : () => _push(const ReviewPage()),
                    ),
                    _Counter(
                      label: TxCards.counterWaiting,
                      value: '${totals.newWaiting}',
                    ),
                    _Counter(
                      label: TxCards.counterTotal,
                      value: '${totals.total}',
                    ),
                    _Counter(label: TxCards.counterHard, value: '$hard'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('review-all'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(160, 52),
                      ),
                      onPressed: totals.todayTotal == 0
                          ? null
                          : () => _push(const ReviewPage()),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(TxCards.review),
                    ),
                    const SizedBox(width: 12),
                    if (totals.todayTotal == 0 && totals.total > 0)
                      Expanded(
                        child: Text(
                          TxCards.nothingToDo,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _PracticeBlock(onOpen: () => _push(const PracticePage())),
                const SizedBox(height: 24),
              ],
              if (decks.isEmpty)
                EmptyState(
                  icon: Icons.style_outlined,
                  title: TxCards.noDecks,
                  message: TxCards.noDecksDetail,
                  action: FilledButton.icon(
                    onPressed: () => createDeckDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text(TxCards.newDeck),
                  ),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text(TxCards.allDecks),
                      selected: !_onlyDue,
                      onSelected: (_) => setState(() => _onlyDue = false),
                    ),
                    ChoiceChip(
                      label: Text('${TxCards.dueToday} (${totals.todayTotal})'),
                      selected: _onlyDue,
                      onSelected: (_) => setState(() => _onlyDue = true),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text(TxCards.byCourse),
                        ),
                        ButtonSegment(value: false, label: Text(TxCards.flat)),
                      ],
                      selected: {_byCourse},
                      onSelectionChanged: (s) =>
                          setState(() => _byCourse = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text(TxCards.noDeckMatches)),
                  )
                else if (_byCourse)
                  ..._grouped(visible, counts, subjects)
                else
                  for (final d in visible)
                    _DeckTile(
                      key: ValueKey('deck-${d.id}'),
                      deck: d,
                      counts: counts[d.id]!,
                      subjectName: subjectName[d.subjectId],
                      onAction: (a) => _deckAction(d, a),
                      onReview: () => reviewDeck(context, d),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    FlashcardsRepository repo,
    List<Deck> decks,
    DeckCounts totals,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(TxCards.title, style: theme.textTheme.headlineSmall),
                  Text(
                    TxCards.summary(decks.length, totals.total),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: TxCards.newDeck,
              icon: const Icon(Icons.add),
              onPressed: () => createDeckDialog(context),
            ),
            PopupMenuButton<String>(
              tooltip: TxCards.menu,
              onSelected: (v) {
                switch (v) {
                  case 'new':
                    createDeckDialog(context);
                  case 'settings':
                    _push(const StudyOptionsPage());
                  case 'catchup':
                    catchUp(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text(TxCards.newDeck)),
                PopupMenuItem(
                  value: 'settings',
                  child: Text(TxCards.studySettings),
                ),
                PopupMenuItem(value: 'catchup', child: Text(TxCards.catchUp)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('deck-search'),
          controller: _search,
          decoration: const InputDecoration(
            hintText: TxCards.searchDecks,
            prefixIcon: Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  List<Widget> _grouped(
    List<Deck> visible,
    Map<int, DeckCounts> counts,
    List<(Subject, Semester, Year)> subjects,
  ) {
    final repo = context.read<FlashcardsRepository>();
    final byId = {for (final (s, _, _) in subjects) s.id: s};
    final sections = <int?, List<Deck>>{};
    for (final d in visible) {
      final key = byId.containsKey(d.subjectId) ? d.subjectId : null;
      sections.putIfAbsent(key, () => []).add(d);
    }
    final searching = _search.text.trim().isNotEmpty || _onlyDue;
    final out = <Widget>[];
    for (final (s, _, _) in subjects) {
      final ds = sections[s.id] ?? const <Deck>[];
      if (ds.isEmpty && searching) continue;
      out.add(
        _Section(
          key: ValueKey('section-${s.id}'),
          title: s.name,
          color: colorOf(s.color),
          cardCount: ds.fold<int>(0, (a, d) => a + counts[d.id]!.total),
          onDrop: (deckId) =>
              guarded(context, () => repo.setDeckSubject(deckId, s.id)),
          empty: ds.isEmpty,
          children: [
            for (final d in ds)
              _DeckTile(
                key: ValueKey('deck-${d.id}'),
                deck: d,
                counts: counts[d.id]!,
                subjectName: null,
                draggable: true,
                onAction: (a) => _deckAction(d, a),
                onReview: () => reviewDeck(context, d),
              ),
          ],
        ),
      );
    }
    final none = sections[null];
    if (none != null) {
      out.add(
        _Section(
          key: const ValueKey('section-none'),
          title: TxCards.noSubject,
          color: null,
          cardCount: none.fold<int>(0, (a, d) => a + counts[d.id]!.total),
          onDrop: (deckId) =>
              guarded(context, () => repo.setDeckSubject(deckId, null)),
          empty: false,
          children: [
            for (final d in none)
              _DeckTile(
                key: ValueKey('deck-${d.id}'),
                deck: d,
                counts: counts[d.id]!,
                subjectName: null,
                draggable: true,
                onAction: (a) => _deckAction(d, a),
                onReview: () => reviewDeck(context, d),
              ),
          ],
        ),
      );
    }
    return out;
  }

  Future<void> _deckAction(Deck d, _DeckAction a) async {
    final repo = context.read<FlashcardsRepository>();
    switch (a) {
      case _DeckAction.newCard:
        _push(NoteEditorPage(deckId: d.id));
      case _DeckAction.seeCards:
        _push(DeckCardsPage(deckId: d.id));
      case _DeckAction.rename:
        final name = await promptText(
          context,
          title: Tx.rename,
          label: TxCards.deckName,
          initial: d.name,
        );
        if (name == null || !mounted) return;
        await guarded(context, () => repo.renameDeck(d.id, name));
      case _DeckAction.subject:
        await chooseSubjectFor(context, d);
      case _DeckAction.linkCourse:
        await chooseCourseFor(context, d);
      case _DeckAction.openCourse:
        if (d.documentId != null) {
          _push(DocumentViewerPage(docId: d.documentId!));
        }
      case _DeckAction.unlinkCourse:
        await guarded(context, () => repo.setDeckDocument(d.id, null));
      case _DeckAction.settings:
        _push(StudyOptionsPage(deckId: d.id));
      case _DeckAction.deadline:
        await setDeadline(context, d);
      case _DeckAction.catchUp:
        await catchUp(context, deck: d);
      case _DeckAction.delete:
        await deleteDeckDialog(context, d);
    }
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.onTap,
  });
  final String label;
  final String value;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 150, minHeight: 80),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall),
            if (detail != null)
              Text(
                detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PracticeBlock extends StatelessWidget {
  const _PracticeBlock({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.fitness_center_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(TxCards.practiceTitle, style: theme.textTheme.titleMedium),
                Text(
                  TxCards.practiceDetail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: const ValueKey('open-practice'),
            onPressed: onOpen,
            child: const Text(TxCards.practiceOpen),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.color,
    required this.cardCount,
    required this.children,
    required this.onDrop,
    required this.empty,
  });
  final String title;
  final Color? color;
  final int cardCount;
  final List<Widget> children;
  final ValueChanged<int> onDrop;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: hovering
                ? scheme.primaryContainer.withValues(alpha: 0.4)
                : null,
          ),
          child: empty
              ? ListTile(
                  dense: true,
                  leading: color == null ? null : ColorDot(color!),
                  title: Text(title, style: theme.textTheme.titleSmall),
                  subtitle: const Text(TxCards.emptySubject),
                )
              : ExpansionTile(
                  key: PageStorageKey<String>('flash-section-$title'),
                  initiallyExpanded: true,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  tilePadding: EdgeInsets.zero,
                  leading: color == null ? null : ColorDot(color!),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TxCards.cardCount(cardCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                  children: children,
                ),
        );
      },
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    super.key,
    required this.deck,
    required this.counts,
    required this.subjectName,
    required this.onAction,
    required this.onReview,
    this.draggable = false,
  });

  final Deck deck;
  final DeckCounts counts;
  final String? subjectName;
  final bool draggable;
  final ValueChanged<_DeckAction> onAction;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final courses = context.read<CoursesRepository>();
    final linked = deck.documentId == null
        ? null
        : courses.document(deck.documentId!);

    Widget stat(String label, int n, {bool strong = false}) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n',
            style: theme.textTheme.titleMedium?.copyWith(
              color: strong && n > 0 ? scheme.primary : null,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );

    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          if (draggable)
            Icon(Icons.drag_indicator, size: 20, color: scheme.outline),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subjectName != null)
                    Text(
                      subjectName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  if (linked != null)
                    Text(
                      linked.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
          stat(TxCards.dueShort, counts.due, strong: true),
          stat(TxCards.newShort, counts.newToday),
          stat(TxCards.cardsShort, counts.total),
          FilledButton.tonal(
            key: ValueKey('review-deck-${deck.id}'),
            onPressed: counts.todayTotal == 0 ? null : onReview,
            child: const Text(TxCards.review),
          ),
          PopupMenuButton<_DeckAction>(
            key: ValueKey('menu-deck-${deck.id}'),
            tooltip: TxCards.menu,
            onSelected: onAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _DeckAction.newCard,
                child: Text(TxCards.newCard),
              ),
              const PopupMenuItem(
                value: _DeckAction.seeCards,
                child: Text(TxCards.seeCards),
              ),
              const PopupMenuItem(
                value: _DeckAction.rename,
                child: Text(Tx.rename),
              ),
              const PopupMenuItem(
                value: _DeckAction.subject,
                child: Text(TxCards.changeSubject),
              ),
              const PopupMenuItem(
                value: _DeckAction.linkCourse,
                child: Text(TxCards.linkCourse),
              ),
              if (linked != null) ...[
                const PopupMenuItem(
                  value: _DeckAction.openCourse,
                  child: Text(Tx.open),
                ),
                const PopupMenuItem(
                  value: _DeckAction.unlinkCourse,
                  child: Text(TxCards.unlinkCourse),
                ),
              ],
              const PopupMenuItem(
                value: _DeckAction.settings,
                child: Text(TxCards.studySettings),
              ),
              const PopupMenuItem(
                value: _DeckAction.deadline,
                child: Text(TxCards.deadline),
              ),
              const PopupMenuItem(
                value: _DeckAction.catchUp,
                child: Text(TxCards.catchUp),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _DeckAction.delete,
                child: Text(TxCards.deleteDeck),
              ),
            ],
          ),
        ],
      ),
    );

    if (!draggable) return tile;
    return LongPressDraggable<int>(
      data: deck.id,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Opacity(opacity: 0.9, child: tile),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}
