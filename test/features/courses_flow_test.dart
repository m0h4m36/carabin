import 'dart:io';

import 'package:carabin/app.dart';
import 'package:carabin/app_session.dart';
import 'package:carabin/data/courses_repository.dart';
import 'package:carabin/data/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_session.dart';

Finder dialogField() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

Future<void> pumpApp(
  WidgetTester tester,
  Session session, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CarabinApp(session: session));
  await tester.tap(find.text('Cours'));
  await tester.pumpAndSettle();
}

Future<void> fillDialog(WidgetTester tester, String text, String button) async {
  await tester.enterText(dialogField().first, text);
  await tester.tap(find.widgetWithText(FilledButton, button));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1280, 800), const Size(390, 800)]) {
    testWidgets(
      'créer année, semestre, matière et thème à la main ($size)',
      (tester) async {
        final session = openTestSession();
        await pumpApp(tester, session, size: size);

        expect(find.text('Aucune année pour l\'instant'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Nouvelle année').first);
        await tester.pumpAndSettle();
        await fillDialog(tester, 'DFGSM2 2025-2026', 'Créer');

        // on est arrivé sur la page de l'année
        expect(find.text('DFGSM2 2025-2026'), findsWidgets);
        expect(find.text('Nouveau semestre'), findsOneWidget);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Nouveau semestre'));
        await tester.pumpAndSettle();
        await fillDialog(tester, 'Semestre 3', 'Créer');
        expect(find.text('Semestre 3'), findsOneWidget);

        await tester.tap(find.text('Nouvelle matière'));
        await tester.pumpAndSettle();
        await fillDialog(tester, 'Anatomie', 'Créer');
        expect(find.text('Anatomie'), findsOneWidget);
        expect(find.text('0 thème · 0 poly'), findsOneWidget);

        await tester.tap(find.text('Anatomie'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Nouveau thème').first);
        await tester.pumpAndSettle();
        await fillDialog(tester, 'Ostéologie', 'Créer');
        expect(find.text('Ostéologie'), findsOneWidget);

        final trail = session.courses.allTrails().single;
        expect(trail.year.name, 'DFGSM2 2025-2026');
        expect(trail.subject.name, 'Anatomie');
        expect(
          Directory(session.workspace.absolute(
            session.courses.relDir(CourseLevel.topic, trail.topic.id),
          )).existsSync(),
          isTrue,
        );
      },
    );
  }

  testWidgets('un nom déjà pris affiche un message clair', (tester) async {
    final session = openTestSession();
    session.courses.createYear('2026');
    await pumpApp(tester, session);
    await tester.tap(find.widgetWithText(FilledButton, 'Nouvelle année').first);
    await tester.pumpAndSettle();
    await fillDialog(tester, '2026', 'Créer');
    expect(find.textContaining('déjà utilisé'), findsOneWidget);
    expect(session.courses.years(), hasLength(1));
  });

  testWidgets('un nom vide affiche un message clair', (tester) async {
    final session = openTestSession();
    await pumpApp(tester, session);
    await tester.tap(find.widgetWithText(FilledButton, 'Nouvelle année').first);
    await tester.pumpAndSettle();
    await fillDialog(tester, '   ', 'Créer');
    expect(find.text('Le nom ne peut pas être vide.'), findsOneWidget);
  });

  testWidgets('les documents d\'un thème s\'affichent et les lectures se cochent',
      (tester) async {
    final session = openTestSession();
    final c = session.courses;
    final y = c.createYear('2026');
    final s = c.createSemester(y.id, 'S1');
    final m = c.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
    final t = c.createTopic(m.id, 'Ostéo');
    final src = File(p.join(session.workspace.root, '..', 'poly.pdf'))
      ..writeAsStringSync('x');
    final doc = await tester.runAsync(() => c.importFile(t.id, src.path));

    await pumpApp(tester, session);
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anatomie'));
    await tester.pumpAndSettle();
    expect(find.text('poly'), findsOneWidget);
    expect(find.text('0/6'), findsOneWidget);

    await tester.tap(find.text('Ostéo'));
    await tester.pumpAndSettle();
    expect(find.text('pas encore lu'), findsOneWidget);
    // cocher la 2e lecture
    final dots = find.bySemanticsLabel('Lecture 2');
    expect(dots, findsOneWidget);
    await tester.tap(dots);
    await tester.pumpAndSettle();
    expect(c.document(doc!.id)!.isRead(1), isTrue);
    expect(find.text('1 lecture'), findsOneWidget);
    // la décocher
    await tester.tap(find.bySemanticsLabel('Lecture 2'));
    await tester.pumpAndSettle();
    expect(c.document(doc.id)!.readCount, 0);
  });

  testWidgets('la recherche trouve un poly par un bout de son titre',
      (tester) async {
    final session = openTestSession();
    final c = session.courses;
    final y = c.createYear('2026');
    final s = c.createSemester(y.id, 'S1');
    final m = c.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
    final t = c.createTopic(m.id, 'Ostéo');
    final src = File(p.join(session.workspace.root, '..', 'Cours Ostéologie.pdf'))
      ..writeAsStringSync('x');
    await tester.runAsync(() => c.importFile(t.id, src.path));

    await pumpApp(tester, session);
    await tester.enterText(find.byType(TextField).first, 'osteolo');
    await tester.pumpAndSettle();
    expect(find.text('Cours Ostéologie'), findsOneWidget);
    expect(find.textContaining('Anatomie'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat.'), findsOneWidget);
  });

  testWidgets('synchroniser affiche le bilan', (tester) async {
    final session = openTestSession();
    final dir = Directory(p.join(session.workspace.coursDir, 'A', 'B', 'C', 'D'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'x.pdf')).writeAsStringSync('x');
    await pumpApp(tester, session);
    await tester.tap(find.byTooltip('Synchroniser le dossier'));
    await tester.pumpAndSettle();
    expect(find.text('1 fichier ajouté à l\'appli.'), findsOneWidget);
  });

  testWidgets('supprimer une année demande confirmation et archive',
      (tester) async {
    final session = openTestSession();
    session.courses.createYear('2026');
    await pumpApp(tester, session);
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plus d\'options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer « 2026 » ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(session.courses.years(), isEmpty);
    // retour automatique sur l'accueil des cours, vide
    expect(find.text('Aucune année pour l\'instant'), findsOneWidget);
  });

  group('visionneuse', () {
    testWidgets('affiche un fichier texte', (tester) async {
      final session = openTestSession();
      final c = session.courses;
      final y = c.createYear('2026');
      final s = c.createSemester(y.id, 'S1');
      final m = c.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
      final t = c.createTopic(m.id, 'Ostéo');
      final src = File(p.join(session.workspace.root, '..', 'note.txt'))
        ..writeAsStringSync('Le fémur est un os long.');
      final doc = (await tester.runAsync(() => c.importFile(t.id, src.path)))!;

      await pumpApp(tester, session);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anatomie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('note'));
      await tester.pumpAndSettle();
      expect(find.text('Le fémur est un os long.'), findsOneWidget);
      expect(c.document(doc.id)!.lastOpenedAt, isNotNull);
    });

    testWidgets('un fichier disparu du disque est signalé', (tester) async {
      final session = openTestSession();
      final c = session.courses;
      final y = c.createYear('2026');
      final s = c.createSemester(y.id, 'S1');
      final m = c.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
      final t = c.createTopic(m.id, 'Ostéo');
      final src = File(p.join(session.workspace.root, '..', 'poly.pdf'))
        ..writeAsStringSync('x');
      final doc = (await tester.runAsync(() => c.importFile(t.id, src.path)))!;
      File(session.workspace.absolute(doc.relPath)).deleteSync();

      await pumpApp(tester, session);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anatomie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('poly'));
      await tester.pumpAndSettle();
      expect(find.textContaining('introuvable'), findsOneWidget);
    });

    testWidgets('un format non affichable le dit clairement', (tester) async {
      final session = openTestSession();
      final c = session.courses;
      final y = c.createYear('2026');
      final s = c.createSemester(y.id, 'S1');
      final m = c.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
      final t = c.createTopic(m.id, 'Ostéo');
      final src = File(p.join(session.workspace.root, '..', 'devoir.docx'))
        ..writeAsStringSync('x');
      await tester.runAsync(() => c.importFile(t.id, src.path));

      await pumpApp(tester, session);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anatomie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('devoir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ne peut pas être affiché'), findsOneWidget);
    });
  });

  group('premier lancement', () {
    testWidgets('créer le dossier par défaut ouvre l\'appli et mémorise le choix',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('carabin_setup_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final locator = WorkspaceLocator(p.join(tmp.path, 'cfg'));
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        CarabinApp(locator: locator, documentsDir: p.join(tmp.path, 'Documents')),
      );
      expect(find.text('Où ranger vos données ?'), findsOneWidget);
      await tester.tap(find.text('Créer le dossier « Carabin »'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      final root = p.join(tmp.path, 'Documents', 'Carabin');
      expect(locator.read(), root);
      expect(Workspace.looksLikeWorkspace(root), isTrue);
      expect(Directory(p.join(root, 'Cours')).existsSync(), isTrue);
    });

    testWidgets('un dossier existant non Carabin n\'est pas écrasé',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('carabin_setup_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final occupied = Directory(p.join(tmp.path, 'Documents', 'Carabin'))
        ..createSync(recursive: true);
      File(p.join(occupied.path, 'perso.txt')).writeAsStringSync('à moi');
      final locator = WorkspaceLocator(p.join(tmp.path, 'cfg'));
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        CarabinApp(locator: locator, documentsDir: p.join(tmp.path, 'Documents')),
      );
      await tester.tap(find.text('Créer le dossier « Carabin »'));
      await tester.pumpAndSettle();

      // le dossier occupé n'a pas été touché, un autre a été créé à côté
      expect(File(p.join(occupied.path, 'perso.txt')).readAsStringSync(), 'à moi');
      expect(Workspace.looksLikeWorkspace(occupied.path), isFalse);
      expect(
        Workspace.looksLikeWorkspace(p.join(tmp.path, 'Documents', 'Carabin (2)')),
        isTrue,
      );
    });
  });
}
