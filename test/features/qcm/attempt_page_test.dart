import 'package:carabin/app_session.dart';
import 'package:carabin/data/qcm_models.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:carabin/features/qcm/attempt_page.dart';
import 'package:carabin/features/qcm/passage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/passage_launch.dart';
import '../../support/pump_page.dart';
import '../../support/test_session.dart';

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

AnswerDraft answerOf(
  Question q,
  Answer? a, {
  bool doubt = false,
  CaseInfo? info,
  int group = -1,
}) => AnswerDraft(
  question: q,
  grade: gradeQuestion(q, a, Scoring.edn),
  answer: a,
  doubt: doubt,
  info: info,
  caseGroup: group,
);

int saveCopy(
  Session session,
  List<AnswerDraft> answers, {
  String title = 'Hémostase',
  bool practice = false,
  bool handwritten = true,
  bool timedOut = false,
  Duration duration = const Duration(minutes: 12, seconds: 5),
  int? examId,
  int? examTotal,
}) => session.qcm.saveAttempt(
  AttemptDraft(
    title: title,
    examId: examId,
    practice: practice,
    handwritten: handwritten,
    settings: const PassageSettings(),
    startedAt: DateTime(2026, 3, 12, 15, 20),
    duration: duration,
    timedOut: timedOut,
    examTotal: examTotal,
    answers: answers,
  ),
);

const _qroc = QrocQuestion(
  body: 'Citez le diagnostic.',
  model: 'Embolie pulmonaire',
);

