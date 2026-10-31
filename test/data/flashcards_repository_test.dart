import 'dart:math';

import 'package:carabin/data/database.dart';
import 'package:carabin/data/errors.dart';
import 'package:carabin/data/flashcard_models.dart';
import 'package:carabin/data/flashcards_repository.dart';
import 'package:carabin/data/settings_repository.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:carabin/domain/study_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FlashcardsRepository repo;
  late DateTime now;

  setUp(() {
    db = AppDatabase.inMemory();
    now = DateTime(2030, 3, 1, 9);
    repo = FlashcardsRepository(
      db,
      SettingsRepository(db),
      clock: () => now,
      random: _FixedRandom(),
    );
  });

  tearDown(() => db.dispose());

  NoteFields basic(String q, [String a = 'réponse']) =>
      NoteFields({'front': q, 'back': a});

  /// Ajoute [n] notes question-réponse dans le paquet.
  List<NoteRow> addBasics(int deckId, int n, {String prefix = 'Q'}) => [
    for (var i = 1; i <= n; i++)
      repo.addNote(deckId, NoteType.basic, basic('$prefix$i')),
  ];

  /// Fait passer une carte neuve en révision (Bien, +11 min, Bien).
  void graduate(int cardId) {
    repo.answer(cardId, Grade.good);
    now = now.add(const Duration(minutes: 11));
    repo.answer(cardId, Grade.good);
  }

  group('paquets', () {
    test('création, renommage et noms uniques', () {
      final d = repo.createDeck('  Cardio   vasculaire ');
      expect(d.name, 'Cardio vasculaire');
      expect(
        () => repo.createDeck('cardio vasculaire'),
        throwsA(isA<NameTakenError>()),
      );
      expect(() => repo.createDeck('   '), throwsA(isA<EmptyNameError>()));
      final e = repo.createDeck('Neuro');
      expect(
        () => repo.renameDeck(e.id, 'CARDIO VASCULAIRE'),
        throwsA(isA<NameTakenError>()),
      );
      repo.renameDeck(e.id, 'Neurologie');
      expect(repo.deck(e.id).name, 'Neurologie');
      repo.renameDeck(e.id, 'Neurologie'); // même nom : permis
    });

    test('deux paquets de même nom dans deux matières différentes', () {
      db.execute("INSERT INTO years(name, position) VALUES ('A', 0)");
      final a = repo.createDeck('Cours', subjectId: null);
      expect(a.subjectId, isNull);
    });

    test('supprimer un paquet supprime ses notes, cartes et historiques', () {
      final d = repo.createDeck('X');
      final n = addBasics(d.id, 2);
      repo.answer(repo.cardsOfNote(n.first.id).first.id, Grade.good);
      repo.deleteDeck(d.id);
      for (final t in ['notes', 'cards', 'review_logs']) {
        expect(
          db.select('SELECT COUNT(*) AS n FROM $t').first['n'],
          0,
          reason: t,
        );
      }
    });

    test('un paquet inconnu lève NotFoundError', () {
      expect(() => repo.deck(999), throwsA(isA<NotFoundError>()));
      expect(
        () => repo.addNote(999, NoteType.basic, basic('q')),
        throwsA(isA<NotFoundError>()),
      );
    });
  });

  group('notes et cartes', () {
    test('un texte à trous fabrique une carte par numéro', () {
      final d = repo.createDeck('X');
      final n = repo.addNote(
        d.id,
        NoteType.cloze,
        NoteFields({'text': '{{c1::a}} {{c2::b}} {{c3::c}}'}),
      );
      expect(repo.cardsOfNote(n.id).map((c) => c.ord), [1, 2, 3]);
      expect(n.cardCount, 3);
      expect(repo.cardsOfNote(n.id).every((c) => c.schedule.isNew), isTrue);
    });

    test('une note invalide est refusée et rien n\'est enregistré', () {
      final d = repo.createDeck('X');
      expect(
        () => repo.addNote(
          d.id,
          NoteType.cloze,
          NoteFields({'text': 'pas de trou'}),
        ),
        throwsA(
          isA<InvalidNoteError>().having(
            (e) => e.issue,
            'issue',
            NoteIssue.noCloze,
          ),
        ),
      );
      expect(repo.notes(d.id), isEmpty);
    });

    test('modifier une note garde l\'historique des cartes qui subsistent', () {
      final d = repo.createDeck('X');
      final n = repo.addNote(
        d.id,
        NoteType.cloze,
        NoteFields({'text': '{{c1::a}} {{c2::b}}'}),
      );
      final c1 = repo.cardsOfNote(n.id).first;
      repo.answer(c1.id, Grade.good);
      // c2 disparaît, c3 apparaît
      repo.updateNote(n.id, NoteFields({'text': '{{c1::a}} {{c3::z}}'}));
      final cards = repo.cardsOfNote(n.id);
      expect(cards.map((c) => c.ord), [1, 3]);
      expect(cards.first.id, c1.id);
      expect(cards.first.schedule.reps, 1);
      expect(cards.last.schedule.isNew, isTrue);
    });

    test('les étiquettes sont nettoyées et sans doublon', () {
      final d = repo.createDeck('X');
      final n = repo.addNote(
        d.id,
        NoteType.basic,
        basic('q'),
        tags: ['  cœur ', 'rein pair', 'cœur', ''],
      );
      expect(n.tags, ['cœur', 'rein_pair']);
    });

    test('recherche dans les notes (sans accents ni casse)', () {
      final d = repo.createDeck('X');
      repo.addNote(d.id, NoteType.basic, basic('Œdème aigu du poumon'));
      repo.addNote(d.id, NoteType.basic, basic('Insuffisance rénale'));
      expect(repo.notes(d.id, query: 'oedeme'), hasLength(1));
      expect(repo.notes(d.id, query: 'RENALE'), hasLength(1));
      expect(repo.notes(d.id, query: 'zzz'), isEmpty);
      expect(repo.notes(d.id), hasLength(2));
    });

    test('doublons détectés', () {
      final d = repo.createDeck('X');
      final n = repo.addNote(d.id, NoteType.basic, basic('Q', 'R'));
      expect(repo.hasDuplicate(d.id, NoteType.basic, basic('Q', 'R')), isTrue);
      expect(
        repo.hasDuplicate(
          d.id,
          NoteType.basic,
          basic('Q', 'R'),
          exceptId: n.id,
        ),
        isFalse,
      );
      expect(
        repo.hasDuplicate(d.id, NoteType.basic, basic('Q', 'autre')),
        isFalse,
      );
    });

    test('déplacer et supprimer une note', () {
      final a = repo.createDeck('A');
      final b = repo.createDeck('B');
      final n = repo.addNote(a.id, NoteType.basic, basic('q'));
      repo.moveNote(n.id, b.id);
      expect(repo.notes(a.id), isEmpty);
      expect(repo.notes(b.id), hasLength(1));
      repo.deleteNote(n.id);
      expect(repo.notes(b.id), isEmpty);
      expect(db.select('SELECT COUNT(*) AS n FROM cards').first['n'], 0);
    });
  });

  group('jour d\'étude', () {
    test('le jour change à 4 h', () {
      expect(studyDayStart(DateTime(2030, 3, 1, 9)), DateTime(2030, 3, 1, 4));
      expect(studyDayStart(DateTime(2030, 3, 2, 1)), DateTime(2030, 3, 1, 4));
      expect(
        studyDayStart(DateTime(2030, 3, 1, 3, 59)),
        DateTime(2030, 2, 28, 4),
      );
      expect(studyDayEnd(DateTime(2030, 3, 1, 9)), DateTime(2030, 3, 2, 4));
    });
  });

  group('file du jour', () {
    test('les nouvelles cartes respectent le plafond', () {
      final d = repo.createDeck('X');
      addBasics(d.id, 5);
      repo.setDeckOptions(
        d.id,
        const StudyOptions(newPerDay: 2, onePerNotePerDay: false),
      );
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(2));
      final c = repo.counts(deckId: d.id);
      expect(c.newToday, 2);
      expect(c.newWaiting, 3);
      expect(c.total, 5);
    });

    test('répondre à une nouvelle carte consomme le plafond du jour', () {
      final d = repo.createDeck('X');
      addBasics(d.id, 5);
      repo.setDeckOptions(
        d.id,
        const StudyOptions(newPerDay: 2, onePerNotePerDay: false),
      );
      var q = repo.todayQueue(deckIds: [d.id]);
      repo.answer(q.first, Grade.good);
      q = repo.todayQueue(deckIds: [d.id]);
      expect(q, hasLength(1));
      repo.answer(q.first, Grade.good);
      expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
      // le lendemain, deux autres
      now = DateTime(2030, 3, 2, 9);
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(2));
    });

    test('sans plafond : toutes les nouvelles cartes', () {
      final d = repo.createDeck('X');
      addBasics(d.id, 30);
      const free = StudyOptions(newPerDay: null, onePerNotePerDay: false);
      repo.setGlobalOptions(free);
      repo.setDeckOptions(d.id, free);
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(30));
    });

    test('le plafond général s\'applique aussi à un paquet sans plafond (le plus strict l\'emporte)', () {
      final d = repo.createDeck('X');
      addBasics(d.id, 30);
      repo.setDeckOptions(
        d.id,
        const StudyOptions(newPerDay: null, onePerNotePerDay: false),
      );
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(20));
    });

    test('plafond général : le plus strict l\'emporte', () {
      final a = repo.createDeck('A');
      final b = repo.createDeck('B');
      addBasics(a.id, 4);
      addBasics(b.id, 4, prefix: 'R');
      repo.setGlobalOptions(
        const StudyOptions(newPerDay: 5, onePerNotePerDay: false),
      );
      expect(repo.todayQueue(), hasLength(5));
      // un paquet à plafond propre plus strict
      repo.setDeckOptions(
        a.id,
        const StudyOptions(newPerDay: 1, onePerNotePerDay: false),
      );
      expect(repo.todayQueue(deckIds: [a.id]), hasLength(1));
      expect(repo.todayQueue(), hasLength(5));
    });

    test('une carte en retard est proposée, pas une carte à venir', () {
      final d = repo.createDeck('X');
      final n = addBasics(d.id, 1).single;
      final id = repo.cardsOfNote(n.id).single.id;
      graduate(id);
      expect(repo.card(id).schedule.state, CardState.review);
      expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
      now = now.add(const Duration(days: 3));
      expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
      now = now.add(const Duration(days: 2));
      expect(repo.todayQueue(deckIds: [d.id]), [id]);
      expect(repo.counts(deckId: d.id).due, 1);
    });

    test('plafond de révisions', () {
      final d = repo.createDeck('X');
      final ids = [
        for (final n in addBasics(d.id, 4)) repo.cardsOfNote(n.id).single.id,
      ];
      ids.forEach(graduate);
      repo.setDeckOptions(
        d.id,
        const StudyOptions(reviewsPerDay: 3, onePerNotePerDay: false),
      );
      now = now.add(const Duration(days: 10));
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(3));
    });

    test('une seule carte par notion et par jour', () {
      final d = repo.createDeck('X');
      final n = repo.addNote(
        d.id,
        NoteType.cloze,
        NoteFields({'text': '{{c1::a}} {{c2::b}} {{c3::c}}'}),
      );
      var q = repo.todayQueue(deckIds: [d.id]);
      expect(q, hasLength(1));
      expect(repo.counts(deckId: d.id).newToday, 1);
      repo.answer(q.single, Grade.easy);
      expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
      // le lendemain, la carte suivante de la notion arrive
      now = DateTime(2030, 3, 2, 9);
      q = repo.todayQueue(deckIds: [d.id]);
      expect(q, hasLength(1));
      expect(repo.card(q.single).noteId, n.id);
      expect(repo.card(q.single).ord, 2);
    });

    test('règle désactivable', () {
      final d = repo.createDeck('X');
      repo.addNote(
        d.id,
        NoteType.cloze,
        NoteFields({'text': '{{c1::a}} {{c2::b}} {{c3::c}}'}),
      );
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(3));
    });

    test('une carte en pause ou enterrée n\'est pas proposée', () {
      final d = repo.createDeck('X');
      final notes = addBasics(d.id, 3);
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      repo.setNoteSuspended(notes[0].id, true);
      repo.buryNote(notes[1].id);
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(1));
      expect(repo.note(notes[0].id).allSuspended, isTrue);
      repo.setNoteSuspended(notes[0].id, false);
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(2));
      now = DateTime(2030, 3, 2, 9); // l'enterrement est levé le lendemain
      expect(repo.todayQueue(deckIds: [d.id]), hasLength(3));
    });

    test('ordre imposé à la séance', () {
      final d = repo.createDeck('X');
      addBasics(d.id, 3);
      repo.setDeckOptions(
        d.id,
        const StudyOptions(order: StudyOrder.shuffled, onePerNotePerDay: false),
      );
      final course = repo.todayQueue(deckIds: [d.id], order: StudyOrder.course);
      expect(course, [...course]..sort());
    });

    test('ordre dans le cours : conserve l\'ordre de création', () {
      final d = repo.createDeck('X');
      final notes = addBasics(d.id, 4);
      repo.setDeckOptions(
        d.id,
        const StudyOptions(order: StudyOrder.course, onePerNotePerDay: false),
      );
      final q = repo.todayQueue(deckIds: [d.id]);
      expect(q.map((id) => repo.card(id).noteId), notes.map((n) => n.id));
    });
  });

  group('apprentissage', () {
    test('« Encore » ramène la carte dans 1 min ; elle reste dans la file d\'apprentissage', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      final r = repo.answer(id, Grade.again);
      expect(r.interval, const Duration(minutes: 1));
      expect(repo.learningDue(), isEmpty);
      expect(repo.learningDue(ahead: learnAhead), [id]);
      now = now.add(const Duration(minutes: 1));
      expect(repo.learningDue(), [id]);
    });

    test(
      'compteur « à revoir » inclut les cartes en apprentissage proches',
      () {
        final d = repo.createDeck('X');
        final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
        repo.answer(id, Grade.good); // dans 10 min
        final c = repo.counts(deckId: d.id);
        expect(c.due, 1);
        expect(c.newToday, 0);
      },
    );

    test(
      'sur une notion déjà en apprentissage, pas de nouvelle carte soeur',
      () {
        final d = repo.createDeck('X');
        repo.addNote(
          d.id,
          NoteType.cloze,
          NoteFields({'text': '{{c1::a}} {{c2::b}}'}),
        );
        final first = repo.todayQueue(deckIds: [d.id]).single;
        repo.answer(first, Grade.good);
        now = DateTime(2030, 3, 2, 9);
        // la carte 1 est en apprentissage depuis la veille : la soeur attend
        expect(repo.learningDue(), [first]);
        expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
      },
    );
  });

  group('réponses', () {
    test('la réponse écrit l\'historique et met à jour la carte', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      repo.answer(id, Grade.hard, durationMs: 4200);
      final c = repo.card(id);
      expect(c.schedule.reps, 1);
      expect(c.schedule.state, CardState.learning);
      final log = db.select('SELECT * FROM review_logs').single;
      expect(log['rating'], 2);
      expect(log['state_before'], 0);
      expect(log['duration_ms'], 4200);
    });

    test('annuler restaure exactement la carte et efface l\'historique', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      graduate(id);
      final before = repo.card(id);
      final r = repo.answer(id, Grade.again);
      expect(repo.card(id).schedule.lapses, 1);
      repo.undo(r.undo);
      final after = repo.card(id);
      expect(after.schedule.state, before.schedule.state);
      expect(after.schedule.stability, before.schedule.stability);
      expect(after.schedule.difficulty, before.schedule.difficulty);
      expect(after.schedule.dueMs, before.schedule.dueMs);
      expect(after.schedule.lapses, 0);
      expect(after.schedule.reps, before.schedule.reps);
      expect(db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'], 2);
    });

    test(
      'annuler une première réponse rend la carte neuve et le plafond du jour',
      () {
        final d = repo.createDeck('X');
        final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
        repo.setDeckOptions(d.id, const StudyOptions(newPerDay: 1));
        final r = repo.answer(id, Grade.good);
        expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
        repo.undo(r.undo);
        expect(repo.card(id).schedule.isNew, isTrue);
        expect(repo.todayQueue(deckIds: [d.id]), [id]);
      },
    );

    test('carte maudite : mise de côté après N oublis', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      repo.setDeckOptions(d.id, const StudyOptions(leechThreshold: 2));
      graduate(id);
      var leech = false;
      for (var i = 0; i < 2; i++) {
        now = now.add(const Duration(days: 40));
        // revenir en révision : deux « Bien » après l'oubli
        final r = repo.answer(id, Grade.again);
        leech = r.becameLeech;
        if (i == 0) {
          expect(leech, isFalse);
          expect(repo.card(id).suspended, isFalse);
          now = now.add(const Duration(minutes: 11));
          repo.answer(id, Grade.good);
        }
      }
      expect(leech, isTrue);
      expect(repo.card(id).suspended, isTrue);
      expect(repo.card(id).schedule.lapses, 2);
    });

    test('carte maudite sans action : signalée mais pas suspendue', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      repo.setDeckOptions(
        d.id,
        const StudyOptions(leechThreshold: 1, leechAction: LeechAction.none),
      );
      graduate(id);
      now = now.add(const Duration(days: 10));
      final r = repo.answer(id, Grade.again);
      expect(r.becameLeech, isTrue);
      expect(repo.card(id).suspended, isFalse);
    });

    test('l\'exigence de mémorisation du paquet est appliquée', () {
      final d = repo.createDeck('X');
      final a = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      final other = repo.createDeck('Y');
      final b = repo.cardsOfNote(addBasics(other.id, 1).single.id).single.id;
      repo.setDeckOptions(other.id, const StudyOptions(retention: 0.97));
      graduate(a);
      graduate(b);
      final ia =
          repo.card(a).schedule.dueMs - repo.card(a).schedule.lastReviewMs!;
      final ib =
          repo.card(b).schedule.dueMs - repo.card(b).schedule.lastReviewMs!;
      expect(ib, lessThan(ia));
    });

    test('prévisualisation des quatre délais', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      final p = repo.preview(id);
      expect(p[Grade.again], const Duration(minutes: 1));
      expect(p[Grade.good], const Duration(minutes: 10));
      expect(p[Grade.easy]!.inDays, greaterThanOrEqualTo(1));
    });
  });

  group('réglages', () {
    test('généraux par défaut, propres au paquet, retour au général', () {
      final d = repo.createDeck('X');
      expect(repo.deckOptions(d.id), isNull);
      expect(repo.effectiveOptions(d.id).newPerDay, 20);
      repo.setGlobalOptions(const StudyOptions(newPerDay: 7));
      expect(repo.effectiveOptions(d.id).newPerDay, 7);
      repo.setDeckOptions(d.id, const StudyOptions(newPerDay: 3));
      expect(repo.effectiveOptions(d.id).newPerDay, 3);
      expect(repo.deck(d.id).hasOwnOptions, isTrue);
      repo.setDeckOptions(d.id, null);
      expect(repo.effectiveOptions(d.id).newPerDay, 7);
    });
  });

  group('rattrapage', () {
    List<int> overdueCards(int deckId, int n) {
      final ids = [
        for (final note in addBasics(deckId, n))
          repo.cardsOfNote(note.id).single.id,
      ];
      ids.forEach(graduate);
      return ids;
    }

    test('tout reporter décale chaque échéance', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      final ids = overdueCards(d.id, 3);
      final dues = {for (final i in ids) i: repo.card(i).schedule.dueMs};
      now = now.add(const Duration(days: 30));
      expect(repo.postponeOverdue(2, deckId: d.id), 3);
      for (final i in ids) {
        expect(repo.card(i).schedule.dueMs - dues[i]!, 2 * 86400000);
      }
    });

    test('étaler le retard répartit sur les jours à venir', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      overdueCards(d.id, 6);
      now = now.add(const Duration(days: 30));
      expect(repo.spreadOverdue(3, deckId: d.id), 6);
      final start = studyDayStart(now).toUtc().millisecondsSinceEpoch;
      final days = [
        for (final r in db.select('SELECT due FROM cards ORDER BY due'))
          ((r['due'] as int) - start) ~/ 86400000,
      ];
      expect(days, [1, 1, 2, 2, 3, 3]);
      expect(repo.todayQueue(deckIds: [d.id]), isEmpty);
    });

    test('rien à faire quand il n\'y a pas de retard', () {
      final d = repo.createDeck('X');
      expect(repo.postponeOverdue(1, deckId: d.id), 0);
      expect(repo.spreadOverdue(3, deckId: d.id), 0);
    });

    test('date butoir : ramène les échéances lointaines avant l\'examen', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      final ids = overdueCards(d.id, 4);
      // pousse toutes les échéances très loin
      db.execute('UPDATE cards SET due = due + ?', [200 * 86400000]);
      final deadline = DateTime(2030, 3, 11);
      expect(repo.applyDeadline(d.id, deadline), 4);
      final limit = DateTime(2030, 3, 11, 4).toUtc().millisecondsSinceEpoch;
      for (final i in ids) {
        expect(repo.card(i).schedule.dueMs, lessThan(limit));
      }
    });
  });

  group('statistiques', () {
    test('cartes par jour, série et rétention', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      final ids = [
        for (final n in addBasics(d.id, 3)) repo.cardsOfNote(n.id).single.id,
      ];
      repo.answer(ids[0], Grade.good);
      repo.answer(ids[1], Grade.good);
      var per = repo.reviewsPerDay(3);
      expect(per, [0, 0, 2]);
      expect(repo.streak(), 1);
      now = DateTime(2030, 3, 2, 9);
      expect(
        repo.streak(),
        1,
      ); // hier compte tant qu'on n'a pas encore révisé aujourd'hui
      repo.answer(ids[2], Grade.good);
      expect(repo.streak(), 2);
      per = repo.reviewsPerDay(3);
      expect(per, [0, 2, 1]);
      now = DateTime(2030, 3, 5, 9);
      expect(repo.streak(), 0);
    });

    test('réviser après minuit compte pour la veille', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      now = DateTime(2030, 3, 2, 1, 30);
      repo.answer(id, Grade.good);
      expect(repo.reviewsPerDay(2), [0, 1]);
      now = DateTime(2030, 3, 2, 9);
      expect(repo.reviewsPerDay(2), [1, 0]);
    });

    test('rétention : seules les cartes déjà apprises comptent', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      final ids = [
        for (final n in addBasics(d.id, 2)) repo.cardsOfNote(n.id).single.id,
      ];
      ids.forEach(graduate);
      expect(repo.retention(30).total, 0);
      expect(repo.retention(30).rate, isNull);
      now = now.add(const Duration(days: 6));
      repo.answer(ids[0], Grade.good);
      repo.answer(ids[1], Grade.again);
      final r = repo.retention(30);
      expect(r.total, 2);
      expect(r.recalled, 1);
      expect(r.rate, 0.5);
    });

    test('stock : neuves, apprentissage, jeunes, mûres', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      final ids = [
        for (final n in addBasics(d.id, 4)) repo.cardsOfNote(n.id).single.id,
      ];
      graduate(ids[0]); // jeune (4 j)
      repo.answer(ids[1], Grade.good); // en apprentissage
      graduate(ids[2]);
      db.execute('UPDATE cards SET due = last_review + ? WHERE id = ?', [
        30 * 86400000,
        ids[2],
      ]); // mûre
      final s = repo.stock();
      expect(s.fresh, 1);
      expect(s.learning, 1);
      expect(s.young, 1);
      expect(s.mature, 1);
      expect(s.total, 4);
    });

    test('cartes difficiles et temps moyen', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      expect(repo.averageSecondsPerCard(), 8);
      graduate(id);
      db.execute('UPDATE cards SET lapses = 4 WHERE id = ?', [id]);
      expect(repo.hardCardCount(), 1);
      repo.answer(id, Grade.good, durationMs: 6000);
      expect(repo.averageSecondsPerCard(), 6);
    });
  });

  group('prochaine échéance', () {
    test('aucune carte programmée : null', () {
      final d = repo.createDeck('X');
      addBasics(d.id, 2);
      expect(repo.nextDue(), isNull);
    });

    test('date de la première échéance et nombre de cartes ce jour-là', () {
      final d = repo.createDeck('X');
      repo.setDeckOptions(d.id, const StudyOptions(onePerNotePerDay: false));
      final ids = [
        for (final n in addBasics(d.id, 3)) repo.cardsOfNote(n.id).single.id,
      ];
      ids.forEach(graduate); // chacune revient dans 4 jours
      final next = repo.nextDue(deckIds: [d.id])!;
      expect(next.count, 3);
      expect(next.at.difference(now).inDays, inInclusiveRange(3, 4));
    });

    test('une carte en apprentissage dans quelques minutes compte', () {
      final d = repo.createDeck('X');
      final id = repo.cardsOfNote(addBasics(d.id, 1).single.id).single.id;
      repo.answer(id, Grade.good);
      final next = repo.nextDue()!;
      expect(next.count, 1);
      expect(next.at.difference(now), const Duration(minutes: 10));
    });
  });

  group('s\'entraîner', () {
    test('tirage dans les paquets choisis, avec limite', () {
      final a = repo.createDeck('A');
      final b = repo.createDeck('B');
      addBasics(a.id, 5);
      addBasics(b.id, 5, prefix: 'R');
      expect(repo.drawCards([a.id]), hasLength(5));
      expect(repo.drawCards([a.id, b.id]), hasLength(10));
      expect(repo.drawCards([a.id, b.id], count: 20), hasLength(10));
      expect(repo.drawCards([a.id, b.id], count: 4), hasLength(4));
      expect(repo.drawCards([]), isEmpty);
    });

    test('le tirage ignore les cartes en pause et ne reprogramme rien', () {
      final a = repo.createDeck('A');
      final notes = addBasics(a.id, 3);
      repo.setNoteSuspended(notes[0].id, true);
      final ids = repo.drawCards([a.id], shuffled: false);
      expect(ids, hasLength(2));
      expect(repo.card(ids.first).schedule.isNew, isTrue);
    });

    test('historique des séances, note sur 20', () {
      repo.recordPractice(
        total: 20,
        correct: 15,
        durationMs: 90000,
        deckNames: ['A', 'B'],
      );
      repo.recordPractice(
        total: 3,
        correct: 1,
        durationMs: 1000,
        deckNames: ['A'],
      );
      final h = repo.practiceHistory();
      expect(h, hasLength(2));
      expect(h.last.score20, 15);
      expect(h.last.deckNames, 'A, B');
      expect(
        h.first.score20,
        6.5,
      ); // 1/3 × 20 = 6,67 → 6,5 (demi-point le plus proche)
      repo.deletePractice(h.first.id);
      expect(repo.practiceHistory(), hasLength(1));
    });
  });
}

/// Hasard déterministe : « mélanger » ne change rien dans les tests.
class _FixedRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}
