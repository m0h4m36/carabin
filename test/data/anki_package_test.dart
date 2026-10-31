import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:carabin/data/anki_package.dart';
import 'package:carabin/data/carabin_package.dart';
import 'package:carabin/data/errors.dart';
import 'package:carabin/data/media_store.dart';
import 'package:carabin/domain/exchange.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/png.dart';

const _crt = 1700000000;
const _unnamed = 'Sans nom';

late Directory tmp;
late String mediaDir;

ParsedPackage read(String path, {bool progress = true}) => readAnkiPackage(
  path,
  mediaDir,
  withProgress: progress,
  unnamedDeck: _unnamed,
  nowMs: 1800000000000,
);

IncomingNote noteOf(ParsedPackage r, String guid) => [
  for (final d in r.decks) ...d.notes,
].firstWhere((n) => n.guid == guid, orElse: () => fail('note $guid absente'));

IncomingDeck deckOf(ParsedPackage r, String name) => r.decks.firstWhere(
  (d) => d.name == name,
  orElse: () => fail('paquet $name absent'),
);

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('carabin_anki_test_');
    mediaDir = p.join(tmp.path, 'media');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('format récent (zstd, schéma 18, protobuf)', () {
    late ParsedPackage r;
    setUp(() => r = read('test/fixtures/anki_latest.apkg'));

    test('paquets : hiérarchie aplatie, paquet filtré résolu, par défaut', () {
      expect(r.decks.map((d) => d.name), ['Cardio › Cœur', 'Par défaut']);
      expect(deckOf(r, 'Par défaut').notes.single.guid, 'anki-guidDefault10');
      expect(r.hasProgress, isTrue);
    });

    test('décomptes', () {
      // type de note inconnu + trous imbriqués
      expect(r.notesSkipped, 2);
      expect(r.soundsDropped, 1);
      expect(r.imagesDropped, 0);
      expect(r.mediaAdded, 2);
      expect(r.mediaSkipped, 0);
      expect(r.shapesApproximated, 1);
      expect(r.shapesDropped, 0);
    });

    test('Basique : mise en forme, image, étiquettes', () {
      final n = noteOf(r, 'anki-guidBasic01');
      expect(n.type, NoteType.basic);
      expect(n.fields.text('front'), '**Aorte**');
      final back = n.fields.text('back');
      expect(back, startsWith('Naît du *VG*'));
      final media = noteMedia(n.fields).toList();
      expect(media.length, 1);
      expect(MediaStore(mediaDir).exists(media.single), isTrue);
      expect(n.tags, ['anat', 'cœur::valves']);
      expect(n.cards, isEmpty);
      expect(n.createdAtMs, 1700000000001);
      expect(n.updatedAtMs, 1700100000 * 1000);
    });

    test('carte inversée : une note réciproque, avancement par carte', () {
      final n = noteOf(r, 'anki-guidRevers02');
      expect(n.type, NoteType.reversed);
      expect(n.fields.text('front'), 'Systole');
      expect(n.fields.text('back'), 'Contraction');
      expect(n.cards.length, 2);

      final c0 = n.cards.firstWhere((c) => c.ord == 0);
      expect(c0.schedule.state, CardState.review);
      expect(c0.schedule.stability, 31.5);
      expect(c0.schedule.difficulty, 4.2);
      expect(c0.schedule.dueMs, (_crt + 50 * 86400) * 1000);
      expect(c0.schedule.reps, 6);
      expect(c0.schedule.lapses, 1);
      expect(c0.suspended, isFalse);
      // le report manuel est écarté
      expect(c0.logs.length, 3);
      expect(c0.logs.map((l) => l.stateBefore), [
        CardState.newCard,
        CardState.review,
        CardState.review,
      ]);
      expect(c0.logs.map((l) => l.rating), [3, 3, 1]);
      expect(c0.schedule.lastReviewMs, c0.logs.last.atMs);

      final c1 = n.cards.firstWhere((c) => c.ord == 1);
      expect(c1.suspended, isTrue);
      expect(c1.schedule.isNew, isTrue);
      expect(c1.logs, isEmpty);
    });

    test('texte à trous : numéros décalés d\'un cran, complément', () {
      final n = noteOf(r, 'anki-guidCloze03');
      expect(n.type, NoteType.cloze);
      expect(
        n.fields.text('text'),
        'Le {{c1::cœur}} bat **{{c2::60}}** fois/min',
      );
      expect(n.fields.extra, 'Normal au repos');
      expect(clozeNumbers(n.fields.text('text')), [1, 2]);
      expect(validateNote(n.type, n.fields), isNull);
      // la carte d'ordre 0 d'Anki est le trou n° 1 de Carabin
      expect(n.cards.single.ord, 1);
      expect(n.cards.single.schedule.stability, 7);
      expect(n.cards.single.schedule.difficulty, closeTo(5, 1e-9));
    });

    test('trous imbriqués : écartés', () {
      final all = [for (final d in r.decks) ...d.notes.map((n) => n.guid)];
      expect(all, isNot(contains('anki-guidNested04')));
      expect(all, isNot(contains('anki-guidGhost08')));
    });

    test('occlusion d\'image intégrée à Anki', () {
      final n = noteOf(r, 'anki-guidOcc05');
      expect(n.type, NoteType.occlusion);
      expect(n.fields.occlusionMode, OcclusionMode.group);
      expect(n.fields.masks.length, 3);
      expect(n.fields.masks.map((m) => m.group), [1, 2, 2]);
      expect(n.fields.masks.map((m) => m.id), [1, 2, 3]);
      expect(n.fields.text('context'), 'Cœur');
      expect(n.fields.extra, 'Vue de face');
      expect(MediaStore(mediaDir).exists(n.fields.image), isTrue);
      expect(cardOrdinals(n.type, n.fields), [1, 2]);
      expect(validateNote(n.type, n.fields), isNull);
      expect(n.tags, ['schema']);
    });

    test('type personnalisé : une note par carte', () {
      final a = noteOf(r, 'anki-guidCustom06-0');
      expect(a.type, NoteType.basic);
      expect(a.fields.text('front'), 'Ventricule gauche');
      expect(a.fields.text('back'), 'Pompe vers l\'aorte');
      final b = noteOf(r, 'anki-guidCustom06-1');
      expect(b.fields.text('front'), startsWith('[img:'));
      expect(b.fields.text('back'), 'Ventricule gauche');
    });

    test('saisie de la réponse', () {
      final n = noteOf(r, 'anki-guidTyped07');
      expect(n.type, NoteType.typed);
      expect(n.fields.text('front'), 'Capitale de la France ?');
      expect(n.fields.text('back'), 'Paris');
    });

    test('carte d\'un paquet filtré : échéance d\'origine', () {
      final n = noteOf(r, 'anki-guidFiltered09');
      expect(deckOf(r, 'Cardio › Cœur').notes, contains(n));
      expect(n.cards.single.schedule.dueMs, (_crt + 90 * 86400) * 1000);
      expect(n.cards.single.schedule.stability, 5);
    });

    test('toutes les notes lues sont valides', () {
      for (final d in r.decks) {
        for (final n in d.notes) {
          expect(validateNote(n.type, n.fields), isNull, reason: n.guid);
        }
      }
    });

    test('sans l\'avancement : aucune carte, rien d\'autre ne change', () {
      final s = read('test/fixtures/anki_latest.apkg', progress: false);
      expect(s.hasProgress, isFalse);
      expect([
        for (final d in s.decks) ...d.notes.expand((n) => n.cards),
      ], isEmpty);
      expect(
        [for (final d in s.decks) ...d.notes.map((n) => n.guid)],
        [for (final d in r.decks) ...d.notes.map((n) => n.guid)],
      );
    });

    test('importer deux fois ne duplique pas les images', () {
      final before = Directory(mediaDir).listSync().length;
      read('test/fixtures/anki_latest.apkg');
      expect(Directory(mediaDir).listSync().length, before);
    });
  });

  group('fichiers inutilisables', () {
    ExchangeError? failure(void Function() f) {
      try {
        f();
      } on ExchangeError catch (e) {
        return e;
      }
      return null;
    }

    test('pas une archive', () {
      final f = File(p.join(tmp.path, 'x.apkg'))
        ..writeAsStringSync('pas un zip');
      expect(failure(() => read(f.path))?.problem, ImportProblem.unreadable);
    });

    test('archive sans collection', () {
      final z = Archive()
        ..addFile(ArchiveFile.bytes('autre.txt', utf8.encode('x')));
      final f = File(p.join(tmp.path, 'x.apkg'))
        ..writeAsBytesSync(ZipEncoder().encodeBytes(z));
      expect(failure(() => read(f.path))?.problem, ImportProblem.unreadable);
    });

    test('seul le fichier de remplacement : refaire l\'export compatible', () {
      final z = _rewrite(
        'test/fixtures/anki_latest.apkg',
        drop: {'collection.anki21b'},
      );
      final f = File(p.join(tmp.path, 'x.apkg'))..writeAsBytesSync(z);
      expect(
        failure(() => read(f.path))?.problem,
        ImportProblem.ankiNeedsOlderFormat,
      );
    });

    test('collection zstd abîmée', () {
      final z = _rewrite(
        'test/fixtures/anki_latest.apkg',
        replace: {
          'collection.anki21b': Uint8List.fromList([
            0x28,
            0xB5,
            0x2F,
            0xFD,
            1,
            2,
            3,
            4,
            5,
            6,
          ]),
        },
      );
      final f = File(p.join(tmp.path, 'x.apkg'))..writeAsBytesSync(z);
      expect(
        failure(() => read(f.path))?.problem,
        ImportProblem.ankiNeedsOlderFormat,
      );
    });

    test('collection qui n\'est pas une base SQLite', () {
      final z = _rewrite(
        'test/fixtures/anki_latest.apkg',
        drop: {'collection.anki21b'},
        replace: {'collection.anki2': Uint8List.fromList(List.filled(200, 7))},
      );
      final f = File(p.join(tmp.path, 'x.apkg'))..writeAsBytesSync(z);
      expect(failure(() => read(f.path))?.problem, ImportProblem.corrupt);
    });

    test('paquet sans aucune note', () {
      final f = _legacyPackage(tmp, notes: (db) {});
      expect(failure(() => read(f))?.problem, ImportProblem.empty);
    });
  });

  group('ancien format (collection.anki2, médias en JSON)', () {
    test('lit notes, paquets hiérarchiques, médias et apprentissage', () {
      final img = tinyPng();
      final path = _legacyPackage(
        tmp,
        media: {
          '0': ('photo 1.png', img),
          '1': ('fond.svg', Uint8List.fromList([1, 2, 3])),
        },
        notes: (db) {
          db.execute(
            "INSERT INTO notes VALUES (10, 'g-basic', 1, 1700100000, 0, ' t1 ', ?, 0, 0, 0, '')",
            [
              '<div>Q1</div>\x1f<div>R1 <img src="photo%201.png"> <img src="fond.svg"> <img src="http://x.test/a.png"></div>',
            ],
          );
          _card(db, 100, 10, 2, 0);
          // apprentissage en cours : repart de zéro, mais l'historique reste
          db.execute(
            "INSERT INTO notes VALUES (11, 'g-learn', 1, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['Q2\x1fR2'],
          );
          _card(db, 110, 11, 2, 0, type: 1, queue: 1, due: 1700500000, ivl: 0);
          db.execute(
            'INSERT INTO revlog VALUES (1700400000000, 110, 0, 1, -60, 0, 0, 2000, 0)',
          );
          // paquet inexistant dans la table des paquets
          db.execute(
            "INSERT INTO notes VALUES (12, 'g-lost', 1, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['Q3\x1fR3'],
          );
          _card(db, 120, 12, 77, 0);
          // mis en attente (-2) : pas suspendue
          db.execute(
            "INSERT INTO notes VALUES (13, 'g-buried', 1, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['Q4\x1fR4'],
          );
          _card(
            db,
            130,
            13,
            2,
            0,
            type: 2,
            queue: -2,
            due: 10,
            ivl: 9,
            factor: 0,
          );
        },
      );
      final r = read(path);
      expect(r.decks.map((d) => d.name), ['Cours › Anatomie', _unnamed]);

      final basic = noteOf(r, 'anki-g-basic');
      expect(basic.fields.text('front'), 'Q1');
      expect(basic.tags, ['t1']);
      expect(noteMedia(basic.fields).length, 1);
      expect(
        MediaStore(mediaDir).exists(noteMedia(basic.fields).single),
        isTrue,
      );
      // svg et adresse distante : comptés, pas importés
      expect(r.imagesDropped, 2);
      expect(r.mediaAdded, 1);
      expect(r.mediaSkipped, 2);

      final learn = noteOf(r, 'anki-g-learn');
      expect(learn.cards.single.schedule.isNew, isTrue);
      expect(learn.cards.single.logs.single.stateBefore, CardState.newCard);

      expect(deckOf(r, _unnamed).notes.single.guid, 'anki-g-lost');

      final buried = noteOf(r, 'anki-g-buried');
      expect(buried.cards.single.suspended, isFalse);
      expect(buried.cards.single.schedule.stability, 9);
      expect(buried.cards.single.schedule.difficulty, closeTo(5, 1e-9));
    });

    test('image en data: et nom d\'image avec pourcentage invalide', () {
      final b64 = base64Encode(tinyPng());
      final path = _legacyPackage(
        tmp,
        notes: (db) {
          db.execute(
            "INSERT INTO notes VALUES (10, 'g1', 1, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['<img src="data:image/png;base64,$b64">\x1f<img src="100%.png">'],
          );
          _card(db, 100, 10, 2, 0);
        },
      );
      final r = read(path);
      final n = noteOf(r, 'anki-g1');
      expect(noteMedia(n.fields).length, 1);
      expect(r.imagesDropped, 1);
    });

    test('type personnalisé à une carte, filtres et sections', () {
      final path = _legacyPackage(
        tmp,
        models: {
          '5': {
            'id': 5,
            'name': 'Médicament',
            'type': 0,
            'flds': [
              {'name': 'DCI', 'ord': 0},
              {'name': 'Classe', 'ord': 1},
              {'name': 'Indice', 'ord': 2},
            ],
            'tmpls': [
              {
                'name': 'C1',
                'ord': 0,
                'qfmt': '{{DCI}}{{#Indice}} ({{hint:Indice}}){{/Indice}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{text:Classe}}',
              },
            ],
          },
        },
        notes: (db) {
          db.execute(
            "INSERT INTO notes VALUES (10, 'g-med', 5, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['Aténolol\x1f<b>Bêta</b>-bloquant\x1f'],
          );
          _card(db, 100, 10, 2, 0);
        },
      );
      final n = noteOf(read(path), 'anki-g-med');
      expect(n.type, NoteType.basic);
      expect(n.fields.text('front'), 'Aténolol');
      expect(n.fields.text('back'), 'Bêta-bloquant');
    });

    test('modèle sans modèle de carte pour la carte : écartée', () {
      final path = _legacyPackage(
        tmp,
        notes: (db) {
          db.execute(
            "INSERT INTO notes VALUES (10, 'g-ok', 1, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['Q\x1fR'],
          );
          _card(db, 100, 10, 2, 0);
          db.execute(
            "INSERT INTO notes VALUES (11, 'g-orphan', 1, 1700100000, 0, '', ?, 0, 0, 0, '')",
            ['Q\x1fR'],
          );
          _card(
            db,
            110,
            11,
            2,
            5,
          ); // ordre 5 : le modèle n'a qu'un modèle de carte
        },
      );
      final r = read(path);
      expect(r.notesSkipped, 1);
      expect(deckOf(r, 'Cours › Anatomie').notes.single.guid, 'anki-g-ok');
    });
  });
}

