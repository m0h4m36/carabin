import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/flashcard_models.dart';
import '../../data/flashcards_repository.dart';
import '../../domain/study_options.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import 'review_page.dart';

/// Choix de l'ordre avant une séance d'un deck. Renvoie :
/// `(chosen: false)` si l'utilisateur annule, sinon l'ordre voulu
/// (`null` = comme d'habitude).
Future<({bool chosen, StudyOrder? order})> askOrder(
  BuildContext context,
) async {
  final r = await pickFromList<int>(
    context,
    title: TxCards.orderAsk,
    choices: const [
      Choice(0, TxCards.orderUsual),
      Choice(1, TxCards.orderShuffled),
      Choice(2, TxCards.orderCourse),
    ],
  );
  if (r == null) return (chosen: false, order: null);
  return (
    chosen: true,
    order: switch (r) {
      1 => StudyOrder.shuffled,
      2 => StudyOrder.course,
      _ => null,
    },
  );
}

/// Lance une séance sur un deck (après avoir demandé l'ordre).
Future<void> reviewDeck(BuildContext context, Deck deck) async {
  final order = await askOrder(context);
  if (!order.chosen || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ReviewPage(deckIds: [deck.id], order: order.order),
    ),
  );
}

/// Range un deck dans une matière (ou dans « Sans matière »).
Future<void> chooseSubjectFor(BuildContext context, Deck deck) async {
  final courses = context.read<CoursesRepository>();
  final repo = context.read<FlashcardsRepository>();
  final subjects = courses.allSubjects();
  final r = await pickFromList<int>(
    context,
    title: TxCards.pickSubject,
    choices: [
      const Choice(-1, TxCards.noSubject),
      for (final (s, sem, y) in subjects)
        Choice(
          s.id,
          s.name,
          subtitle: '${y.name} · ${sem.name}',
          color: colorOf(s.color),
        ),
    ],
  );
  if (r == null || !context.mounted) return;
  await guarded(
    context,
    () => repo.setDeckSubject(deck.id, r == -1 ? null : r),
  );
}

/// Associe un poly à un deck (recherche par titre).
Future<void> chooseCourseFor(BuildContext context, Deck deck) async {
  final repo = context.read<FlashcardsRepository>();
  final id = await pickCourse(context);
  if (id == null || !context.mounted) return;
  await guarded(context, () => repo.setDeckDocument(deck.id, id));
}

/// Demande à quel poly rattacher quelque chose (recherche par titre) ;
/// renvoie l'identifiant du document choisi, ou null.
Future<int?> pickCourse(BuildContext context) =>
    showDialog<int>(context: context, builder: (_) => const _CoursePicker());

class _CoursePicker extends StatefulWidget {
  const _CoursePicker();

  @override
  State<_CoursePicker> createState() => _CoursePickerState();
}

class _CoursePickerState extends State<_CoursePicker> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courses = context.read<CoursesRepository>();
    final q = _controller.text.trim();
    final hits = q.isEmpty ? const <DocHit>[] : courses.searchDocuments(q);
    return AlertDialog(
      title: const Text(TxCards.pickCourse),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: TxCards.searchCourse,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: q.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(TxCards.typeToSearch),
                    )
                  : hits.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(TxCards.noCourseFound),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final h in hits)
                          ListTile(
                            title: Text(h.doc.title),
                            subtitle: h.trail == null
                                ? null
                                : Text(
                                    '${h.trail!.subject.name} › ${h.trail!.topic.name}',
                                  ),
                            onTap: () => Navigator.pop(context, h.doc.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(Tx.cancel),
        ),
      ],
    );
  }
}

/// Date butoir d'un deck.
Future<void> setDeadline(BuildContext context, Deck deck) async {
  final repo = context.read<FlashcardsRepository>();
  final now = repo.now();
  final picked = await showDatePicker(
    context: context,
    helpText: TxCards.deadlineHelp,
    initialDate: now.add(const Duration(days: 14)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 365 * 3)),
  );
  if (picked == null || !context.mounted) return;
  int? moved;
  final ok = await guarded(
    context,
    () => moved = repo.applyDeadline(deck.id, picked),
  );
  if (ok && context.mounted) {
    showInfo(context, TxCards.deadlineDone(moved ?? 0));
  }
}

/// Rattrapage de retard : tout reporter de N jours, ou étaler sur N jours.
Future<void> catchUp(BuildContext context, {Deck? deck}) async {
  final repo = context.read<FlashcardsRepository>();
  final days = TextEditingController(text: '3');
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        deck == null
            ? TxCards.catchUpTitle
            : '${TxCards.catchUpTitle} · ${deck.name}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(TxCards.catchUpHelp),
          const SizedBox(height: 12),
          TextField(
            controller: days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: TxCards.daysLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(Tx.cancel),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, 'postpone'),
          child: const Text(TxCards.postponeAll),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'spread'),
          child: const Text(TxCards.spreadOut),
        ),
      ],
    ),
  );
  final n = int.tryParse(days.text.trim());
  days.dispose();
  if (choice == null || !context.mounted) return;
  if (n == null || n < 1) {
    showInfo(context, TxCards.daysLabel);
    return;
  }
  var count = 0;
  final ok = await guarded(context, () {
    count = choice == 'postpone'
        ? repo.postponeOverdue(n, deckId: deck?.id)
        : repo.spreadOverdue(n, deckId: deck?.id);
  });
  if (ok && context.mounted) {
    showInfo(
      context,
      choice == 'postpone' ? TxCards.postponed(count) : TxCards.spread(count),
    );
  }
}

/// Nouveau deck ; renvoie le deck créé, ou null.
Future<Deck?> createDeckDialog(BuildContext context, {int? subjectId}) async {
  final repo = context.read<FlashcardsRepository>();
  final name = await promptText(
    context,
    title: TxCards.newDeck,
    label: TxCards.deckName,
    confirmLabel: Tx.create,
  );
  if (name == null || !context.mounted) return null;
  Deck? created;
  await guarded(
    context,
    () => created = repo.createDeck(name, subjectId: subjectId),
  );
  return created;
}

/// Supprimer un deck après confirmation.
Future<bool> deleteDeckDialog(BuildContext context, Deck deck) async {
  final repo = context.read<FlashcardsRepository>();
  final notes = repo.notes(deck.id).length;
  final ok = await confirm(
    context,
    title: TxCards.deleteDeck,
    message: TxCards.deleteDeckAsk(deck.name, notes),
    confirmLabel: Tx.delete,
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  return guarded(context, () => repo.deleteDeck(deck.id));
}
