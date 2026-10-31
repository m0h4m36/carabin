import 'dart:math';

import 'package:carabin/data/database.dart';
import 'package:carabin/data/flashcards_repository.dart';
import 'package:carabin/data/settings_repository.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:carabin/domain/study_options.dart';
import 'package:carabin/features/flashcards/review_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _R implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

void main() {
  late AppDatabase db;
  late FlashcardsRepository repo;
  late DateTime now;
  late int deck;

  setUp(() {
    db = AppDatabase.inMemory();
    now = DateTime(2030, 3, 1, 9);
    repo = FlashcardsRepository(
      db,
      SettingsRepository(db),
      clock: () => now,
      random: _R(),
    );
    deck = repo.createDeck('X').id;
    repo.setDeckOptions(
      deck,
      const StudyOptions(onePerNotePerDay: false, order: StudyOrder.course),
    );
  });
  tearDown(() => db.dispose());

  List<int> add(int n) => [
    for (var i = 1; i <= n; i++)
      repo
          .cardsOfNote(
            repo
                .addNote(
                  deck,
                  NoteType.basic,
                  NoteFields({'front': 'Q$i', 'back': 'R$i'}),
                )
                .id,
          )
          .single
          .id,
  ];

  test('séance vide', () {
    final s = ReviewSession(repo);
    expect(s.finished, isTrue);
    expect(s.initialTotal, 0);
  });

  test('sert les cartes dans l\'ordre et se termine', () {
    final ids = add(3);
    final s = ReviewSession(repo);
    expect(s.initialTotal, 3);
    expect(s.current, ids[0]);
    expect(s.pills, (fresh: 3, learning: 0, review: 0));
    s.answer(Grade.easy); // sort de l'apprentissage
    expect(s.current, ids[1]);
    expect(s.pills.fresh, 2);
    s.answer(Grade.easy);
    s.answer(Grade.easy);
    expect(s.finished, isTrue);
    expect(s.answered, 3);
  });

  test('« Encore » : la carte revient dans la séance après son délai', () {
    final ids = add(2);
    final s = ReviewSession(repo);
    s.answer(Grade.again); // revient dans 1 min
    expect(s.current, ids[1]);
    expect(s.pills.learning, 1);
    s.answer(Grade.easy);
    // plus rien d'autre : la carte en apprentissage est présentée sans attendre
    expect(s.current, ids[0]);
    expect(s.finished, isFalse);
  });

  test(
    'une carte en apprentissage dont l\'heure est venue passe avant la file',
    () {
      final ids = add(3);
      final s = ReviewSession(repo);
      s.answer(Grade.again);
      expect(s.current, ids[1]);
      now = now.add(const Duration(minutes: 2));
      s.answer(Grade.easy);
      expect(s.current, ids[0]); // revenue avant ids[2]
    },
  );

  test('annuler remet la carte et la suivante retrouve sa place', () {
    final ids = add(3);
    final s = ReviewSession(repo);
    s.answer(Grade.easy);
    expect(s.current, ids[1]);
    expect(s.undo(), isTrue);
    expect(s.current, ids[0]);
    expect(s.answered, 0);
    expect(repo.card(ids[0]).schedule.isNew, isTrue);
    expect(s.canUndo, isFalse);
    expect(s.undo(), isFalse);
    s.answer(Grade.easy);
    expect(s.current, ids[1]);
    s.answer(Grade.easy);
    expect(s.current, ids[2]);
  });

  test('annuler deux fois de suite', () {
    final ids = add(3);
    final s = ReviewSession(repo);
    s.answer(Grade.easy);
    s.answer(Grade.easy);
    expect(s.current, ids[2]);
    s.undo();
    expect(s.current, ids[1]);
    s.undo();
    expect(s.current, ids[0]);
    s.answer(Grade.easy);
    s.answer(Grade.easy);
    s.answer(Grade.easy);
    expect(s.finished, isTrue);
    expect(db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'], 3);
  });

  test('mettre de côté, enterrer, supprimer', () {
    final ids = add(4);
    final s = ReviewSession(repo);
    s.suspendCurrent();
    expect(repo.card(ids[0]).suspended, isTrue);
    expect(s.current, ids[1]);
    s.buryCurrent();
    expect(repo.card(ids[1]).buriedUntilMs, isNotNull);
    expect(s.current, ids[2]);
    s.deleteCurrent();
    expect(() => repo.card(ids[2]), throwsA(anything));
    expect(s.current, ids[3]);
    s.answer(Grade.easy);
    expect(s.finished, isTrue);
  });

  test('enterrer une notion retire ses cartes sœurs de la séance', () {
    final n = repo.addNote(
      deck,
      NoteType.cloze,
      NoteFields({'text': '{{c1::a}} {{c2::b}} {{c3::c}}'}),
    );
    final other = add(1).single;
    final s = ReviewSession(repo);
    expect(s.initialTotal, 4);
    s.buryCurrent();
    expect(s.current, other);
    s.answer(Grade.easy);
    expect(s.finished, isTrue);
    expect(
      repo.cardsOfNote(n.id).every((c) => c.buriedUntilMs != null),
      isTrue,
    );
  });

  test('séance sur une liste de cartes imposée (entraînement)', () {
    final ids = add(5);
    final s = ReviewSession(repo, cardIds: [ids[4], ids[2]]);
    expect(s.initialTotal, 2);
    expect(s.current, ids[4]);
    s.answer(Grade.good);
    expect(s.current, ids[2]);
  });

  test('révisions avant nouvelles, et pastilles', () {
    final ids = add(2);
    for (final id in ids) {
      repo.answer(id, Grade.good);
      now = now.add(const Duration(minutes: 11));
      repo.answer(id, Grade.good);
    }
    final fresh = add(1).single;
    now = now.add(const Duration(days: 10));
    final s = ReviewSession(repo);
    expect(s.pills, (fresh: 1, learning: 0, review: 2));
    expect(s.current, isNot(fresh));
    s.answer(Grade.good);
    s.answer(Grade.good);
    expect(s.current, fresh);
  });

  test('carte maudite : retirée de la séance une fois suspendue', () {
    final id = add(1).single;
    repo.setDeckOptions(
      deck,
      const StudyOptions(
        leechThreshold: 1,
        onePerNotePerDay: false,
        order: StudyOrder.course,
      ),
    );
    repo.answer(id, Grade.good);
    now = now.add(const Duration(minutes: 11));
    repo.answer(id, Grade.good);
    now = now.add(const Duration(days: 10));
    final s = ReviewSession(repo);
    final r = s.answer(Grade.again);
    expect(r.becameLeech, isTrue);
    expect(repo.card(id).suspended, isTrue);
    expect(s.finished, isTrue);
  });

  test('durée cumulée plafonnée', () {
    add(2);
    final s = ReviewSession(repo);
    s.answer(Grade.easy, durationMs: 3000);
    s.answer(Grade.easy, durationMs: 99 * 60 * 1000);
    expect(s.spent, const Duration(minutes: 10, seconds: 3));
  });
}