// ----------------------------------------------------------------- aides

Uint8List tinyPng() => solidPng(4, 4);

/// Réécrit un paquet en retirant ou remplaçant des fichiers.
Uint8List _rewrite(
  String path, {
  Set<String> drop = const {},
  Map<String, Uint8List> replace = const {},
}) {
  final src = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final out = Archive();
  for (final f in src.files) {
    if (!f.isFile || drop.contains(f.name)) continue;
    out.addFile(ArchiveFile.bytes(f.name, replace[f.name] ?? f.readBytes()!));
  }
  for (final e in replace.entries) {
    if (!out.files.any((f) => f.name == e.key)) {
      out.addFile(ArchiveFile.bytes(e.key, e.value));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

void _card(
  Database db,
  int id,
  int nid,
  int did,
  int ord, {
  int type = 0,
  int queue = 0,
  int due = 1,
  int ivl = 0,
  int factor = 0,
}) {
  db.execute(
    'INSERT INTO cards VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, ?)',
    [id, nid, did, ord, type, queue, due, ivl, factor, ''],
  );
}

/// Fabrique un `.apkg` à l'ancien format (schéma 11) avec un type « Basique »
/// (id 1) et deux paquets (id 2 « Cours::Anatomie », id 3 filtré).
String _legacyPackage(
  Directory dir, {
  required void Function(Database db) notes,
  Map<String, Object?> models = const {},
  Map<String, (String, Uint8List)> media = const {},
}) {
  final dbPath = p.join(
    dir.path,
    'legacy-${DateTime.now().microsecondsSinceEpoch}.sqlite',
  );
  final db = sqlite3.open(dbPath);
  db.execute('''
    CREATE TABLE col (id integer PRIMARY KEY, crt integer NOT NULL, mod integer NOT NULL,
      scm integer NOT NULL, ver integer NOT NULL, dty integer NOT NULL, usn integer NOT NULL,
      ls integer NOT NULL, conf text NOT NULL, models text NOT NULL, decks text NOT NULL,
      dconf text NOT NULL, tags text NOT NULL);
    CREATE TABLE notes (id integer PRIMARY KEY, guid text NOT NULL, mid integer NOT NULL,
      mod integer NOT NULL, usn integer NOT NULL, tags text NOT NULL, flds text NOT NULL,
      sfld integer NOT NULL, csum integer NOT NULL, flags integer NOT NULL, data text NOT NULL);
    CREATE TABLE cards (id integer PRIMARY KEY, nid integer NOT NULL, did integer NOT NULL,
      ord integer NOT NULL, mod integer NOT NULL, usn integer NOT NULL, type integer NOT NULL,
      queue integer NOT NULL, due integer NOT NULL, ivl integer NOT NULL, factor integer NOT NULL,
      reps integer NOT NULL, lapses integer NOT NULL, left integer NOT NULL, odue integer NOT NULL,
      odid integer NOT NULL, flags integer NOT NULL, data text NOT NULL);
    CREATE TABLE revlog (id integer PRIMARY KEY, cid integer NOT NULL, usn integer NOT NULL,
      ease integer NOT NULL, ivl integer NOT NULL, lastIvl integer NOT NULL, factor integer NOT NULL,
      time integer NOT NULL, type integer NOT NULL);
  ''');
  final allModels = <String, Object?>{
    '1': {
      'id': 1,
      'name': 'Basique',
      'type': 0,
      'flds': [
        {'name': 'Recto', 'ord': 0},
        {'name': 'Verso', 'ord': 1},
      ],
      'tmpls': [
        {
          'name': 'Carte 1',
          'ord': 0,
          'qfmt': '{{Recto}}',
          'afmt': '{{FrontSide}}<hr id=answer>{{Verso}}',
        },
      ],
    },
    ...models,
  };
  final decks = {
    '2': {'id': 2, 'name': 'Cours::Anatomie', 'dyn': 0},
    '3': {'id': 3, 'name': 'Filtré', 'dyn': 1},
  };
  db.execute(
    "INSERT INTO col VALUES (1, $_crt, 0, 0, 11, 0, 0, 0, '{}', ?, ?, '{}', '{}')",
    [jsonEncode(allModels), jsonEncode(decks)],
  );
  notes(db);
  db.close();

  final z = Archive();
  z.addFile(
    ArchiveFile.bytes('collection.anki2', File(dbPath).readAsBytesSync()),
  );
  z.addFile(
    ArchiveFile.bytes(
      'media',
      utf8.encode(
        jsonEncode({for (final e in media.entries) e.key: e.value.$1}),
      ),
    ),
  );
  for (final e in media.entries) {
    z.addFile(ArchiveFile.bytes(e.key, e.value.$2));
  }
  final out = p.join(
    dir.path,
    'legacy-${DateTime.now().microsecondsSinceEpoch}.apkg',
  );
  File(out).writeAsBytesSync(ZipEncoder().encodeBytes(z));
  return out;
}