void main() {
  late Session session;

  setUp(() => session = openTestSession());

  Future<void> show(
    WidgetTester tester,
    int id, {
    Size size = const Size(1400, 900),
  }) => pumpPage(tester, session, AttemptPage(attemptId: id), size: size);

  testWidgets('résumé : note, points, tuiles, durée, mentions', (tester) async {
    final id = saveCopy(session, [
      answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
      answerOf(qru('Bonne2', 'Fausse2'), const ChoiceAnswer({1})),
      answerOf(qru('Bonne3', 'Fausse3'), null),
      answerOf(qru('Bonne4', 'Fausse4'), const ChoiceAnswer({0})),
    ], examTotal: null);
    await show(tester, id);

    expect(tester.widget<Text>(key('attempt-note')).data, '10');
    expect(
      tester.widget<Text>(key('attempt-points')).data,
      '2,00 / 4,00 points',
    );
    String tile(String k) => (tester.widget<Text>(
      find.descendant(of: key(k), matching: find.byType(Text)).first,
    )).data!;
    expect(tile('tile-right'), '2');
    expect(tile('tile-wrong'), '1');
    expect(tile('tile-skipped'), '1');
    expect(tile('tile-partial'), '0');
    expect(key('tile-pending'), findsNothing);
    expect(
      find.descendant(
        of: key('tile-duration'),
        matching: find.text('12 min 05 s'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('12 mars 2026 à 15:20'), findsOneWidget);
    expect(find.textContaining('Écrite à la main'), findsOneWidget);
    expect(key('timed-out'), findsNothing);
    expect(key('pending-note'), findsNothing);
  });

  testWidgets('entraînement : la part de l\'épreuve est indiquée', (
    tester,
  ) async {
    final id = saveCopy(
      session,
      [
        answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
      ],
      practice: true,
      handwritten: false,
      examTotal: 4,
    );
    await show(tester, id);
    expect(
      find.textContaining('Entraînement · 25 % de l\'épreuve'),
      findsOneWidget,
    );
    expect(find.textContaining('Écrite à la main'), findsNothing);
  });

  testWidgets('temps écoulé : mention', (tester) async {
    final id = saveCopy(session, [
      answerOf(qru('Bonne1', 'Fausse1'), null),
    ], timedOut: true);
    await show(tester, id);
    expect(key('timed-out'), findsOneWidget);
  });

  testWidgets('détail : on déplie une question, la correction apparaît', (
    tester,
  ) async {
    final id = saveCopy(session, [
      answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({1})),
    ]);
    await show(tester, id);
    final row = session.qcm.attempt(id).answers.single;
    // Replié : pas de correction.
    expect(find.text('Oubliée'), findsNothing);
    expect(find.text('Fausse · 0 / 1'), findsOneWidget);
    await tapKey(tester, 'answer-head-${row.id}');
    expect(find.text('Oubliée'), findsOneWidget);
    expect(find.text('Bonne1'), findsOneWidget);
    // Replier.
    await tapKey(tester, 'answer-head-${row.id}');
    expect(find.text('Oubliée'), findsNothing);
  });

  testWidgets('pastille : déplie la question correspondante', (tester) async {
    final id = saveCopy(session, [
      for (var i = 1; i <= 12; i++)
        answerOf(qru('Bonne$i', 'Fausse$i'), const ChoiceAnswer({0})),
    ]);
    await show(tester, id, size: const Size(400, 860));
    final rows = session.qcm.attempt(id).answers;
    await tester.ensureVisible(key('attempt-dot-${rows[10].id}'));
    await tester.tap(key('attempt-dot-${rows[10].id}'));
    await tester.pumpAndSettle();
    expect(find.text('Bonne11'), findsOneWidget);
    expect(find.text('Bonne10'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onglet À reprendre : les erreurs, les passées et les doutes', (
    tester,
  ) async {
    final id = saveCopy(session, [
      answerOf(qru('Juste1', 'F1'), const ChoiceAnswer({0}), doubt: true),
      answerOf(qru('Juste2', 'F2'), const ChoiceAnswer({0})),
      answerOf(qru('Ratee3', 'F3'), const ChoiceAnswer({1})),
      answerOf(qru('Passee4', 'F4'), null),
    ]);
    await show(tester, id);
    String q(int n) =>
        'Énoncé de ${['Juste1', 'Juste2', 'Ratee3', 'Passee4'][n]}';
    expect(find.text(q(1)), findsOneWidget);

    await tester.tap(find.text('À reprendre'));
    await tester.pumpAndSettle();
    expect(find.text(q(0)), findsOneWidget, reason: 'doute');
    expect(find.text(q(1)), findsNothing);
    expect(find.text(q(2)), findsOneWidget);
    expect(find.text(q(3)), findsOneWidget);

    await tester.tap(find.text('Toutes'));
    await tester.pumpAndSettle();
    expect(find.text(q(1)), findsOneWidget);
  });

  testWidgets('tout juste : rien à reprendre, refaire mes ratées inactif', (
    tester,
  ) async {
    final id = saveCopy(session, [
      answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
    ]);
    await show(tester, id);
    await tester.tap(find.text('À reprendre'));
    await tester.pumpAndSettle();
    expect(key('nothing-to-review'), findsOneWidget);
    expect(
      tester.widget<ButtonStyleButton>(key('redo-missed')).onPressed,
      isNull,
    );
  });

  testWidgets('dossier : le contexte du cas précède ses questions', (
    tester,
  ) async {
    const info = CaseInfo(
      genre: CaseGenre.kfp,
      title: 'Douleur thoracique',
      context: 'Homme de 60 ans.',
    );
    final id = saveCopy(session, [
      answerOf(qru('B1', 'F1'), const ChoiceAnswer({0}), info: info, group: 0),
      answerOf(qru('B2', 'F2'), const ChoiceAnswer({0}), info: info, group: 0),
      answerOf(qru('B3', 'F3'), const ChoiceAnswer({0})),
    ]);
    await show(tester, id);
    expect(find.text('Douleur thoracique'), findsOneWidget);
    // Un seul en-tête de cas, pour les deux questions du dossier.
    expect(
      find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('case-header-');
      }),
      findsOneWidget,
    );
  });

  group('auto-évaluation d\'un QROC', () {
    testWidgets('la note est provisoire puis recalculée', (tester) async {
      final id = saveCopy(session, [
        answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
        answerOf(_qroc, const TextAnswer('une embolie')),
      ]);
      await show(tester, id);
      expect(tester.widget<Text>(key('attempt-note')).data, '10');
      expect(key('pending-note'), findsOneWidget);
      expect(key('tile-pending'), findsOneWidget);

      final row = session.qcm.attempt(id).answers[1];
      await tapKey(tester, 'answer-head-${row.id}');
      expect(
        find.text('Comparez avec la réponse modèle puis évaluez-vous'),
        findsOneWidget,
      );
      await tapKey(tester, 'self-1.0');

      expect(key('pending-note'), findsNothing);
      expect(key('tile-pending'), findsNothing);
      expect(tester.widget<Text>(key('attempt-note')).data, '20');
      expect(
        tester.widget<Text>(key('attempt-points')).data,
        '2,00 / 2,00 points',
      );
      expect(session.qcm.attempt(id).answers[1].verdict, Verdict.right);

      // Se réévaluer : partielle.
      await tapKey(tester, 'self-0.5');
      expect(tester.widget<Text>(key('attempt-note')).data, '15');
      expect(session.qcm.attempt(id).answers[1].verdict, Verdict.partial);
    });
  });

  testWidgets(
    'supprimer la copie : confirmation, retour à la page précédente',
    (tester) async {
      final id = saveCopy(session, [
        answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
      ]);
      await openFromLauncher(tester, session, () => AttemptPage(attemptId: id));
      await tapKey(tester, 'attempt-menu');
      await tester.tap(key('attempt-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer cette copie ?'), findsOneWidget);
      // Annuler : la copie reste.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(session.qcm.attempts(), hasLength(1));

      await tapKey(tester, 'attempt-menu');
      await tester.tap(key('attempt-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer la copie'));
      await tester.pumpAndSettle();
      expect(session.qcm.attempts(), isEmpty);
      expect(find.byType(AttemptPage), findsNothing);
      expect(key('launch'), findsOneWidget);
    },
  );

  testWidgets('copie introuvable : message, pas d\'erreur', (tester) async {
    await show(tester, 999);
    expect(find.text('Cette copie n\'existe plus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('recommencer', () {
    ExamSummary? summaryOf(int examId) =>
        session.qcm.exams().where((s) => s.exam.id == examId).firstOrNull;

    testWidgets('refaire mes ratées : réglages, puis seulement les ratées', (
      tester,
    ) async {
      final id = saveCopy(session, [
        answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
        answerOf(qru('Bonne2', 'Fausse2'), const ChoiceAnswer({1})),
        answerOf(qru('Bonne3', 'Fausse3'), null),
      ]);
      await show(tester, id);
      expect(find.text('Refaire mes ratées · 2'), findsOneWidget);
      await tapKey(tester, 'redo-missed');
      // Fenêtre de réglages : 2 questions disponibles.
      expect(key('setup-start'), findsOneWidget);
      expect(find.textContaining('2 questions'), findsWidgets);
      await tapKey(tester, 'setup-start');

      expect(find.byType(PassagePage), findsOneWidget);
      expect(find.text('Question 1 sur 2'), findsOneWidget);
      expect(find.text('Énoncé de Bonne2'), findsOneWidget);
      // C'est un entraînement : une partie de la copie initiale.
      await tester.tap(find.text('Bonne2'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'validate');
      await tester.tap(find.text('Bonne3'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'validate');
      final all = session.qcm.attempts();
      expect(all, hasLength(2));
      final newest = all.first;
      expect(newest.practice, isTrue);
      expect(newest.score, 2);
      expect(newest.questionCount, 2);
    });

    testWidgets('repasser : toutes les questions de la copie', (tester) async {
      final id = saveCopy(session, [
        answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
        answerOf(qru('Bonne2', 'Fausse2'), const ChoiceAnswer({1})),
      ]);
      await show(tester, id);
      await tapKey(tester, 'replay');
      await tapKey(tester, 'setup-start');
      expect(find.text('Question 1 sur 2'), findsOneWidget);
    });

    testWidgets(
      'une autre épreuve : jamais l\'épreuve qu\'on vient de passer',
      (tester) async {
        final done = session.qcm.createExam('Faite');
        session.qcm.addQuestion(done.id, qru('Bonne1', 'Fausse1'));
        final other = session.qcm.createExam('Autre');
        session.qcm.addQuestion(other.id, qru('BonneA', 'FausseA'));
        expect(summaryOf(other.id)!.ready, 1);
        final id = saveCopy(
          session,
          [
            answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
          ],
          title: 'Faite',
          examId: done.id,
        );
        await show(tester, id);
        await tapKey(tester, 'another-exam');
        await tapKey(tester, 'setup-start');
        expect(find.text('Énoncé de BonneA'), findsOneWidget);
      },
    );

    testWidgets('une autre épreuve : aucune autre prête', (tester) async {
      final done = session.qcm.createExam('Faite');
      session.qcm.addQuestion(done.id, qru('Bonne1', 'Fausse1'));
      final id = saveCopy(
        session,
        [
          answerOf(qru('Bonne1', 'Fausse1'), const ChoiceAnswer({0})),
        ],
        title: 'Faite',
        examId: done.id,
      );
      await show(tester, id);
      await tapKey(tester, 'another-exam');
      expect(
        find.text('Aucune autre épreuve prête à être passée pour le moment.'),
        findsOneWidget,
      );
      expect(key('setup-start'), findsNothing);
    });
  });
}
