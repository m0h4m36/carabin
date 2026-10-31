import 'package:carabin/app_session.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/features/qcm/attempt_page.dart';
import 'package:carabin/features/qcm/passage_page.dart';
import 'package:carabin/features/qcm/question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/passage_launch.dart';
import '../../support/test_session.dart';

const _narrow = Size(400, 860);

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

/// Deux questions : « Bonne1 » / « Bonne2 » sont les bonnes réponses.
List<PlannedQuestion> twoQuestions() => [
  planned(qru('Bonne1', 'Fausse1')),
  planned(qru('Bonne2', 'Fausse2')),
];

Future<void> openPassage(
  WidgetTester tester,
  Session session, {
  List<PlannedQuestion>? plan,
  PassageSettings settings = const PassageSettings(),
  DateTime Function()? clock,
  Size size = const Size(1400, 900),
  bool practice = false,
}) => openFromLauncher(
  tester,
  session,
  () => PassagePage(
    plan: plan ?? twoQuestions(),
    settings: settings,
    title: 'Hémostase',
    practice: practice,
    clock: clock,
  ),
  size: size,
);

void main() {
  late Session session;

  setUp(() => session = openTestSession());

  testWidgets('répondre à tout : la copie s\'affiche directement', (
    tester,
  ) async {
    await openPassage(tester, session);
    expect(find.text('Question 1 sur 2'), findsOneWidget);
    // Rien de coché : Valider est inactif.
    expect(tester.widget<FilledButton>(key('validate')).onPressed, isNull);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    expect(find.text('Question 2 sur 2'), findsOneWidget);
    await tester.tap(find.text('Bonne2'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');

    // Plus de question : pas de boîte de dialogue, la copie est ouverte.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AttemptPage), findsOneWidget);
    final saved = session.qcm.attempts();
    expect(saved, hasLength(1));
    expect(saved.single.score, 2);
    expect(saved.single.max, 2);
    expect(saved.single.title, 'Hémostase');
    expect(saved.single.timedOut, isFalse);
    expect(tester.widget<Text>(key('attempt-note')).data, '20');
  });

  testWidgets('une question passée : on peut la reprendre ou rendre', (
    tester,
  ) async {
    await openPassage(tester, session);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    await tapKey(tester, 'skip');
    expect(find.text('Il reste des questions passées'), findsOneWidget);
    expect(
      find.text(
        'Il reste 1 question passée. La reprendre, ou rendre la copie ?',
      ),
      findsOneWidget,
    );

    // Reprendre : on revient sur la question passée.
    await tapKey(tester, 'end-resume');
    expect(find.text('Question 2 sur 2'), findsOneWidget);
    expect(session.qcm.attempts(), isEmpty);

    // Passer encore, puis rendre quand même.
    await tapKey(tester, 'skip');
    await tapKey(tester, 'end-hand-in');
    final saved = session.qcm.attempts().single;
    expect(saved.score, 1);
    final detail = session.qcm.attempt(saved.id);
    expect(detail.answers[1].verdict, Verdict.skipped);
    expect(detail.answers[1].answer, isNull);
  });

  testWidgets('correction immédiate : verdict, propositions figées, suite', (
    tester,
  ) async {
    await openPassage(
      tester,
      session,
      settings: const PassageSettings(correction: Correction.each),
    );
    await tester.tap(find.text('Fausse1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');

    expect(key('verdict'), findsOneWidget);
    expect(find.textContaining('Fausse · 0 / 1'), findsOneWidget);
    // La bonne réponse est signalée comme oubliée ; plus de saisie possible.
    expect(find.text('Oubliée'), findsOneWidget);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    expect(key('validate'), findsNothing);
    expect(find.text('Question suivante'), findsOneWidget);

    await tapKey(tester, 'next');
    expect(find.text('Question 2 sur 2'), findsOneWidget);
    await tester.tap(find.text('Bonne2'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    expect(find.textContaining('Juste · 1 / 1'), findsOneWidget);
    // Dernière question : le bouton annonce les résultats.
    expect(find.text('Voir les résultats'), findsOneWidget);
    await tapKey(tester, 'next');
    expect(find.byType(AttemptPage), findsOneWidget);
    expect(session.qcm.attempts().single.score, 1);
  });

  testWidgets('retour interdit : une question validée est verrouillée', (
    tester,
  ) async {
    await openPassage(tester, session);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    expect(tester.widget<InkWell>(key('dot-0')).onTap, isNull);
    expect(tester.widget<InkWell>(key('dot-1')).onTap, isNotNull);
  });

  testWidgets('retour permis : modifier ou effacer une réponse validée', (
    tester,
  ) async {
    await openPassage(
      tester,
      session,
      settings: const PassageSettings(backAllowed: true),
    );
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    expect(find.text('Question 2 sur 2'), findsOneWidget);

    // On revient : la réponse validée est rendue cochée et peut être effacée.
    await tapKey(tester, 'dot-0');
    expect(find.text('Question 1 sur 2'), findsOneWidget);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(key('validate')).onPressed,
      isNull,
      reason: 'une réponse vide ne se valide pas',
    );
    // On choisit l'autre proposition puis on valide : c'est elle qui compte.
    await tester.tap(find.text('Fausse1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    await tester.tap(find.text('Bonne2'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    final detail = session.qcm.attempt(session.qcm.attempts().single.id);
    expect(detail.answers[0].verdict, Verdict.wrong);
    expect(detail.answers[1].verdict, Verdict.right);
  });

  testWidgets('doute : enregistré dans la copie', (tester) async {
    await openPassage(tester, session);
    await tapKey(tester, 'doubt');
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    await tester.tap(find.text('Bonne2'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    final detail = session.qcm.attempt(session.qcm.attempts().single.id);
    expect(detail.answers.map((a) => a.doubt), [true, false]);
  });

  testWidgets('rendre la copie avant la fin : confirmation puis copie', (
    tester,
  ) async {
    await openPassage(tester, session);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');

    await tapKey(tester, 'passage-hand-in');
    expect(
      find.text(
        'Il reste 1 question sans réponse. Rendre la copie quand même ?',
      ),
      findsOneWidget,
    );
    // On annule : rien n'est enregistré.
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(session.qcm.attempts(), isEmpty);

    await tapKey(tester, 'passage-hand-in');
    await tester.tap(find.widgetWithText(FilledButton, 'Rendre la copie'));
    await tester.pumpAndSettle();
    expect(session.qcm.attempts().single.score, 1);
    expect(find.byType(AttemptPage), findsOneWidget);
  });

  testWidgets('une seule question : validée, la copie part sans confirmation', (
    tester,
  ) async {
    final plan = [planned(qru('Bonne1', 'Fausse1'))];
    await openPassage(tester, session, plan: plan);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    // La question est validée : la copie part sans confirmation.
    await tapKey(tester, 'validate');
    expect(find.byType(AttemptPage), findsOneWidget);
  });

  testWidgets('abandonner : confirmation, rien d\'enregistré', (tester) async {
    await openPassage(tester, session);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');

    await tapKey(tester, 'passage-close');
    expect(find.text('Abandonner ce passage ?'), findsOneWidget);
    // Annuler : on reste.
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(PassagePage), findsOneWidget);

    await tapKey(tester, 'passage-close');
    await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
    await tester.pumpAndSettle();
    expect(find.byType(PassagePage), findsNothing);
    expect(find.byKey(const ValueKey('launch')), findsOneWidget);
    expect(session.qcm.attempts(), isEmpty);
  });

  testWidgets('retour du système : même confirmation', (tester) async {
    await openPassage(tester, session);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Abandonner ce passage ?'), findsOneWidget);
    expect(find.byType(PassagePage), findsOneWidget);
  });

  group('minuteur', () {
    testWidgets('décompte, puis copie rendue à la fin du temps', (
      tester,
    ) async {
      var now = DateTime(2026, 1, 1, 10);
      await openPassage(
        tester,
        session,
        settings: const PassageSettings(timerMinutes: 1),
        clock: () => now,
      );
      Text timer() => tester.widget<Text>(
        find.descendant(of: key('passage-timer'), matching: find.byType(Text)),
      );
      expect(timer().data, '01:00');

      await tester.tap(find.text('Bonne1'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'validate');

      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(timer().data, '00:30');

      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(AttemptPage), findsOneWidget);
      final saved = session.qcm.attempts().single;
      expect(saved.timedOut, isTrue);
      expect(saved.duration, const Duration(minutes: 1));
      expect(saved.score, 1);
      expect(key('timed-out'), findsOneWidget);
    });

    testWidgets('fin du temps pendant une boîte de dialogue', (tester) async {
      var now = DateTime(2026, 1, 1, 10);
      await openPassage(
        tester,
        session,
        settings: const PassageSettings(timerMinutes: 5),
        clock: () => now,
      );
      await tapKey(tester, 'passage-hand-in');
      expect(find.byType(AlertDialog), findsOneWidget);

      now = now.add(const Duration(minutes: 6));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // La boîte est fermée, la copie remplace le passage.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PassagePage), findsNothing);
      expect(find.byType(AttemptPage), findsOneWidget);
      expect(session.qcm.attempts().single.timedOut, isTrue);
      // Retour : on retombe sur la page de départ, sans passage fantôme.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('launch')), findsOneWidget);
    });

    testWidgets('sans minuteur : pas d\'horloge affichée', (tester) async {
      await openPassage(tester, session);
      expect(key('passage-timer'), findsNothing);
    });
  });

  group('dossiers', () {
    testWidgets('bandeau du cas, contexte masquable', (tester) async {
      const info = CaseInfo(
        genre: CaseGenre.kfp,
        title: 'Douleur thoracique',
        context: 'Homme de 60 ans, douleur brutale.',
      );
      await openPassage(
        tester,
        session,
        plan: [
          planned(qru('Bonne1', 'Fausse1'), info: info, group: 0),
          planned(qru('Bonne2', 'Fausse2'), info: info, group: 0),
        ],
      );
      expect(key('case-banner'), findsOneWidget);
      expect(find.text('Douleur thoracique'), findsOneWidget);
      expect(find.textContaining('Homme de 60 ans'), findsOneWidget);
      await tapKey(tester, 'case-toggle');
      expect(find.textContaining('Homme de 60 ans'), findsNothing);
      await tapKey(tester, 'case-toggle');
      expect(find.textContaining('Homme de 60 ans'), findsOneWidget);
    });

    testWidgets('dossier progressif : la question suivante est verrouillée '
        'tant que la précédente n\'est pas vue', (tester) async {
      const info = CaseInfo(genre: CaseGenre.progressive, title: 'Dossier');
      await openPassage(
        tester,
        session,
        plan: [
          planned(qru('Bonne1', 'Fausse1'), info: info, group: 0),
          planned(qru('Bonne2', 'Fausse2'), info: info, group: 0),
          planned(qru('Bonne3', 'Fausse3'), info: info, group: 0),
        ],
      );
      // Q3 ne s'ouvre pas avant que Q2 ait été vue.
      expect(tester.widget<InkWell>(key('dot-2')).onTap, isNull);
      expect(tester.widget<InkWell>(key('dot-1')).onTap, isNotNull);
    });
  });

  testWidgets('écran étroit : pastilles en rangée, aucun débordement', (
    tester,
  ) async {
    await openPassage(tester, session, size: _narrow);
    expect(tester.takeException(), isNull);
    expect(key('dot-0'), findsOneWidget);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    expect(find.text('Question 2 sur 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('taille du texte : choix dans le menu', (tester) async {
    await openPassage(tester, session);
    double scaleOf() =>
        MediaQuery.of(tester.element(find.byType(QuestionView))).textScaler
            .scale(10);
    // Grand écran : 120 % par défaut.
    expect(scaleOf(), closeTo(12, 0.001));
    await tapKey(tester, 'passage-zoom');
    expect(find.text('170 %'), findsOneWidget);
    await tester.tap(find.text('170 %'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(scaleOf(), closeTo(17, 0.001));
    expect(tester.takeException(), isNull);
    expect(find.text('Question 1 sur 2'), findsOneWidget);
  });

  testWidgets('entraînement : la copie le mentionne', (tester) async {
    await openPassage(tester, session, practice: true);
    await tester.tap(find.text('Bonne1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'validate');
    await tapKey(tester, 'passage-hand-in');
    await tester.tap(find.widgetWithText(FilledButton, 'Rendre la copie'));
    await tester.pumpAndSettle();
    expect(session.qcm.attempts().single.practice, isTrue);
  });
}
