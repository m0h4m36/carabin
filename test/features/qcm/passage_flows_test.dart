import 'package:carabin/app_session.dart';
import 'package:carabin/data/qcm_models.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:carabin/features/qcm/passage_flows.dart';
import 'package:carabin/features/qcm/passage_page.dart';
import 'package:carabin/features/qcm/qcm_page.dart';
import 'package:carabin/l10n/textes_qcm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attempts.dart';
import '../../support/passage_launch.dart';
import '../../support/pump_page.dart';
import '../../support/test_session.dart';

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

AnswerRow row(
  int position,
  Verdict verdict, {
  CaseInfo? info,
  int group = -1,
}) => AnswerRow(
  id: position + 1,
  attemptId: 1,
  position: position,
  question: qru('Bonne$position', 'Fausse$position'),
  info: info,
  caseGroup: group,
  order: const [],
  answer: null,
  verdict: verdict,
  score: verdict == Verdict.right ? 1 : 0,
  max: 1,
  doubt: false,
  subjectId: 7,
  topicId: 8,
  examId: 9,
  notebook: false,
);

void main() {
  group('unitsOfAttempt', () {
    const info = CaseInfo(genre: CaseGenre.progressive, title: 'Dossier');

    test('toutes les questions, regroupées en cas', () {
      final units = unitsOfAttempt([
        row(0, Verdict.right),
        row(1, Verdict.right, info: info, group: 0),
        row(2, Verdict.wrong, info: info, group: 0),
        row(3, Verdict.skipped),
      ], onlyMissed: false);
      expect(units, hasLength(3));
      expect(units[0].info, isNull);
      expect(units[1].info, info);
      expect(units[1].questions, hasLength(2));
      expect(units[2].questions, hasLength(1));
      // Origine conservée pour classer le résultat.
      final src = units[0].questions.single;
      expect((src.examId, src.subjectId, src.topicId), (9, 7, 8));
    });

    test('ratées seulement : un cas revient en entier', () {
      final units = unitsOfAttempt([
        row(0, Verdict.right),
        row(1, Verdict.right, info: info, group: 0),
        row(2, Verdict.partial, info: info, group: 0),
        row(3, Verdict.wrong),
        row(4, Verdict.pending),
        row(5, Verdict.skipped),
      ], onlyMissed: true);
      expect([for (final u in units) u.questions.length], [2, 1, 1, 1]);
      expect(units.first.info, info);
    });

    test('deux cas voisins restent deux cas', () {
      final units = unitsOfAttempt([
        row(0, Verdict.wrong, info: info, group: 0),
        row(1, Verdict.wrong, info: info, group: 1),
      ], onlyMissed: false);
      expect(units, hasLength(2));
    });

    test('tout juste : rien à refaire', () {
      expect(
        unitsOfAttempt([row(0, Verdict.right)], onlyMissed: true),
        isEmpty,
      );
    });
  });

  group('depuis la liste des séries', () {
    late Session session;
    setUp(() => session = openTestSession());

    int exam(String title, List<String> goods) {
      final e = session.qcm.createExam(title);
      for (final g in goods) {
        session.qcm.addQuestion(e.id, qru(g, 'F$g'));
      }
      return e.id;
    }

    Future<void> showList(WidgetTester tester) =>
        pumpPage(tester, session, const QcmPage(), size: const Size(1300, 900));

    testWidgets('Composer : réglages mémorisés puis passage', (tester) async {
      final id = exam('Cardio', ['Bonne1', 'Bonne2']);
      await showList(tester);
      await tapKey(tester, 'exam-primary-$id');
      expect(key('setup-start'), findsOneWidget);
      expect(find.text('Cardio'), findsWidgets);

      // On choisit la correction à chaque question.
      await tester.tap(
        find.descendant(
          of: key('setup-correction'),
          matching: find.text(TxQcm.correctionEach),
        ),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-start');

      expect(find.byType(PassagePage), findsOneWidget);
      expect(find.text('Question 1 sur 2'), findsOneWidget);
      expect(session.qcm.passageSettings().correction, Correction.each);
    });

    testWidgets('annuler les réglages : pas de passage, réglages inchangés', (
      tester,
    ) async {
      final id = exam('Cardio', ['Bonne1']);
      await showList(tester);
      await tapKey(tester, 'exam-primary-$id');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(PassagePage), findsNothing);
      expect(session.qcm.passageSettings().correction, Correction.end);
    });

    testWidgets('série sans question prête : message, pas de réglages', (
      tester,
    ) async {
      final e = session.qcm.createExam('Vide');
      session.qcm.addQuestion(e.id, const ChoiceQuestion(body: 'Incomplète'));
      await showList(tester);
      await tester.tap(key('exam-${e.id}'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cette série n\'a encore aucune question prête à poser.'),
        findsOneWidget,
      );
      expect(key('setup-start'), findsNothing);
    });

    testWidgets('une partie d\'une épreuve compte comme un entraînement', (
      tester,
    ) async {
      final id = exam('Cardio', ['Bonne1', 'Bonne2', 'Bonne3', 'Bonne4']);
      await showList(tester);
      await tapKey(tester, 'exam-primary-$id');
      // « Une partie seulement » : 2 questions sur 4.
      await tapKey(tester, 'setup-part');
      await tester.enterText(key('setup-count'), '2');
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-start');
      expect(find.text('Question 1 sur 2'), findsOneWidget);
      // Rendre la copie sans répondre.
      await tapKey(tester, 'passage-hand-in');
      await tester.tap(find.widgetWithText(FilledButton, 'Rendre la copie'));
      await tester.pumpAndSettle();
      final saved = session.qcm.attempts().single;
      expect(saved.practice, isTrue);
      expect(saved.examId, id);
      expect(saved.examTotal, 4);
      expect(saved.part, 0.5);
    });

    testWidgets('l\'épreuve entière n\'est pas un entraînement', (
      tester,
    ) async {
      final id = exam('Cardio', ['Bonne1']);
      await showList(tester);
      await tapKey(tester, 'exam-primary-$id');
      await tapKey(tester, 'setup-start');
      await tester.tap(find.text('Bonne1'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'validate');
      final saved = session.qcm.attempts().single;
      expect(saved.practice, isFalse);
      expect(saved.examId, id);
      expect(saved.handwritten, isTrue);
    });

    testWidgets('Prochaine épreuve : la première jamais passée', (
      tester,
    ) async {
      final first = exam('Première', ['BonneA']);
      exam('Seconde', ['BonneB']);
      // La première a déjà une copie : on propose la seconde.
      session.qcm.saveAttempt(AttemptDraftForTest.simple(examId: first));
      await showList(tester);
      await tapKey(tester, 'next-exam');
      expect(find.text('Seconde'), findsWidgets);
      await tapKey(tester, 'setup-start');
      expect(find.text('Énoncé de BonneB'), findsOneWidget);
    });

    testWidgets('Prochaine épreuve : aucune épreuve prête', (tester) async {
      final e = session.qcm.createExam('Vide');
      session.qcm.addQuestion(e.id, const ChoiceQuestion(body: 'Incomplète'));
      await showList(tester);
      await tapKey(tester, 'next-exam');
      expect(find.text('Aucune épreuve prête à être passée.'), findsOneWidget);
    });

    testWidgets('S\'entraîner : plusieurs séries, tirage dans toutes', (
      tester,
    ) async {
      final a = exam('Cardio', ['BonneA1', 'BonneA2']);
      final b = exam('Pneumo', ['BonneB1']);
      await showList(tester);
      await tapKey(tester, 'practice');
      expect(key('selection-practice'), findsOneWidget);
      // Rien de coché : le bouton est inactif.
      expect(
        tester.widget<ButtonStyleButton>(key('selection-practice')).onPressed,
        isNull,
      );
      await tester.tap(key('exam-$a'));
      await tester.pumpAndSettle();
      await tester.tap(key('exam-$b'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'selection-practice');
      expect(find.text('Entraînement · 2 épreuves'), findsWidgets);
      await tapKey(tester, 'setup-start');
      expect(find.text('Question 1 sur 3'), findsOneWidget);

      await tapKey(tester, 'passage-hand-in');
      await tester.tap(find.widgetWithText(FilledButton, 'Rendre la copie'));
      await tester.pumpAndSettle();
      final saved = session.qcm.attempts().single;
      expect(saved.practice, isTrue);
      expect(saved.examId, isNull);
      expect(saved.title, 'Entraînement · 2 épreuves');
      expect(saved.questionCount, 3);
    });

    testWidgets('S\'entraîner : annuler les réglages garde la sélection', (
      tester,
    ) async {
      final a = exam('Cardio', ['BonneA1']);
      await showList(tester);
      await tapKey(tester, 'practice');
      await tester.tap(key('exam-$a'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'selection-practice');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(key('selection-count'), findsOneWidget);
      expect(find.byType(PassagePage), findsNothing);
    });
  });
}
