import 'package:carabin/app_session.dart';
import 'package:carabin/data/qcm_models.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:carabin/features/qcm/exam_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_page.dart';
import '../../support/test_session.dart';

const _wide = Size(1500, 1000);
const _narrow = Size(420, 900);

ChoiceQuestion ready(String body) => ChoiceQuestion(
  body: body,
  propositions: const [
    Proposition(text: 'Oui', correct: true),
    Proposition(text: 'Non'),
  ],
);

Finder tile(int id) => find.byKey(ValueKey('question-$id'));

void main() {
  late Session session;
  late int examId;

  setUp(() {
    session = openTestSession();
    examId = session.qcm.createExam('Cardio 2026').id;
  });

  testWidgets('série vide : invitation et boutons d\'ajout', (tester) async {
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    expect(find.text('Cardio 2026'), findsWidgets);
    expect(find.text('Aucune question'), findsOneWidget);
    expect(
      find.text('Aucune question. Ajoutez-en avec les boutons ci-dessus.'),
      findsOneWidget,
    );
    expect(find.text('Choisissez une question à modifier.'), findsWidgets);
    for (final k in ['add-qcm', 'add-qroc', 'add-tcs', 'add-qzp', 'add-case']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
  });

  testWidgets('ajouter une question l\'ouvre dans le formulaire', (
    tester,
  ) async {
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    await tester.tap(find.byKey(const ValueKey('add-qcm')));
    await tester.pumpAndSettle();
    final content = session.qcm.content(examId);
    expect(content.questions, hasLength(1));
    final id = content.questions.single.id;
    expect(tile(id), findsOneWidget);
    expect(find.byKey(const ValueKey('body')), findsOneWidget);
    // Aperçu : question incomplète signalée.
    expect(find.byKey(const ValueKey('issues')), findsOneWidget);
    expect(find.text('• Écrivez l\'énoncé.'), findsOneWidget);
    expect(find.text('1 à finir'), findsNothing);
    expect(find.text('0 prête · 1 à finir'), findsOneWidget);
  });

  testWidgets('la saisie est enregistrée au fil de l\'eau', (tester) async {
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    await tester.tap(find.byKey(const ValueKey('add-qcm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('body')),
      'Quel est le diagnostic ?',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('proposition-0')),
      'Infarctus',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('proposition-1')),
      'Péricardite',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('correct-0')));
    await tester.pumpAndSettle();
    final row = session.qcm.content(examId).questions.single;
    final q = row.question as ChoiceQuestion;
    expect(q.body, 'Quel est le diagnostic ?');
    expect(q.propositions.map((p) => p.text), ['Infarctus', 'Péricardite']);
    expect(q.propositions.first.correct, isTrue);
    expect(row.ready, isTrue);
    expect(find.text('1 prête · 0 à finir'), findsOneWidget);
    expect(find.byKey(const ValueKey('all-good')), findsOneWidget);
    // La liste montre le début de l'énoncé.
    expect(find.text('Quel est le diagnostic ?'), findsWidgets);
  });

  testWidgets('aperçu : on peut répondre puis voir la correction', (
    tester,
  ) async {
    session.qcm.addQuestion(examId, ready('Q1'));
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    final id = session.qcm.content(examId).questions.single.id;
    await tester.tap(tile(id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reveal-switch')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reveal-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Oui'), findsWidgets);
  });

  testWidgets('numérotation, déplacement, duplication, suppression', (
    tester,
  ) async {
    final a = session.qcm.addQuestion(examId, ready('Alpha'));
    final b = session.qcm.addQuestion(examId, ready('Bravo'));
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    // Alpha est la question 1.
    expect(
      find.descendant(of: tile(a), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile(b), matching: find.text('2')),
      findsOneWidget,
    );

    // Descendre Alpha.
    await tester.tap(find.byKey(ValueKey('question-menu-$a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descendre'));
    await tester.pumpAndSettle();
    expect(
      [for (final q in session.qcm.content(examId).questions) q.id],
      [b, a],
    );
    // La première ne peut plus monter.
    await tester.tap(find.byKey(ValueKey('question-menu-$b')));
    await tester.pumpAndSettle();
    final up = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('Monter'), matching: find.byType(InkWell))
          .first,
    );
    expect(up.onTap, isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Dupliquer Bravo.
    await tester.tap(find.byKey(ValueKey('question-menu-$b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dupliquer'));
    await tester.pumpAndSettle();
    expect(session.qcm.content(examId).questions, hasLength(3));

    // Supprimer Bravo (avec confirmation).
    await tester.tap(find.byKey(ValueKey('question-menu-$b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer la question'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer la question 1 ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect(session.qcm.content(examId).questions, hasLength(3));
    await tester.tap(find.byKey(ValueKey('question-menu-$b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer la question'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(
      session.qcm.content(examId).questions.map((q) => q.id),
      isNot(contains(b)),
    );
    expect(session.qcm.content(examId).questions, hasLength(2));
  });

  testWidgets('cas clinique : ajout, question dans le cas, suppression', (
    tester,
  ) async {
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    await tester.tap(find.byKey(const ValueKey('add-case')));
    await tester.pumpAndSettle();
    // Choix du genre.
    expect(find.text('Dossier progressif'), findsOneWidget);
    await tester.tap(find.text('KFP'));
    await tester.pumpAndSettle();
    var content = session.qcm.content(examId);
    final unit = content.units.single as CaseUnit;
    expect(unit.kase.info.genre, CaseGenre.kfp);
    expect(find.byKey(ValueKey('case-${unit.kase.id}')), findsOneWidget);
    expect(find.text('KFP 1'), findsWidgets);
    expect(find.text('Aucune question dans ce cas.'), findsWidgets);

    // Titre et contexte du cas.
    await tester.enterText(
      find.byKey(const ValueKey('case-title')),
      'Douleur thoracique',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('case-context')),
      'Homme de 58 ans.',
    );
    await tester.pumpAndSettle();
    var info = (session.qcm.content(examId).units.single as CaseUnit).kase.info;
    expect(info.title, 'Douleur thoracique');
    expect(info.context, 'Homme de 58 ans.');
    expect(find.text('Douleur thoracique'), findsWidgets);

    // Ajouter une question dans le cas depuis son menu.
    await tester.tap(find.byKey(ValueKey('case-menu-${unit.kase.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter une question au dossier · QCM'));
    await tester.pumpAndSettle();
    content = session.qcm.content(examId);
    final inside = (content.units.single as CaseUnit).questions;
    expect(inside, hasLength(1));
    expect(inside.single.caseId, unit.kase.id);
    // Le contexte du cas apparaît dans l'aperçu de la question.
    expect(find.byKey(const ValueKey('case-card')), findsOneWidget);
    expect(find.text('Homme de 58 ans.'), findsWidgets);

    // Sortir la question du cas par la liste déroulante.
    await tester.tap(find.byKey(const ValueKey('case-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non, question isolée').last);
    await tester.pumpAndSettle();
    content = session.qcm.content(examId);
    expect(content.units, hasLength(2));
    expect(content.units.whereType<SingleUnit>(), hasLength(1));
    expect((content.units.whereType<CaseUnit>().single).questions, isEmpty);

    // Supprimer le cas.
    await tester.tap(find.byKey(ValueKey('case-menu-${unit.kase.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer le cas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    content = session.qcm.content(examId);
    expect(content.units, hasLength(1));
    expect(content.units.single, isA<SingleUnit>());
  });

  testWidgets('en-tête : renommer, items, matière', (tester) async {
    final y = session.courses.createYear('A');
    final sem = session.courses.createSemester(y.id, 'S1');
    final subject = session.courses.createSubject(
      sem.id,
      'Cardiologie',
      color: 3,
    );
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );

    await tester.tap(find.byKey(const ValueKey('rename-exam')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cardio corrigée');
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();
    expect(session.qcm.exam(examId).title, 'Cardio corrigée');

    await tester.tap(find.byKey(const ValueKey('items-chip')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '12, 224');
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();
    expect(session.qcm.exam(examId).items, '12, 224');
    expect(find.text('Items : 12, 224'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subject-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cardiologie'));
    await tester.pumpAndSettle();
    expect(session.qcm.exam(examId).subjectId, subject.id);
  });

  testWidgets('mélanger : confirmation puis nouvel ordre', (tester) async {
    for (var i = 0; i < 8; i++) {
      session.qcm.addQuestion(examId, ready('Q$i'));
    }
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _wide,
    );
    final before = [
      for (final q in session.qcm.content(examId).questions) q.id,
    ];
    await tester.tap(find.byKey(const ValueKey('exam-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mélanger'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mélanger'));
    await tester.pumpAndSettle();
    final after = [for (final q in session.qcm.content(examId).questions) q.id];
    expect(after.toSet(), before.toSet());
    expect(after.length, before.length);
  });

  testWidgets('écran étroit : trois onglets', (tester) async {
    session.qcm.addQuestion(examId, ready('Alpha'));
    await pumpPage(
      tester,
      session,
      ExamEditorPage(examId: examId),
      size: _narrow,
    );
    final id = session.qcm.content(examId).questions.single.id;
    expect(find.byKey(const ValueKey('editor-tabs')), findsOneWidget);
    expect(tile(id), findsOneWidget);
    await tester.tap(tile(id));
    await tester.pumpAndSettle();
    // On arrive dans l'édition.
    expect(find.byKey(const ValueKey('body')).hitTestable(), findsOneWidget);
    await tester.tap(find.text('Aperçu').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reveal-switch')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.text('Questions').last);
    await tester.pumpAndSettle();
    expect(tile(id).hitTestable(), findsOneWidget);
  });

  testWidgets('série supprimée ailleurs : l\'éditeur se ferme', (tester) async {
    await pumpPage(
      tester,
      session,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ExamEditorPage(examId: examId),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
      size: _wide,
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rename-exam')), findsOneWidget);
    session.qcm.deleteExams([examId]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rename-exam')), findsNothing);
    expect(find.text('ouvrir'), findsOneWidget);
  });
}
