import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/errors.dart';
import '../../data/flashcard_models.dart';
import '../../data/flashcards_repository.dart';
import '../../domain/note_types.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';
import '../../ui/widgets.dart';
import 'card_text.dart';
import 'occlusion_view.dart';
import 'note_editor_page.dart';

/// Les notes d'un deck : recherche, aperçu, pause, modification, suppression.
class DeckCardsPage extends StatefulWidget {
  const DeckCardsPage({super.key, required this.deckId});
  final int deckId;

  @override
  State<DeckCardsPage> createState() => _DeckCardsPageState();
}

class _DeckCardsPageState extends State<DeckCardsPage> {
  final _search = TextEditingController();
  final Set<int> _selected = {};
  int? _open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  FlashcardsRepository get _repo => context.read<FlashcardsRepository>();

  Future<void> _newCard() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => NoteEditorPage(deckId: widget.deckId)),
  );

  Future<void> _edit(int noteId) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NoteEditorPage(deckId: widget.deckId, noteId: noteId),
    ),
  );

  Future<void> _deleteNotes(List<NoteRow> notes) async {
    final cards = notes.fold<int>(0, (a, n) => a + n.cardCount);
    final ok = await confirm(
      context,
      title: TxCards.deleteNote,
      message: notes.length == 1
          ? TxCards.deleteNoteAsk(cards)
          : TxCards.deleteManyAsk(notes.length),
      confirmLabel: Tx.delete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await guarded(context, () {
      for (final n in notes) {
        _repo.deleteNote(n.id);
      }
    });
    setState(() {
      _selected.removeAll(notes.map((n) => n.id));
      if (notes.any((n) => n.id == _open)) _open = null;
    });
  }

  Future<void> _moveNotes(List<NoteRow> notes) async {
    final decks = [
      for (final d in _repo.decks())
        if (d.id != widget.deckId) d,
    ];
    final target = await pickFromList<int>(
      context,
      title: TxCards.moveNotes,
      choices: [for (final d in decks) Choice(d.id, d.name)],
    );
    if (target == null || !mounted) return;
    await guarded(context, () {
      for (final n in notes) {
        _repo.moveNote(n.id, target);
      }
    });
    setState(() {
      _selected.removeAll(notes.map((n) => n.id));
      if (notes.any((n) => n.id == _open)) _open = null;
    });
  }

  void _suspend(List<NoteRow> notes, bool value) {
    for (final n in notes) {
      _repo.setNoteSuspended(n.id, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final Deck deck;
    try {
      deck = _repo.deck(widget.deckId);
    } on NotFoundError {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    final all = _repo.notes(widget.deckId);
    final query = _search.text;
    final notes = query.trim().isEmpty
        ? all
        : _repo.notes(widget.deckId, query: query);
    final cardTotal = all.fold<int>(0, (a, n) => a + n.cardCount);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    NoteRow? open;
    for (final n in all) {
      if (n.id == _open) open = n;
    }
    final selectedNotes = [
      for (final n in all)
        if (_selected.contains(n.id)) n,
    ];

    final list = notes.isEmpty
        ? EmptyState(
            icon: Icons.style_outlined,
            title: all.isEmpty ? TxCards.noNotes : TxCards.noNoteMatches,
            action: all.isEmpty
                ? FilledButton.icon(
                    onPressed: _newCard,
                    icon: const Icon(Icons.add),
                    label: const Text(TxCards.newCard),
                  )
                : null,
          )
        : ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, i) {
              final n = notes[i];
              final preview = n.preview.trim().isEmpty
                  ? TxCards.occlusionNote
                  : n.preview;
              return ListTile(
                key: ValueKey('note-${n.id}'),
                selected: n.id == _open,
                leading: Checkbox(
                  value: _selected.contains(n.id),
                  onChanged: (v) => setState(() {
                    v == true ? _selected.add(n.id) : _selected.remove(n.id);
                  }),
                ),
                title: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${TxCards.typeName(n.type)} · ${TxCards.cardCount(n.cardCount)}'
                  '${n.tags.isEmpty ? '' : ' · ${n.tags.join(' ')}'}',
                ),
                trailing: n.allSuspended
                    ? const Icon(Icons.pause_circle_outline, size: 20)
                    : null,
                onTap: () {
                  if (wide) {
                    setState(() => _open = n.id);
                  } else {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (sheet) => _NoteDetail(
                        noteId: n.id,
                        onEdit: () {
                          Navigator.pop(sheet);
                          _edit(n.id);
                        },
                        onDelete: (note) async {
                          Navigator.pop(sheet);
                          await _deleteNotes([note]);
                        },
                      ),
                    );
                  }
                },
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(TxCards.deckHeader(deck.name, all.length, cardTotal)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _newCard,
              icon: const Icon(Icons.add),
              label: const Text(TxCards.newCard),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: TxCards.searchNotes,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(TxCards.selected(_selected.length)),
                  TextButton(
                    onPressed: () => setState(
                      () => _selected
                        ..clear()
                        ..addAll(notes.map((n) => n.id)),
                    ),
                    child: const Text(TxCards.selectAll),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text(TxCards.selectNone),
                  ),
                  TextButton.icon(
                    onPressed: () => _suspend(
                      selectedNotes,
                      !selectedNotes.every((n) => n.allSuspended),
                    ),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: Text(
                      selectedNotes.every((n) => n.allSuspended)
                          ? TxCards.resumeSelected
                          : TxCards.pauseSelected,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _moveNotes(selectedNotes),
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: const Text(Tx.moveTo),
                  ),
                  TextButton.icon(
                    onPressed: () => _deleteNotes(selectedNotes),
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      Tx.delete,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (notes.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton(
                  onPressed: () =>
                      setState(() => _selected.addAll(notes.map((n) => n.id))),
                  child: const Text(TxCards.selectAll),
                ),
              ),
            ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      SizedBox(width: 420, child: list),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: open == null
                            ? const EmptyState(
                                icon: Icons.touch_app_outlined,
                                title: TxCards.selectNote,
                              )
                            : _NoteDetail(
                                key: ValueKey('detail-${open.id}'),
                                noteId: open.id,
                                onEdit: () => _edit(open!.id),
                                onDelete: (n) => _deleteNotes([n]),
                              ),
                      ),
                    ],
                  )
                : list,
          ),
        ],
      ),
    );
  }
}

