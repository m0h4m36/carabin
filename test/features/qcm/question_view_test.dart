import 'package:carabin/data/media_store.dart';
import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:carabin/features/qcm/question_view.dart';
import 'package:carabin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/async_wait.dart';
import '../../support/png.dart';
import '../../support/test_session.dart';

/// Montre une question et garde la dernière réponse émise.
class Harness {
  Answer? answer;
  int changes = 0;
  double? self;
}

Future<Harness> pump(
  WidgetTester tester,
  Question q, {
  List<int> order = const [],
  Answer? initial,
  bool reveal = false,
  bool readOnly = false,
  Scoring scoring = Scoring.edn,
  bool selfEvaluate = false,
  MediaStore? media,
}) async {
  final h = Harness()..answer = initial;
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = media ?? openTestSession().media;
  await tester.pumpWidget(
    Provider<MediaStore>.value(
      value: store,
      child: MaterialApp(
        theme: CarabinTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: QuestionView(
                question: q,
                order: order,
                answer: h.answer,
                reveal: reveal,
                scoring: scoring,
                onChanged: readOnly
                    ? null
                    : (a) => setState(() {
                        h.answer = a;
                        h.changes++;
                      }),
                onSelfEvaluate: selfEvaluate
                    ? (v) => setState(() => h.self = v)
                    : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return h;
}

Set<int> ticked(Harness h) =>
    h.answer is ChoiceAnswer ? (h.answer! as ChoiceAnswer).ticked : <int>{};

ChoiceQuestion choice(
  List<bool> correct, {
  bool pointed = false,
  Set<int> critical = const {},
}) => ChoiceQuestion(
  body: 'Énoncé **important**',
  pointed: pointed,
  propositions: [
    for (var i = 0; i < correct.length; i++)
      Proposition(
        text: 'Prop ${propositionLetter(i)}',
        correct: correct[i],
        critical: critical.contains(i),
      ),
  ],
);

void main() {
  test('lettres des propositions', () {
    expect(propositionLetter(0), 'A');
    expect(propositionLetter(25), 'Z');
    expect(propositionLetter(26), 'AA');
    expect(propositionLetter(27), 'AB');
  });

  group('QRU', () {
    testWidgets('une seule case à la fois, décochable', (tester) async {
      final h = await pump(tester, choice([true, false, false]));
      expect(find.text('QRU'), findsOneWidget);
      expect(find.textContaining('Énoncé'), findsOneWidget);
      await tester.tap(find.text('Prop A'));
      await tester.pump();
      expect(ticked(h), {0});
      await tester.tap(find.text('Prop B'));
      await tester.pump();
      expect(ticked(h), {1});
      await tester.tap(find.text('Prop B'));
      await tester.pump();
      expect(h.answer, isNull);
    });
  });

  group('QRM', () {
    testWidgets('plusieurs cases', (tester) async {
      final h = await pump(tester, choice([true, true, false]));
      expect(find.text('QRM'), findsOneWidget);
      await tester.tap(find.text('Prop A'));
      await tester.pump();
      await tester.tap(find.text('Prop C'));
      await tester.pump();
      expect(ticked(h), {0, 2});
      await tester.tap(find.text('Prop A'));
      await tester.pump();
      expect(ticked(h), {2});
    });
  });

  group('QRP', () {
    testWidgets('pas plus de réponses que celles attendues', (tester) async {
      final h = await pump(
        tester,
        choice([true, true, false, false], pointed: true),
      );
      expect(find.text('QRP'), findsOneWidget);
      expect(find.textContaining('Cochez 2 réponses'), findsOneWidget);
      await tester.tap(find.text('Prop A'));
      await tester.pump();
      await tester.tap(find.text('Prop C'));
      await tester.pump();
      expect(ticked(h), {0, 2});
      await tester.tap(find.text('Prop D')); // limite atteinte : ignoré
      await tester.pump();
      expect(ticked(h), {0, 2});
      await tester.tap(find.text('Prop A')); // on peut décocher
      await tester.pump();
      await tester.tap(find.text('Prop D'));
      await tester.pump();
      expect(ticked(h), {2, 3});
    });
  });

  testWidgets(
    'l\'ordre d\'affichage suit order, la réponse les positions d\'origine',
    (tester) async {
      final h = await pump(
        tester,
        choice([true, false, false]),
        order: const [2, 0, 1],
      );
      final texts = tester
          .widgetList<Text>(find.textContaining('Prop '))
          .map((t) => t.data ?? t.textSpan!.toPlainText())
          .toList();
      expect(texts, ['Prop C', 'Prop A', 'Prop B']);
      // première ligne affichée = proposition d'origine n° 2
      await tester.tap(find.text('Prop C'));
      await tester.pump();
      expect(ticked(h), {2});
      // la lettre de la première ligne est A
      expect(find.text('A'), findsOneWidget);
    },
  );

  testWidgets('un ordre invalide est ignoré', (tester) async {
    await pump(tester, choice([true, false]), order: const [5, 5]);
    expect(find.text('Prop A'), findsOneWidget);
    expect(find.text('Prop B'), findsOneWidget);
  });

  testWidgets('lecture seule : rien ne bouge', (tester) async {
    final h = await pump(tester, choice([true, false]), readOnly: true);
    await tester.tap(find.text('Prop A'));
    await tester.pump();
    expect(h.changes, 0);
  });

  group('correction d\'un QCM', () {
    testWidgets('bonnes, fausses et oubliées', (tester) async {
      final h = await pump(
        tester,
        choice([true, true, false], critical: {0, 2}),
        initial: const ChoiceAnswer({1, 2}),
        reveal: true,
      );
      expect(
        find.byIcon(Icons.check_circle),
        findsOneWidget,
      ); // B cochée à raison
      expect(find.byIcon(Icons.cancel), findsOneWidget); // C cochée à tort
      expect(
        find.byIcon(Icons.radio_button_unchecked),
        findsOneWidget,
      ); // A oubliée
      expect(find.textContaining('Oubliée'), findsOneWidget);
      expect(find.textContaining('Indispensable'), findsOneWidget);
      expect(find.textContaining('Inacceptable'), findsOneWidget);
      await tester.tap(find.text('Prop A'));
      await tester.pump();
      expect(h.changes, 0);
    });

    testWidgets('explication affichée seulement à la correction', (
      tester,
    ) async {
      final q = choice([true, false])
          .withCommon(explanation: 'Parce que voilà');
      await pump(tester, q);
      expect(find.text('Parce que voilà'), findsNothing);
      await pump(tester, q, reveal: true);
      expect(find.text('Parce que voilà'), findsOneWidget);
    });
  });

  group('QROC', () {
    testWidgets('saisie : réponse émise, vide = aucune', (tester) async {
      final h = await pump(
        tester,
        const QrocQuestion(body: 'Q', nature: 'Un diagnostic', model: 'M'),
      );
      expect(find.text('QROC'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('qroc-field')),
        'ma réponse',
      );
      await tester.pump();
      expect((h.answer! as TextAnswer).text, 'ma réponse');
      await tester.enterText(find.byKey(const ValueKey('qroc-field')), '   ');
      await tester.pump();
      expect(h.answer, isNull);
    });

    testWidgets('longueur maximale en lignes', (tester) async {
      final h = await pump(
        tester,
        const QrocQuestion(body: 'Q', maxLines: 2, model: 'M'),
      );
      await tester.enterText(find.byKey(const ValueKey('qroc-field')), 'a\nb');
      await tester.pump();
      expect((h.answer! as TextAnswer).text, 'a\nb');
      await tester.enterText(
        find.byKey(const ValueKey('qroc-field')),
        'a\nb\nc',
      );
      await tester.pump();
      expect((h.answer! as TextAnswer).text, 'a\nb'); // la 3e ligne est refusée
    });

    testWidgets('correction avec éléments attendus', (tester) async {
      await pump(
        tester,
        const QrocQuestion(
          body: 'Q',
          model: 'Infarctus du myocarde',
          elements: [
            ExpectedElement(pattern: 'infarctus|IDM', points: 2),
            ExpectedElement(pattern: 'troponine'),
          ],
        ),
        initial: const TextAnswer('Un IDM'),
        reveal: true,
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.text('Infarctus du myocarde'), findsOneWidget);
      expect(find.text('Un IDM'), findsOneWidget);
      expect(find.text('Juste'), findsNothing); // pas d'auto-évaluation
    });

    testWidgets('auto-évaluation', (tester) async {
      final h = await pump(
        tester,
        const QrocQuestion(body: 'Q', model: 'M'),
        initial: const TextAnswer('x'),
        reveal: true,
        selfEvaluate: true,
      );
      await tester.tap(find.text('Partielle'));
      await tester.pump();
      expect(h.self, 0.5);
      await tester.tap(find.text('Juste'));
      await tester.pump();
      expect(h.self, 1);
      await tester.tap(find.text('Fausse'));
      await tester.pump();
      expect(h.self, 0);
    });
  });

  group('TCS', () {
    const q = TcsQuestion(
      hypothesis: 'une embolie pulmonaire',
      newInfo: 'des D-dimères négatifs',
      panel: [0, 1, 6, 3, 0],
    );

    testWidgets('choix d\'un niveau', (tester) async {
      final h = await pump(tester, q);
      expect(find.text('TCS'), findsOneWidget);
      expect(find.text('une embolie pulmonaire'), findsOneWidget);
      expect(find.text('L\'hypothèse est infirmée'), findsOneWidget);
      await tester.tap(find.text('−1'));
      await tester.pump();
      expect((h.answer! as TcsAnswer).level, -1);
      await tester.tap(find.text('+2'));
      await tester.pump();
      expect((h.answer! as TcsAnswer).level, 2);
    });

    testWidgets('libellés personnalisés', (tester) async {
      await pump(
        tester,
        q.copyWith(lowLabel: 'Éliminée', highLabel: 'Certaine'),
      );
      expect(find.text('Éliminée'), findsOneWidget);
      expect(find.text('Certaine'), findsOneWidget);
    });

    testWidgets('correction : effectifs du panel', (tester) async {
      await pump(tester, q, initial: const TcsAnswer(1), reveal: true);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('QZP', () {
    late MediaStore media;
    late String image;
    setUp(() {
      media = openTestSession().media;
      image = media.addBytes(solidPng(100, 50), 'png');
    });

    QzpQuestion qzp() => QzpQuestion(
      body: 'Où est la lésion ?',
      image: image,
      zones: const [Zone(left: 0.0, top: 0.0, width: 0.5, height: 0.5)],
    );

    testWidgets('toucher l\'image donne un point en fractions', (tester) async {
      final h = await pump(tester, qzp(), media: media);
      final surface = find.byKey(const ValueKey('qzp-surface'));
      await waitForWidget(tester, surface);
      final rect = tester.getRect(surface);
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * 0.25, rect.height * 0.5),
      );
      await tester.pump();
      final a = h.answer! as PointAnswer;
      expect(a.x, closeTo(0.25, 0.01));
      expect(a.y, closeTo(0.5, 0.01));
    });

    testWidgets('correction : plus de changement possible', (tester) async {
      final h = await pump(
        tester,
        qzp(),
        media: media,
        initial: const PointAnswer(0.2, 0.2),
        reveal: true,
      );
      final surface = find.byKey(const ValueKey('qzp-surface'));
      await waitForWidget(tester, surface);
      await tester.tap(surface);
      await tester.pump();
      expect(h.changes, 0);
      expect(find.text('Votre point'), findsOneWidget);
    });

    testWidgets('image manquante : message, pas de plantage', (tester) async {
      await pump(
        tester,
        const QzpQuestion(body: 'Q', image: 'aaaaaaaaaa.png'),
        media: media,
      );
      await tester.pump();
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
