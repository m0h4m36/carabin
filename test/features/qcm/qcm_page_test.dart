import 'dart:convert';
import 'dart:io';

import 'package:carabin/app_session.dart';
import 'package:carabin/data/background.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:carabin/features/qcm/qcm_page.dart';
import 'package:carabin/ui/pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attempts.dart';
import '../../support/pump_page.dart';
import '../../support/test_session.dart';

const _wide = Size(1300, 900);
const _narrow = Size(400, 860);

ChoiceQuestion q(String body) => ChoiceQuestion(
  body: body,
  propositions: const [
    Proposition(text: 'A', correct: true),
    Proposition(text: 'B'),
  ],
);

Finder card(int id) => find.byKey(ValueKey('exam-$id'));

void main() {
  late Session session;

  setUp(() => session = openTestSession());

  testWidgets('aucune série : invitation à en écrire ou à en recevoir', (
    tester,
  ) async {
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    expect(find.text('Aucune épreuve pour l\'instant'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-new-series')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-import')), findsOneWidget);
    expect(find.byKey(const ValueKey('qcm-tabs')), findsNothing);
  });

  testWidgets('créer une série ouvre son éditeur', (tester) async {
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.tap(find.byKey(const ValueKey('new-series')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Hémostase');
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();
    final exams = session.qcm.exams();
    expect(exams.single.exam.title, 'Hémostase');
    expect(find.byKey(const ValueKey('add-qcm')), findsOneWidget);
    // Retour à la liste.
    await tester.tap(find.text('Retour aux séries'));
    await tester.pumpAndSettle();
    expect(card(exams.single.exam.id), findsOneWidget);
  });

  testWidgets('une série vide du nom refusé : message, rien créé', (
    tester,
  ) async {
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.tap(find.byKey(const ValueKey('new-series')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();
    expect(session.qcm.exams(), isEmpty);
    expect(find.byKey(const ValueKey('add-qcm')), findsNothing);
  });

  testWidgets('cartes : effectifs, à finir, jamais passée', (tester) async {
    final e = session.qcm.createExam('Cardio');
    session.qcm.addQuestion(e.id, q('Un'));
    session.qcm.addQuestion(e.id, q('Deux'));
    session.qcm.addQuestion(e.id, const ChoiceQuestion(body: 'Incomplète'));
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    final c = card(e.id);
    expect(
      find.descendant(of: c, matching: find.text('Cardio')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: c, matching: find.text('3 questions')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: c, matching: find.text('1 à finir')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: c, matching: find.text('jamais passée')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: c, matching: find.text('Écrite à la main')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: c, matching: find.text('Sans matière')),
      findsOneWidget,
    );
  });

  testWidgets('annales : par le titre ou par le choix', (tester) async {
    final a = session.qcm.createExam('Cardio');
    final b = session.qcm.createExam('Annales 2024');
    final c = session.qcm.createExam('Neuro', pastPaper: true);
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    expect(card(a.id), findsOneWidget);
    expect(card(b.id), findsNothing);
    expect(card(c.id), findsNothing);
    await tester.tap(find.byKey(const ValueKey('section-past')));
    await tester.pumpAndSettle();
    expect(card(a.id), findsNothing);
    expect(card(b.id), findsOneWidget);
    expect(card(c.id), findsOneWidget);
    // Sortir « Neuro » des annales depuis son menu.
    await tester.tap(find.byKey(ValueKey('exam-menu-${c.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sortir des annales'));
    await tester.pumpAndSettle();
    expect(card(c.id), findsNothing);
    expect(session.qcm.exam(c.id).pastPaper, isFalse);
    // « Annales 2024 » est dans les annales à cause du titre : pas de
    // bascule proposée.
    await tester.tap(find.byKey(ValueKey('exam-menu-${b.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Sortir des annales'), findsNothing);
    expect(find.text('Mettre dans les annales'), findsNothing);
  });

  testWidgets('annales vides : explication', (tester) async {
    session.qcm.createExam('Cardio');
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.tap(find.byKey(const ValueKey('section-past')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucune annale.'), findsOneWidget);
  });

  testWidgets('filtres : matière, jamais passées, sans matière', (
    tester,
  ) async {
    final y = session.courses.createYear('A');
    final sem = session.courses.createSemester(y.id, 'S1');
    final cardio = session.courses.createSubject(
      sem.id,
      'Cardiologie',
      color: 1,
    );
    final neuro = session.courses.createSubject(sem.id, 'Neurologie', color: 2);
    final a = session.qcm.createExam('Alpha', subjectId: cardio.id);
    final b = session.qcm.createExam('Bravo', subjectId: neuro.id);
    final c = session.qcm.createExam('Charlie');
    session.qcm.addQuestion(a.id, q('x'));
    final content = session.qcm.content(a.id);
    session.qcm.saveAttempt(
      AttemptDraftForTest.simple(examId: content.exam.id),
    );
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    for (final e in [a, b, c]) {
      expect(card(e.id), findsOneWidget);
    }

    await tester.tap(find.byKey(ValueKey('filter-subject-${cardio.id}')));
    await tester.pumpAndSettle();
    expect(card(a.id), findsOneWidget);
    expect(card(b.id), findsNothing);
    expect(card(c.id), findsNothing);

    await tester.tap(find.byKey(const ValueKey('filter-never-')));
    await tester.pumpAndSettle();
    expect(card(a.id), findsNothing); // déjà passée
    expect(card(b.id), findsOneWidget);
    expect(card(c.id), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('filter-noSubject-')));
    await tester.pumpAndSettle();
    expect(card(c.id), findsOneWidget);
    expect(card(b.id), findsNothing);

    await tester.tap(find.byKey(const ValueKey('filter-all-')));
    await tester.pumpAndSettle();
    expect(card(b.id), findsOneWidget);
  });

  testWidgets('recherche par titre ou matière', (tester) async {
    final y = session.courses.createYear('A');
    final sem = session.courses.createSemester(y.id, 'S1');
    final cardio = session.courses.createSubject(
      sem.id,
      'Cardiologie',
      color: 1,
    );
    final a = session.qcm.createExam('Alpha', subjectId: cardio.id);
    final b = session.qcm.createExam('Électrolytes');
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.enterText(find.byKey(const ValueKey('exam-search')), 'cardio');
    await tester.pumpAndSettle();
    expect(card(a.id), findsOneWidget);
    expect(card(b.id), findsNothing);
    // insensible aux accents et à la casse
    await tester.enterText(
      find.byKey(const ValueKey('exam-search')),
      'ELECTRO',
    );
    await tester.pumpAndSettle();
    expect(card(b.id), findsOneWidget);
    expect(card(a.id), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('exam-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucune épreuve ne correspond.'), findsOneWidget);
  });

  testWidgets('menu : dupliquer et supprimer', (tester) async {
    final e = session.qcm.createExam('Cardio');
    session.qcm.addQuestion(e.id, q('Un'));
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.tap(find.byKey(ValueKey('exam-menu-${e.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dupliquer'));
    await tester.pumpAndSettle();
    final exams = session.qcm.exams();
    expect(
      exams.map((s) => s.exam.title),
      containsAll(['Cardio', 'Cardio (copie)']),
    );
    expect(exams.every((s) => s.questions == 1), isTrue);

    await tester.tap(find.byKey(ValueKey('exam-menu-${e.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('L\'épreuve « Cardio »'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(session.qcm.exams().map((s) => s.exam.title), ['Cardio (copie)']);
  });

  testWidgets('sélection multiple : annales, matière, suppression', (
    tester,
  ) async {
    final y = session.courses.createYear('A');
    final sem = session.courses.createSemester(y.id, 'S1');
    final subject = session.courses.createSubject(
      sem.id,
      'Cardiologie',
      color: 1,
    );
    final a = session.qcm.createExam('Alpha');
    final b = session.qcm.createExam('Bravo');
    final c = session.qcm.createExam('Charlie');
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.tap(find.byKey(ValueKey('exam-menu-${a.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sélectionner plusieurs'));
    await tester.pumpAndSettle();
    expect(find.text('1 sélectionnée'), findsOneWidget);
    await tester.tap(card(b.id));
    await tester.pumpAndSettle();
    expect(find.text('2 sélectionnées'), findsOneWidget);
    // Retirer puis remettre.
    await tester.tap(card(b.id));
    await tester.pumpAndSettle();
    expect(find.text('1 sélectionnée'), findsOneWidget);
    await tester.tap(card(b.id));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('selection-move')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cardiologie'));
    await tester.pumpAndSettle();
    expect(session.qcm.exam(a.id).subjectId, subject.id);
    expect(session.qcm.exam(b.id).subjectId, subject.id);
    expect(session.qcm.exam(c.id).subjectId, isNull);

    await tester.tap(find.byKey(const ValueKey('selection-past')));
    await tester.pumpAndSettle();
    expect(session.qcm.exam(a.id).pastPaper, isTrue);
    expect(session.qcm.exam(b.id).pastPaper, isTrue);
    expect(session.qcm.exam(c.id).pastPaper, isFalse);

    // Elles ont quitté la section : plus rien de visible à supprimer, mais la
    // sélection existe encore.
    await tester.tap(find.byKey(const ValueKey('selection-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(session.qcm.exams().map((s) => s.exam.title), ['Charlie']);
    expect(find.byKey(const ValueKey('selection-count')), findsNothing);
  });

  testWidgets('sélection : tout sélectionner / désélectionner', (tester) async {
    final a = session.qcm.createExam('Alpha');
    final b = session.qcm.createExam('Bravo');
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    await tester.tap(find.byKey(ValueKey('exam-menu-${a.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sélectionner plusieurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-all')));
    await tester.pumpAndSettle();
    expect(find.text('2 sélectionnées'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('selection-all')));
    await tester.pumpAndSettle();
    expect(find.text('Aucune sélection'), findsOneWidget);
    // Sans sélection, les actions sont inactives.
    final move = tester.widget<TextButton>(
      find.byKey(const ValueKey('selection-move')),
    );
    expect(move.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('selection-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-count')), findsNothing);
    expect(card(b.id), findsOneWidget);
  });

  testWidgets('onglet Édition : un toucher ouvre l\'éditeur', (tester) async {
    final e = session.qcm.createExam('Cardio');
    await pumpPage(tester, session, const QcmPage(), size: _wide);
    expect(find.byKey(ValueKey('exam-primary-${e.id}')), findsOneWidget);
    await tester.tap(find.text('Édition'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('exam-primary-${e.id}')), findsNothing);
    await tester.tap(card(e.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-qcm')), findsOneWidget);
  });

  testWidgets('écran étroit : filtres en pastilles', (tester) async {
    final y = session.courses.createYear('A');
    final sem = session.courses.createSemester(y.id, 'S1');
    final cardio = session.courses.createSubject(
      sem.id,
      'Cardiologie',
      color: 1,
    );
    final a = session.qcm.createExam('Alpha', subjectId: cardio.id);
    final b = session.qcm.createExam('Bravo');
    await pumpPage(tester, session, const QcmPage(), size: _narrow);
    expect(find.byKey(const ValueKey('filter-rail')), findsNothing);
    expect(find.byKey(const ValueKey('filter-chips')), findsOneWidget);
    // La pastille de la matière est plus loin dans la rangée : on la fait
    // défiler.
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('chip-subject-${cardio.id}')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('filter-chips')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(ValueKey('chip-subject-${cardio.id}')));
    await tester.pumpAndSettle();
    expect(card(a.id), findsOneWidget);
    expect(card(b.id), findsNothing);
  });

  group('réception d\'une épreuve', () {
    late Directory tmp;
    final originalFile = Pickers.file;
    final originalSave = Pickers.save;
    final originalRun = Background.run;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('carabin_qcm_page_');
      // pas d'isolat dans les tests : on exécute le travail tout de suite
      Background.run = <T>(job) async => await job();
    });

    tearDown(() {
      Pickers.file = originalFile;
      Pickers.save = originalSave;
      Background.run = originalRun;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Épreuve d'un camarade, écrite dans un fichier.
    String friendsFile() {
      final other = openTestSession();
      final e = other.qcm.createExam('Annales 2025');
      other.qcm.addQuestion(e.id, q('Q1'));
      other.qcm.addQuestion(e.id, q('Q2'));
      final bytes = other.examExchange.exportExam(e.id).bytes;
      final f = File('${tmp.path}/annales.qcm.json')..writeAsBytesSync(bytes);
      return f.path;
    }

    testWidgets('ouvrir un fichier : épreuve ajoutée, bilan, bon onglet', (
      tester,
    ) async {
      final path = friendsFile();
      Pickers.file = (_) async => path;
      await pumpPage(tester, session, const QcmPage(), size: _wide);
      await tester.tap(find.byKey(const ValueKey('empty-import')));
      await tester.pumpAndSettle();
      expect(find.text('Épreuve reçue'), findsOneWidget);
      expect(find.textContaining('« Annales 2025 » ajoutée'), findsOneWidget);
      expect(find.textContaining('2 questions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-ok')));
      await tester.pumpAndSettle();
      final exam = session.qcm.exams().single.exam;
      expect(exam.title, 'Annales 2025');
      expect(exam.imported, isTrue);
      // C'est une annale : on bascule dessus pour la montrer.
      expect(card(exam.id), findsOneWidget);
      expect(find.text('Reçue'), findsOneWidget);
    });

    testWidgets('même épreuve reçue deux fois : choix remplacer / garder', (
      tester,
    ) async {
      final path = friendsFile();
      Pickers.file = (_) async => path;
      await pumpPage(tester, session, const QcmPage(), size: _wide);
      await tester.tap(find.byKey(const ValueKey('empty-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-ok')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-exam')));
      await tester.pumpAndSettle();
      expect(find.text('Cette épreuve existe déjà'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-keep-both')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-ok')));
      await tester.pumpAndSettle();
      expect(session.qcm.exams(), hasLength(2));

      await tester.tap(find.byKey(const ValueKey('import-exam')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-replace')));
      await tester.pumpAndSettle();
      expect(find.textContaining('remplacée'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-ok')));
      await tester.pumpAndSettle();
      expect(session.qcm.exams(), hasLength(2));
    });

    testWidgets('fichier illisible : message, rien d\'ajouté', (tester) async {
      final f = File('${tmp.path}/mauvais.qcm.json')
        ..writeAsStringSync('ceci n\'est pas du json');
      Pickers.file = (_) async => f.path;
      session.qcm.createExam('Déjà là');
      await pumpPage(tester, session, const QcmPage(), size: _wide);
      await tester.tap(find.byKey(const ValueKey('import-exam')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(session.qcm.exams(), hasLength(1));
    });

    testWidgets('annuler le choix du fichier ne fait rien', (tester) async {
      Pickers.file = (_) async => null;
      session.qcm.createExam('Déjà là');
      await pumpPage(tester, session, const QcmPage(), size: _wide);
      await tester.tap(find.byKey(const ValueKey('import-exam')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('partager : le fichier enregistré se relit', (tester) async {
      final e = session.qcm.createExam('Cardio');
      session.qcm.addQuestion(e.id, q('Un'));
      String? savedName;
      List<int>? saved;
      Pickers.save = (name, bytes) async {
        savedName = name;
        saved = bytes;
        return true;
      };
      await pumpPage(tester, session, const QcmPage(), size: _wide);
      await tester.tap(find.byKey(ValueKey('exam-menu-${e.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partager'));
      await tester.pumpAndSettle();
      expect(savedName, 'Cardio.qcm.json');
      expect(jsonDecode(utf8.decode(saved!)), isA<Map<String, dynamic>>());
      expect(
        find.textContaining('Épreuve enregistrée : Cardio.qcm.json'),
        findsOneWidget,
      );
    });
  });
}