class _NoteDetail extends StatefulWidget {
  const _NoteDetail({
    super.key,
    required this.noteId,
    required this.onEdit,
    required this.onDelete,
  });
  final int noteId;
  final VoidCallback onEdit;
  final ValueChanged<NoteRow> onDelete;

  @override
  State<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends State<_NoteDetail> {
  int? _ord;

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final repo = context.read<FlashcardsRepository>();
    final NoteRow note;
    try {
      note = repo.note(widget.noteId);
    } on NotFoundError {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cards = repo.cardsOfNote(note.id);
    final ords = [for (final c in cards) c.ord];
    final ord = ords.contains(_ord) ? _ord! : (ords.isEmpty ? 0 : ords.first);
    final face = note.type == NoteType.occlusion
        ? null
        : renderFace(note.type, note.fields, ord);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text(TxCards.typeName(note.type))),
              Text(
                TxCards.cardCount(note.cardCount),
                style: theme.textTheme.bodyMedium,
              ),
              if (note.allSuspended) Chip(label: const Text(TxCards.paused)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    repo.setNoteSuspended(note.id, !note.allSuspended),
                icon: Icon(
                  note.allSuspended
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                ),
                label: Text(note.allSuspended ? TxCards.resume : TxCards.pause),
              ),
              OutlinedButton.icon(
                onPressed: widget.onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text(TxCards.edit),
              ),
              IconButton(
                tooltip: TxCards.deleteNote,
                onPressed: () => widget.onDelete(note),
                icon: Icon(Icons.delete_outline, color: scheme.error),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (face == null) ...[
            Text(
              TxCards.previewQuestion,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            OcclusionView(
              fields: note.fields,
              ord: ord,
              revealed: false,
              maxHeight: 300,
            ),
            const Divider(height: 28),
            Text(
              TxCards.previewAnswer,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            OcclusionView(
              fields: note.fields,
              ord: ord,
              revealed: true,
              maxHeight: 300,
            ),
            if (note.fields.extra.isNotEmpty) ...[
              const SizedBox(height: 12),
              RichFieldText(
                note.fields.extra,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ] else ...[
            Text(
              TxCards.previewQuestion,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            FaceText(
              face.question,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodyLarge,
            ),
            const Divider(height: 28),
            Text(
              TxCards.previewAnswer,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            FaceText(
              face.answer,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodyLarge,
            ),
            if (face.extra.isNotEmpty) ...[
              const SizedBox(height: 12),
              RichFieldText(
                face.extra,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (face.context.isNotEmpty) ...[
              const SizedBox(height: 12),
              RichFieldText(
                face.context,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
          if (cards.length > 1) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < cards.length; i++)
                  ChoiceChip(
                    label: Text(
                      note.type == NoteType.cloze
                          ? TxCards.clozeOrdinal(cards[i].ord)
                          : TxCards.cardOrdinal(
                              note.type == NoteType.occlusion
                                  ? i
                                  : cards[i].ord,
                            ),
                    ),
                    selected: cards[i].ord == ord,
                    onSelected: (_) => setState(() => _ord = cards[i].ord),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
