import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:carabin/data/carabin_package.dart';
import 'package:carabin/data/database.dart';
import 'package:carabin/data/deck_exchange.dart';
import 'package:carabin/data/errors.dart';
import 'package:carabin/data/flashcards_repository.dart';
import 'package:carabin/data/media_store.dart';
import 'package:carabin/data/settings_repository.dart';
import 'package:carabin/domain/exchange.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:carabin/domain/study_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/png.dart';

/// Un appareil : sa base, ses médias, son horloge.
class Device {
  Device(String name, this.tmp, DateTime start)
    : now = start,
      db = AppDatabase.inMemory() {
    media = MediaStore(p.join(tmp.path, name, 'media'));
    repo = FlashcardsRepository(db, SettingsRepository(db), clock: () => now);
    exchange = DeckExchange(db, repo);
  }

  final Directory tmp;
  final AppDatabase db;
  late final MediaStore media;
  late final FlashcardsRepository repo;
  late final DeckExchange exchange;
  DateTime now;

  void answer(int cardId, Grade g) {
    repo.answer(cardId, g);
    now = now.add(const Duration(minutes: 11));
  }

  /// Écrit les paquets dans un fichier et renvoie son chemin.
  String export(
    List<int> deckIds, {
    required bool progress,
    String name = 'echange',
  }) {
    final bytes = buildCarabinPackage(
      decks: [
        for (final id in deckIds) exchange.exportDeck(id, progress: progress),
      ],
      progress: progress,
      media: media,
      now: now,
    );
    final f = File(p.join(tmp.path, '$name.carabin'))..writeAsBytesSync(bytes);
    return f.path;
  }

  /// Importe un fichier .carabin comme le ferait l'application.
  ImportReport import(String path, {bool progress = true}) {
    final parsed = readCarabinPackage(path, media.dir);
    final report = ImportReport()
      ..mediaAdded = parsed.mediaAdded
      ..mediaSkipped = parsed.mediaSkipped;
    db.transaction(() {
      for (final d in parsed.decks) {
        final r = exchange.ensureDeck(d.name, options: d.options);
        if (r.created) report.decksCreated++;
        exchange.importNotes(
          r.deck,
          d.notes,
          report,
          progress: progress && parsed.hasProgress,
          nowMs: now.toUtc().millisecondsSinceEpoch,
        );
      }
    });
    return report;
  }

  void dispose() => db.dispose();
}

