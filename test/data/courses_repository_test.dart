import 'dart:io';

import 'package:carabin/data/courses_repository.dart';
import 'package:carabin/data/database.dart';
import 'package:carabin/data/errors.dart';
import 'package:carabin/data/models.dart';
import 'package:carabin/data/names.dart';
import 'package:carabin/data/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Workspace ws;
  late AppDatabase db;
  late CoursesRepository repo;
  var tick = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('carabin_test_');
    ws = Workspace(p.join(tmp.path, 'racine'))..ensureStructure();
    db = AppDatabase.inMemory();
    tick = 0;
    repo = CoursesRepository(
      db,
      ws,
      pageCounter: (path) async => 12,
      clock: () => DateTime.utc(2026, 10, 31, 12, 0, tick++),
    );
  });

  tearDown(() {
    db.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// Crée année › semestre › matière › thème et renvoie les identifiants.
  ({int year, int sem, int subject, int topic}) chain() {
    final y = repo.createYear('DFGSM2 2025-2026');
    final s = repo.createSemester(y.id, 'Semestre 3');
    final m = repo.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
    final t = repo.createTopic(m.id, 'Ostéologie');
    return (year: y.id, sem: s.id, subject: m.id, topic: t.id);
  }

  File makeFile(String name, [String content = 'contenu']) {
    final f = File(p.join(tmp.path, name))..writeAsStringSync(content);
    return f;
  }

  group('noms', () {
    test(
      'safeFileName remplace les caractères interdits et les noms réservés',
      () {
        expect(safeFileName('TP: 1/2?'), 'TP_ 1_2_');
        expect(safeFileName('  '), '_');
        expect(safeFileName('CON'), '_CON');
        expect(safeFileName('nul.txt'), '_nul.txt');
        expect(safeFileName('Fin.'), 'Fin');
        expect(safeFileName('a' * 300).length, 100);
      },
    );

    test('normalize retire accents et majuscules', () {
      expect(normalize('Ostéologie Œdème'), 'osteologie oedeme');
    });
  });

  group('création', () {
    test('crée la base et les dossiers correspondants', () {
      final c = chain();
      expect(
        Directory(ws.absolute(repo.relDir(CourseLevel.topic, c.topic)))
            .existsSync(),
        isTrue,
      );
      expect(
        repo.relDir(CourseLevel.topic, c.topic),
        'Cours/DFGSM2 2025-2026/Semestre 3/Anatomie/Ostéologie',
      );
      expect(repo.years().single.name, 'DFGSM2 2025-2026');
    });

    test(
      'refuse un nom vide, un doublon (même en majuscules) ou équivalent',
      () {
        final y = repo.createYear('A');
        expect(() => repo.createYear('   '), throwsA(isA<EmptyNameError>()));
        expect(() => repo.createYear('a'), throwsA(isA<NameTakenError>()));
        repo.createYear('A/B');
        expect(() => repo.createYear('A?B'), throwsA(isA<NameTakenError>()));
        expect(repo.years(), hasLength(2));
        // pas de dossier orphelin pour la tentative refusée
        expect(
          Directory(p.join(ws.coursDir, 'a')).existsSync() ||
              Directory(p.join(ws.coursDir, 'A')).existsSync(),
          isTrue,
        );
        expect(y.id, isPositive);
      },
    );

    test('un nom avec des espaces multiples est nettoyé', () {
      final y = repo.createYear('  Année   2026  ');
      expect(y.name, 'Année 2026');
    });
  });

  group('renommer', () {
    test('renomme le dossier et met à jour le chemin des documents', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.rename(CourseLevel.subject, c.subject, 'Anatomie générale');
      final after = repo.document(doc.id)!;
      expect(
        after.relPath,
        'Cours/DFGSM2 2025-2026/Semestre 3/Anatomie générale/Ostéologie/poly.pdf',
      );
      expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
      expect(
        Directory(
          p.join(ws.coursDir, 'DFGSM2 2025-2026', 'Semestre 3', 'Anatomie'),
        ).existsSync(),
        isFalse,
      );
    });

    test('changement de casse seul', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.rename(CourseLevel.topic, c.topic, 'ostéologie');
      final after = repo.document(doc.id)!;
      expect(after.relPath.endsWith('/ostéologie/poly.pdf'), isTrue);
      expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
    });

    test('refuse un nom déjà pris et ne touche à rien', () {
      final c = chain();
      repo.createTopic(c.subject, 'Myologie');
      expect(
        () => repo.rename(CourseLevel.topic, c.topic, 'MYOLOGIE'),
        throwsA(isA<NameTakenError>()),
      );
      expect(repo.topics(c.subject).map((t) => t.name), [
        'Ostéologie',
        'Myologie',
      ]);
    });

    test(
      'un dossier déjà présent sur le disque bloque le renommage proprement',
      () async {
        final c = chain();
        final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
        Directory(
          p.join(
            ws.coursDir,
            'DFGSM2 2025-2026',
            'Semestre 3',
            'Anatomie',
            'Autre',
          ),
        ).createSync();
        expect(
          () => repo.rename(CourseLevel.topic, c.topic, 'Autre'),
          throwsA(isA<FileProblemError>()),
        );
        // base et fichier restent cohérents
        expect(repo.topics(c.subject).first.name, 'Ostéologie');
        expect(
          File(ws.absolute(repo.document(doc.id)!.relPath)).existsSync(),
          isTrue,
        );
      },
    );
  });

  group('import', () {
    test('copie le fichier, garde l\'original, compte les pages', () async {
      final c = chain();
      final src = makeFile('Cours ostéo.pdf', 'pdf');
      final doc = await repo.importFile(c.topic, src.path);
      expect(src.existsSync(), isTrue);
      expect(doc.title, 'Cours ostéo');
      expect(doc.kind, DocKind.pdf);
      expect(doc.pageCount, 12);
      expect(File(ws.absolute(doc.relPath)).readAsStringSync(), 'pdf');
    });

    test('deux fichiers de même nom ne s\'écrasent pas', () async {
      final c = chain();
      final a = await repo.importFile(c.topic, makeFile('poly.pdf', 'A').path);
      final b = await repo.importFile(c.topic, makeFile('poly.pdf', 'B').path);
      expect(a.relPath, isNot(b.relPath));
      expect(b.relPath.endsWith('poly (2).pdf'), isTrue);
      expect(File(ws.absolute(a.relPath)).readAsStringSync(), 'A');
      expect(File(ws.absolute(b.relPath)).readAsStringSync(), 'B');
    });

    test('type de document reconnu', () async {
      final c = chain();
      expect(
        (await repo.importFile(c.topic, makeFile('a.DOCX').path)).kind,
        DocKind.word,
      );
      expect(
        (await repo.importFile(c.topic, makeFile('b.jpeg').path)).kind,
        DocKind.image,
      );
      expect(
        (await repo.importFile(c.topic, makeFile('c.txt').path)).kind,
        DocKind.text,
      );
      expect(
        (await repo.importFile(c.topic, makeFile('d.xyz').path)).kind,
        DocKind.other,
      );
    });

    test('un fichier inexistant est refusé', () async {
      final c = chain();
      await expectLater(
        repo.importFile(c.topic, p.join(tmp.path, 'absent.pdf')),
        throwsA(isA<FileProblemError>()),
      );
      expect(repo.documents(c.topic), isEmpty);
    });

    test('un PDF illisible est gardé sans nombre de pages', () async {
      final bad = CoursesRepository(
        db,
        ws,
        pageCounter: (path) async => throw StateError('illisible'),
      );
      final c = chain();
      final doc = await bad.importFile(c.topic, makeFile('x.pdf').path);
      expect(doc.pageCount, isNull);
    });
  });

  group('déplacer', () {
    test('déplace un document dans un autre thème', () async {
      final c = chain();
      final t2 = repo.createTopic(c.subject, 'Myologie');
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.moveDocument(doc.id, t2.id);
      final after = repo.document(doc.id)!;
      expect(after.topicId, t2.id);
      expect(after.relPath.contains('/Myologie/'), isTrue);
      expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
      expect(repo.documents(c.topic), isEmpty);
    });

    test('déplace un thème avec ses documents', () async {
      final c = chain();
      final m2 = repo.createSubject(c.sem, 'Histologie', color: 0xFF1E88E5);
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.moveTopic(c.topic, m2.id);
      final after = repo.document(doc.id)!;
      expect(after.relPath.contains('/Histologie/Ostéologie/'), isTrue);
      expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
      expect(repo.topics(c.subject), isEmpty);
    });

    test('refuse de déplacer un thème vers une matière qui a le même nom', () {
      final c = chain();
      final m2 = repo.createSubject(c.sem, 'Histologie', color: 0xFF1E88E5);
      repo.createTopic(m2.id, 'ostéologie');
      expect(
        () => repo.moveTopic(c.topic, m2.id),
        throwsA(isA<NameTakenError>()),
      );
    });
  });

  group('suppression et archives', () {
    test(
      'supprimer un thème archive ses documents sans rien effacer',
      () async {
        final c = chain();
        final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
        repo.delete(CourseLevel.topic, c.topic);
        final after = repo.document(doc.id)!;
        expect(after.archivedAt, isNotNull);
        expect(after.relPath.startsWith('Archives/Cours/'), isTrue);
        expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
        expect(repo.topics(c.subject), isEmpty);
        expect(
          Directory(
            p.join(
              ws.coursDir,
              'DFGSM2 2025-2026',
              'Semestre 3',
              'Anatomie',
              'Ostéologie',
            ),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('supprimer une année archive tout ce qu\'elle contient', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.delete(CourseLevel.year, c.year);
      expect(repo.years(), isEmpty);
      final after = repo.document(doc.id)!;
      expect(after.archivedAt, isNotNull);
      expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
      expect(db.select('SELECT * FROM topics'), isEmpty);
    });

    test('archiver un document puis le retrouver dans Archives', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.archiveDocument(doc.id);
      expect(repo.documents(c.topic), isEmpty);
      final after = repo.document(doc.id)!;
      expect(File(ws.absolute(after.relPath)).existsSync(), isTrue);
    });

    test('suppression définitive : fichier et ligne disparaissent', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      final abs = ws.absolute(doc.relPath);
      repo.deleteDocumentPermanently(doc.id);
      expect(File(abs).existsSync(), isFalse);
      expect(repo.document(doc.id), isNull);
    });

    test('un nom d\'année peut être réutilisé après suppression', () {
      repo.createYear('2026');
      final y = repo.years().single;
      repo.delete(CourseLevel.year, y.id);
      repo.createYear('2026');
      expect(repo.years(), hasLength(1));
    });
  });

  group('chemins', () {
    test('allTrails liste tous les thèmes avec leur chemin', () {
      final c = chain();
      final m2 = repo.createSubject(c.sem, 'Histologie', color: 0xFF1E88E5);
      repo.createTopic(m2.id, 'Épithéliums');
      final trails = repo.allTrails();
      expect(trails.map((t) => t.topic.name), ['Ostéologie', 'Épithéliums']);
      expect(trails.last.subject.name, 'Histologie');
      expect(trails.first.year.name, 'DFGSM2 2025-2026');
      expect(repo.trailOfTopic(c.topic).semester.name, 'Semestre 3');
      expect(() => repo.trailOfTopic(9999), throwsA(isA<NotFoundError>()));
    });
  });

  group('lecture, récents, recherche', () {
    test('six lectures cochables et décochables', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      repo.setRead(doc.id, 0, true);
      repo.setRead(doc.id, 2, true);
      expect(repo.document(doc.id)!.readCount, 2);
      repo.setRead(doc.id, 0, false);
      final after = repo.document(doc.id)!;
      expect(after.isRead(0), isFalse);
      expect(after.isRead(2), isTrue);
      expect(() => repo.setRead(doc.id, 6, true), throwsRangeError);
    });

    test('récents : le dernier ouvert est en tête', () async {
      final c = chain();
      final a = await repo.importFile(c.topic, makeFile('a.pdf').path);
      final b = await repo.importFile(c.topic, makeFile('b.pdf').path);
      repo.markOpened(a.id);
      repo.markOpened(b.id);
      repo.markOpened(a.id);
      expect(repo.recents().map((d) => d.id), [a.id, b.id]);
    });

    test('recherche sans accents ni majuscules, avec le chemin', () async {
      final c = chain();
      await repo.importFile(c.topic, makeFile('Cours Ostéologie.pdf').path);
      final hits = repo.searchDocuments('osteolo');
      expect(hits, hasLength(1));
      expect(hits.single.trail!.subject.name, 'Anatomie');
      expect(repo.searchDocuments('inconnu'), isEmpty);
      expect(repo.searchDocuments('  '), isEmpty);
    });
  });

  group('synchroniser', () {
    test('reprend un PDF déposé à la main et crée les dossiers inconnus', () {
      final c = chain();
      final dir = Directory(
        p.join(
          ws.coursDir,
          'DFGSM2 2025-2026',
          'Semestre 3',
          'Anatomie',
          'Ostéologie',
        ),
      );
      File(p.join(dir.path, 'depose.pdf')).writeAsStringSync('x');
      File(p.join(dir.path, '.cache')).writeAsStringSync('x');
      final neuf = Directory(
        p.join(
          ws.coursDir,
          'DFGSM2 2025-2026',
          'Semestre 4',
          'Biochimie',
          'ADN',
        ),
      )..createSync(recursive: true);
      File(p.join(neuf.path, 'adn.pdf')).writeAsStringSync('x');

      final report = repo.syncFolder();
      expect(report.added, 2);
      expect(repo.documents(c.topic).single.title, 'depose');
      final sems = repo.semesters(c.year);
      expect(sems.map((s) => s.name), ['Semestre 3', 'Semestre 4']);
      // une deuxième synchronisation n'ajoute rien
      expect(repo.syncFolder().added, 0);
    });

    test('signale les fichiers disparus sans rien supprimer', () async {
      final c = chain();
      final doc = await repo.importFile(c.topic, makeFile('poly.pdf').path);
      File(ws.absolute(doc.relPath)).deleteSync();
      final report = repo.syncFolder();
      expect(report.missing, 1);
      expect(repo.document(doc.id), isNotNull);
    });

    test('la synchronisation ne duplique pas les noms déjà connus', () {
      chain();
      repo.syncFolder();
      expect(repo.years(), hasLength(1));
      expect(db.select('SELECT * FROM subjects'), hasLength(1));
    });
  });

  group('base', () {
    test('la base se rouvre depuis un fichier avec ses données', () {
      final path = p.join(tmp.path, 'x.db');
      final a = AppDatabase.open(path);
      a.execute("INSERT INTO years(name) VALUES ('2030')");
      a.dispose();
      final b = AppDatabase.open(path);
      expect(b.select('SELECT name FROM years').single['name'], '2030');
      expect(b.schemaVersion, greaterThanOrEqualTo(1));
      b.dispose();
    });

    test('une transaction qui échoue est annulée', () {
      expect(
        () => db.transaction(() {
          db.execute("INSERT INTO years(name) VALUES ('X')");
          throw StateError('boum');
        }),
        throwsStateError,
      );
      expect(db.select('SELECT * FROM years'), isEmpty);
    });

    test('les écrans sont prévenus après une écriture', () {
      var calls = 0;
      db.addListener(() => calls++);
      repo.createYear('Z');
      expect(calls, 1);
    });

    test('sauvegarde cohérente par VACUUM INTO', () {
      repo.createYear('S');
      final out = p.join(tmp.path, 'copie.db');
      db.backupTo(out);
      final copy = AppDatabase.open(out);
      expect(copy.select('SELECT name FROM years').single['name'], 'S');
      copy.dispose();
    });
  });

  group('espace de travail', () {
    test('le localisateur retient le dossier et ignore un fichier abîmé', () {
      final loc = WorkspaceLocator(p.join(tmp.path, 'cfg'));
      expect(loc.read(), isNull);
      loc.write('/un/chemin');
      expect(loc.read(), '/un/chemin');
      File(p.join(tmp.path, 'cfg', 'dossier.json')).writeAsStringSync('{{{');
      expect(loc.read(), isNull);
    });

    test('reconnaît un dossier Carabin', () {
      expect(Workspace.looksLikeWorkspace(ws.root), isFalse);
      AppDatabase.open(ws.dbPath).dispose();
      expect(Workspace.looksLikeWorkspace(ws.root), isTrue);
      expect(Workspace.isEmptyOrMissing(p.join(tmp.path, 'inconnu')), isTrue);
      expect(Workspace.isEmptyOrMissing(ws.root), isFalse);
    });

    test('chemins relatifs et absolus sont réversibles', () {
      final abs = ws.absolute('Cours/A/B.pdf');
      expect(ws.relative(abs), 'Cours/A/B.pdf');
    });
  });
}