void main() {
  late Directory tmp;
  late Device a;
  late Device b;
  final t0 = DateTime(2030, 3, 1, 9);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('carabin_exchange_');
    a = Device('a', tmp, t0);
    b = Device('b', tmp, t0);
  });
  tearDown(() {
    a.dispose();
    b.dispose();
    tmp.deleteSync(recursive: true);
  });

  NoteFields basic(String q, [String r = 'réponse']) =>
      NoteFields({'front': q, 'back': r});

  group('partage d\'un paquet (sans progression)', () {
    test(
      'notes, étiquettes, images et réglages passent sur l\'autre appareil',
      () {
        final img = a.media.addBytes(solidPng(8, 4), 'png');
        final deck = a.repo.createDeck('Anatomie');
        a.repo.setDeckOptions(deck.id, const StudyOptions(newPerDay: 5));
        a.repo.addNote(
          deck.id,
          NoteType.cloze,
          NoteFields({
            'text': 'Le {{c1::cœur}} [img:$img] a {{c2::4}} cavités',
            'extra': 'ex',
          }),
          tags: ['cardio', 'S1'],
        );
        a.repo.addNote(deck.id, NoteType.basic, basic('Q', 'R'));
        final path = a.export([deck.id], progress: false);

        final report = b.import(path);
        expect(report.decksCreated, 1);
        expect(report.notesAdded, 2);
        expect(report.cardsAdded, 3);
        expect(report.mediaAdded, 1);

        final copy = b.repo.decks().single;
        expect(copy.name, 'Anatomie');
        expect(b.repo.deckOptions(copy.id)!.newPerDay, 5);
        final notes = b.repo.notes(copy.id);
        expect(notes.map((n) => n.type), [NoteType.cloze, NoteType.basic]);
        expect(notes.first.tags, ['cardio', 'S1']);
        expect(notes.first.fields.text('extra'), 'ex');
        expect(b.media.exists(img), isTrue);
        expect(b.media.read(img), a.media.read(img));
        // mêmes identifiants : c'est bien la même note
        expect(
          notes.map((n) => n.guid),
          a.repo.notes(deck.id).map((n) => n.guid),
        );
        // trois cartes neuves ; une seule par notion et par jour est proposée
        final counts = b.repo.counts(deckId: copy.id);
        expect(counts.total, 3);
        expect(counts.newToday, 2);
      },
    );

    test('réimporter le même fichier ne crée aucun doublon', () {
      final deck = a.repo.createDeck('Anatomie');
      a.repo.addNote(deck.id, NoteType.basic, basic('Q1'));
      a.repo.addNote(deck.id, NoteType.basic, basic('Q2'));
      final path = a.export([deck.id], progress: false);
      b.import(path);
      final again = b.import(path);
      expect(again.notesAdded, 0);
      expect(again.notesPresent, 2);
      expect(again.decksCreated, 0);
      expect(b.repo.decks(), hasLength(1));
      expect(b.repo.notes(b.repo.decks().single.id), hasLength(2));
    });

    test(
      'un paquet de même nom (casse, accents) reçoit les nouvelles notes',
      () {
        final da = a.repo.createDeck('Cœur');
        a.repo.addNote(da.id, NoteType.basic, basic('A'));
        final db1 = b.repo.createDeck('COEUR');
        b.repo.addNote(db1.id, NoteType.basic, basic('B'));
        final r = b.import(a.export([da.id], progress: false));
        expect(r.decksCreated, 0);
        expect(b.repo.decks(), hasLength(1));
        expect(b.repo.notes(db1.id).map((n) => n.preview), hasLength(2));
      },
    );

    test('plusieurs paquets dans un seul fichier', () {
      final d1 = a.repo.createDeck('Un');
      final d2 = a.repo.createDeck('Deux');
      a.repo.addNote(d1.id, NoteType.basic, basic('1'));
      a.repo.addNote(d2.id, NoteType.basic, basic('2'));
      final r = b.import(a.export([d1.id, d2.id], progress: false));
      expect(r.decksCreated, 2);
      expect(b.repo.decks().map((d) => d.name), ['Un', 'Deux']);
    });

    test('les médias absents du dossier ne bloquent pas l\'export', () {
      final deck = a.repo.createDeck('Anatomie');
      a.repo.addNote(
        deck.id,
        NoteType.basic,
        basic('Q [img:00000000deadbeef0000.png]'),
      );
      final r = b.import(a.export([deck.id], progress: false));
      expect(r.notesAdded, 1);
      expect(r.mediaAdded, 0);
    });
  });

  group('progression', () {
    test(
      'cartes révisées, échéances et historique voyagent avec le paquet',
      () {
        final deck = a.repo.createDeck('Cardio');
        final n1 = a.repo.addNote(deck.id, NoteType.basic, basic('Q1'));
        final n2 = a.repo.addNote(deck.id, NoteType.basic, basic('Q2'));
        final c1 = a.repo.cardsOfNote(n1.id).single.id;
        a.answer(c1, Grade.good);
        a.answer(c1, Grade.good);
        a.answer(c1, Grade.easy);
        a.repo.setNoteSuspended(n2.id, true);

        final r = b.import(a.export([deck.id], progress: true));
        expect(r.logsAdded, 3);

        final copy = b.repo.decks().single;
        final notes = b.repo.notes(copy.id);
        final mine = a.repo.cardsOfNote(n1.id).single;
        final theirs = b.repo.cardsOfNote(notes.first.id).single;
        expect(theirs.schedule.state, mine.schedule.state);
        expect(theirs.schedule.stability, mine.schedule.stability);
        expect(theirs.schedule.difficulty, mine.schedule.difficulty);
        expect(theirs.schedule.dueMs, mine.schedule.dueMs);
        expect(theirs.schedule.reps, 3);
        expect(
          b.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'],
          3,
        );
        expect(b.repo.cardsOfNote(notes.last.id).single.suspended, isTrue);
      },
    );

    test('sans la case progression, le paquet repart de zéro', () {
      final deck = a.repo.createDeck('Cardio');
      final n = a.repo.addNote(deck.id, NoteType.basic, basic('Q1'));
      a.answer(a.repo.cardsOfNote(n.id).single.id, Grade.good);
      final path = a.export([deck.id], progress: false);
      b.import(path);
      final c = b.repo
          .cardsOfNote(b.repo.notes(b.repo.decks().single.id).single.id)
          .single;
      expect(c.schedule.isNew, isTrue);
      expect(
        b.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'],
        0,
      );
    });

    test('un fichier avec progression importé sans elle (progress: false) n\'apporte que le contenu', () {
      final deck = a.repo.createDeck('Cardio');
      final n = a.repo.addNote(deck.id, NoteType.basic, basic('Q1'));
      a.answer(a.repo.cardsOfNote(n.id).single.id, Grade.good);
      b.import(a.export([deck.id], progress: true), progress: false);
      final c = b.repo
          .cardsOfNote(b.repo.notes(b.repo.decks().single.id).single.id)
          .single;
      expect(c.schedule.isNew, isTrue);
    });

    test('fusion : la carte révisée le plus récemment l\'emporte, les historiques s\'additionnent', () {
      final deck = a.repo.createDeck('Cardio');
      final n = a.repo.addNote(deck.id, NoteType.basic, basic('Q1'));
      // B reçoit d'abord la note neuve
      b.import(a.export([deck.id], progress: true, name: 'v1'));
      final cardA = a.repo.cardsOfNote(n.id).single.id;
      final bDeck = b.repo.decks().single.id;
      final cardB = b.repo.cardsOfNote(b.repo.notes(bDeck).single.id).single.id;

      // A révise le matin, B révise l'après-midi
      a.answer(cardA, Grade.good);
      b.now = t0.add(const Duration(hours: 5));
      b.answer(cardB, Grade.good);
      b.answer(cardB, Grade.good);

      // B reçoit l'avancement de A (plus ancien) : B garde le sien, mais récupère le log de A
      final before = b.repo.card(cardB).schedule;
      final r1 = b.import(a.export([deck.id], progress: true, name: 'v2'));
      expect(r1.cardsProgressed, 0);
      expect(b.repo.card(cardB).schedule.dueMs, before.dueMs);
      expect(b.repo.card(cardB).schedule.reps, 2);
      expect(r1.logsAdded, 1);
      expect(
        b.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'],
        3,
      );

      // A reçoit l'avancement de B (plus récent) : A prend celui de B
      final r2 = a.import(b.export([bDeck], progress: true, name: 'v3'));
      expect(r2.cardsProgressed, 1);
      expect(a.repo.card(cardA).schedule.reps, 2);
      expect(a.repo.card(cardA).schedule.dueMs, before.dueMs);
      expect(
        a.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'],
        3,
      );

      // et recommencer ne change plus rien
      final r3 = a.import(b.export([bDeck], progress: true, name: 'v4'));
      expect(r3.changedAnything, isFalse);
      expect(r3.notesPresent, 1);
    });
  });

  group('mise à jour du contenu', () {
    test('une note modifiée plus récemment remplace l\'ancienne ; un trou ajouté crée une carte', () {
      final deck = a.repo.createDeck('Cardio');
      final n = a.repo.addNote(
        deck.id,
        NoteType.cloze,
        NoteFields({'text': 'A {{c1::b}}'}),
      );
      b.import(a.export([deck.id], progress: false, name: 'v1'));

      a.now = a.now.add(const Duration(days: 1));
      a.repo.updateNote(n.id, NoteFields({'text': 'A {{c1::b}} et {{c2::c}}'}));
      final r = b.import(a.export([deck.id], progress: false, name: 'v2'));
      expect(r.notesUpdated, 1);
      expect(r.cardsAdded, 1);
      final note = b.repo.notes(b.repo.decks().single.id).single;
      expect(note.fields.text('text'), 'A {{c1::b}} et {{c2::c}}');
      expect(note.cardCount, 2);
    });

    test('une note plus ancienne que la locale ne l\'écrase pas', () {
      final deck = a.repo.createDeck('Cardio');
      a.repo.addNote(deck.id, NoteType.basic, basic('ancienne version'));
      final path = a.export([deck.id], progress: false);
      b.import(path);
      final note = b.repo.notes(b.repo.decks().single.id).single;
      b.now = b.now.add(const Duration(days: 2));
      b.repo.updateNote(note.id, basic('modifiée sur B'));
      final r = b.import(path);
      expect(r.notesUpdated, 0);
      expect(
        b.repo.notes(b.repo.decks().single.id).single.fields.text('front'),
        'modifiée sur B',
      );
    });
  });

  group('fichiers invalides', () {
    String write(String name, List<int> bytes) =>
        (File(p.join(tmp.path, name))..writeAsBytesSync(bytes)).path;

    String zip(Map<String, List<int>> files) {
      final ar = Archive();
      files.forEach((k, v) => ar.addFile(ArchiveFile.bytes(k, v)));
      return write('x.carabin', ZipEncoder().encodeBytes(ar));
    }

    ExchangeError? failure(String path) {
      try {
        readCarabinPackage(path, b.media.dir);
      } on ExchangeError catch (e) {
        return e;
      }
      return null;
    }

    List<int> json(Object o) => utf8.encode(jsonEncode(o));

    test('ce n\'est pas une archive', () {
      expect(
        failure(write('a.carabin', [1, 2, 3, 4]))!.problem,
        ImportProblem.unreadable,
      );
      expect(
        failure(write('b.carabin', const []))!.problem,
        ImportProblem.unreadable,
      );
    });

    test('archive sans manifeste, ou d\'un autre format', () {
      expect(
        failure(
          zip({
            'hello.txt': [104],
          }),
        )!.problem,
        ImportProblem.unreadable,
      );
      expect(
        failure(
          zip({
            'manifest.json': json({'format': 'autre', 'version': 1}),
            'decks.json': json({'decks': []}),
          }),
        )!.problem,
        ImportProblem.unreadable,
      );
    });

    test('version plus récente que celle que l\'appli connaît', () {
      expect(
        failure(
          zip({
            'manifest.json': json({'format': 'carabin-decks', 'version': 99}),
            'decks.json': json({'decks': []}),
          }),
        )!.problem,
        ImportProblem.newerFormat,
      );
    });

    test('contenu abîmé', () {
      final manifest = json({'format': 'carabin-decks', 'version': 1});
      expect(
        failure(
          zip({
            'manifest.json': manifest,
            'decks.json': utf8.encode('{pas du json'),
          }),
        )!.problem,
        ImportProblem.corrupt,
      );
      expect(
        failure(
          zip({
            'manifest.json': manifest,
            'decks.json': json({
              'decks': [
                {
                  'name': 'X',
                  'notes': [
                    {
                      'guid': 'g',
                      'type': 'inconnu',
                      'fields': {},
                      'created': 1,
                      'updated': 1,
                    },
                  ],
                },
              ],
            }),
          }),
        )!.problem,
        ImportProblem.corrupt,
      );
    });

    test('une note invalide est ignorée, les autres passent', () {
      final good = IncomingNote(
        guid: 'g1',
        type: NoteType.basic,
        fields: basic('Q'),
        createdAtMs: 1,
        updatedAtMs: 1,
      );
      final bad = IncomingNote(
        guid: 'g2',
        type: NoteType.cloze,
        fields: NoteFields({'text': 'sans trou'}),
        createdAtMs: 1,
        updatedAtMs: 1,
      );
      final path = write(
        'mix.carabin',
        buildCarabinPackage(
          decks: [
            IncomingDeck(name: 'Mix', notes: [good, bad]),
          ],
          progress: false,
          media: a.media,
        ),
      );
      final r = b.import(path);
      expect(r.notesAdded, 1);
      expect(r.notesSkipped, 1);
    });

    test(
      'une image dont le nom ne correspond pas au contenu est renommée partout',
      () {
        final png = solidPng(5, 5);
        final real = MediaStore.nameFor(png, 'png');
        final fake = '1111111111111111aaaa.png';
        final path = zip({
          'manifest.json': json({'format': 'carabin-decks', 'version': 1}),
          'decks.json': json({
            'decks': [
              {
                'name': 'Img',
                'notes': [
                  {
                    'guid': 'g1',
                    'type': 'basic',
                    'fields': {'front': 'Voir [img:$fake]', 'back': 'ok'},
                    'created': 1,
                    'updated': 1,
                  },
                  {
                    'guid': 'g2',
                    'type': 'occlusion',
                    'fields': {
                      'image': fake,
                      'masks': [
                        {'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.2},
                      ],
                    },
                    'created': 1,
                    'updated': 1,
                  },
                ],
              },
            ],
          }),
          'media/$fake': png,
        });
        b.import(path);
        final notes = b.repo.notes(b.repo.decks().single.id);
        expect(notes[0].fields.text('front'), 'Voir [img:$real]');
        expect(notes[1].fields.image, real);
        expect(b.media.exists(real), isTrue);
      },
    );

    test('un nom de média avec un chemin est écarté (pas d\'écriture hors du dossier)', () {
      final path = zip({
        'manifest.json': json({'format': 'carabin-decks', 'version': 1}),
        'decks.json': json({'decks': []}),
        'media/../../evil.png': solidPng(2, 2),
        'media/sous/dossier.png': solidPng(2, 2),
        'media/lisez-moi.txt': [1, 2, 3],
      });
      final parsed = readCarabinPackage(path, b.media.dir);
      expect(parsed.mediaAdded, 0);
      expect(parsed.mediaSkipped, 3);
      expect(File(p.join(tmp.path, 'evil.png')).existsSync(), isFalse);
    });
  });

  test('nom de fichier proposé', () {
    expect(packageFileName('Anatomie'), 'Anatomie.carabin');
    expect(
      packageFileName('Cœur / vaisseaux: S1?'),
      'Cœur _ vaisseaux_ S1_.carabin',
    );
    expect(packageFileName('   '), 'paquet.carabin');
  });
}
