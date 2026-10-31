import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter_test/flutter_test.dart';

ChoiceQuestion qcm(
  List<bool> correct, {
  Set<int> critical = const {},
  bool pointed = false,
  double points = 1,
}) => ChoiceQuestion(
  body: 'Q',
  points: points,
  pointed: pointed,
  propositions: [
    for (var i = 0; i < correct.length; i++)
      Proposition(
        text: 'P$i',
        correct: correct[i],
        critical: critical.contains(i),
      ),
  ],
);

Grade g(Question q, Answer? a, [Scoring s = Scoring.edn]) =>
    gradeQuestion(q, a, s);

ChoiceAnswer t(Iterable<int> i) => ChoiceAnswer(i.toSet());

void main() {
  group('QRU', () {
    final q = qcm([false, true, false, false]);
    test('tout ou rien', () {
      expect(g(q, t([1])).verdict, Verdict.right);
      expect(g(q, t([1])).score, 1);
      expect(g(q, t([0])).verdict, Verdict.wrong);
      expect(g(q, t([0, 1])).verdict, Verdict.wrong);
      expect(g(q, t([])).verdict, Verdict.wrong);
    });

    test('même chose en barème Points', () {
      expect(g(q, t([1]), Scoring.points).score, 1);
      expect(g(q, t([0, 1]), Scoring.points).score, 0);
    });

    test('points de la question', () {
      final two = qcm([true, false], points: 2);
      expect(g(two, t([0])).score, 2);
      expect(g(two, t([0])).max, 2);
    });
  });

  group('QRM, barème EDN', () {
    final q = qcm([true, true, false, false, true]);
    test('aucune discordance : 1', () {
      final r = g(q, t([0, 1, 4]));
      expect(r.score, 1);
      expect(r.verdict, Verdict.right);
    });

    test('une discordance : 0,5', () {
      expect(g(q, t([0, 1])).score, 0.5); // oubli
      expect(g(q, t([0, 1, 4, 2])).score, 0.5); // coche en trop
      expect(g(q, t([0, 1])).verdict, Verdict.partial);
    });

    test('deux discordances : 0,2', () {
      expect(g(q, t([0, 4, 2])).score, 0.2); // un oubli + une en trop
      expect(g(q, t([0, 1, 4, 2, 3])).score, 0.2); // deux en trop
      expect(g(q, t([0, 1, 4, 2, 3])).verdict, Verdict.partial);
    });

    test('trois discordances ou plus : 0', () {
      expect(g(q, t([0, 1, 2, 3])).score, 0); // deux en trop + un oubli
      expect(g(q, t([2, 3])).score, 0);
      expect(g(q, t([2, 3])).verdict, Verdict.wrong);
    });

    test('deux oublis : 0,2', () {
      expect(g(q, t([0])).score, 0.2);
    });

    test('valeur mise à l\'échelle des points', () {
      final three = qcm([true, true, false], points: 3);
      expect(g(three, t([0])).score, 1.5);
      expect(g(three, t([0, 2])).score, 0.6);
    });
  });

  group('annulation (EDN)', () {
    test('bonne réponse indispensable oubliée', () {
      final q = qcm([true, true, false, false], critical: {0});
      expect(g(q, t([1])).score, 0);
      expect(g(q, t([0, 1])).score, 1);
    });

    test('mauvaise réponse inacceptable cochée', () {
      final q = qcm([true, true, false, false], critical: {3});
      expect(g(q, t([0, 1, 3])).score, 0);
      expect(g(q, t([0, 1, 2])).score, 0.5);
    });

    test('sans effet en barème Points', () {
      final q = qcm([true, true, false, false], critical: {0});
      expect(g(q, t([1]), Scoring.points).score, 0.75);
    });
  });

  group('QRM, barème Points', () {
    test('part des propositions bien traitées', () {
      final q = qcm([true, true, false, false]);
      expect(g(q, t([0, 1]), Scoring.points).score, 1);
      expect(g(q, t([0]), Scoring.points).score, 0.75);
      expect(g(q, t([0, 2]), Scoring.points).score, 0.5);
      expect(g(q, t([2, 3]), Scoring.points).score, 0);
      expect(g(q, t([0]), Scoring.points).verdict, Verdict.partial);
    });
  });

  group('QRP', () {
    final q = qcm([true, true, false, false, true], pointed: true);
    test('bonnes cochées sur attendues', () {
      expect(g(q, t([0, 1, 4])).score, 1);
      expect(g(q, t([0, 1, 4])).verdict, Verdict.right);
      expect(g(q, t([0, 1, 2])).score, closeTo(2 / 3, 1e-6));
      expect(g(q, t([0])).score, closeTo(1 / 3, 1e-6));
      expect(g(q, t([2, 3])).verdict, Verdict.wrong);
    });

    test('annulation en EDN seulement', () {
      final c = qcm([true, true, false], critical: {0}, pointed: true);
      expect(g(c, t([1])).score, 0);
      expect(g(c, t([1]), Scoring.points).score, 0.5);
    });
  });

  group('indices hors limites ignorés', () {
    test('QRM', () {
      final q = qcm([true, true, false]);
      expect(g(q, t([0, 1, 9, -1])).score, 1);
    });
  });

  group('TCS', () {
    const q = TcsQuestion(
      hypothesis: 'h',
      newInfo: 'i',
      panel: [0, 2, 6, 3, 0],
    );
    test('le niveau le plus choisi vaut tout, les autres au prorata', () {
      expect(g(q, const TcsAnswer(0)).score, 1);
      expect(g(q, const TcsAnswer(0)).verdict, Verdict.right);
      expect(g(q, const TcsAnswer(1)).score, 0.5);
      expect(g(q, const TcsAnswer(-1)).score, closeTo(1 / 3, 1e-6));
      expect(g(q, const TcsAnswer(1)).verdict, Verdict.partial);
      expect(g(q, const TcsAnswer(2)).score, 0);
      expect(g(q, const TcsAnswer(2)).verdict, Verdict.wrong);
      expect(g(q, const TcsAnswer(-2)).verdict, Verdict.wrong);
    });

    test('panel vide : jamais plus de zéro', () {
      const empty = TcsQuestion(hypothesis: 'h', newInfo: 'i');
      expect(g(empty, const TcsAnswer(0)).score, 0);
    });
  });

  group('QZP', () {
    const q = QzpQuestion(
      body: 'Où ?',
      image: 'abcdef0123.png',
      zones: [
        Zone(left: 0.1, top: 0.1, width: 0.2, height: 0.2),
        Zone(left: 0.6, top: 0.6, width: 0.2, height: 0.2),
      ],
    );
    test('juste si le point est dans une zone', () {
      expect(g(q, const PointAnswer(0.2, 0.2)).verdict, Verdict.right);
      expect(g(q, const PointAnswer(0.7, 0.7)).verdict, Verdict.right);
      expect(g(q, const PointAnswer(0.5, 0.5)).verdict, Verdict.wrong);
    });
  });

  group('QROC', () {
    const auto = QrocQuestion(
      body: 'Q',
      points: 4,
      elements: [
        ExpectedElement(pattern: 'infarctus|IDM', points: 2),
        ExpectedElement(pattern: 'troponine;ECG', points: 1),
        ExpectedElement(pattern: 'coronarographie', points: 1),
      ],
    );

    test('chaque élément rapporte ses points', () {
      var r = g(auto, const TextAnswer('Un IDM, troponine et ECG'));
      expect(r.score, 3);
      expect(r.verdict, Verdict.partial);
      r = g(
        auto,
        const TextAnswer('infarctus, ECG, troponine, coronarographie'),
      );
      expect(r.score, 4);
      expect(r.verdict, Verdict.right);
      r = g(auto, const TextAnswer('ECG seulement'));
      expect(r.score, 0);
      expect(r.verdict, Verdict.wrong);
    });

    test('éléments trouvés listés', () {
      expect(qrocHits(auto, 'IDM et coronarographie'), [true, false, true]);
    });

    test('sans élément : auto-évaluation', () {
      const free = QrocQuestion(body: 'Q', model: 'M');
      expect(g(free, const TextAnswer('x')).verdict, Verdict.pending);
      expect(g(free, const TextAnswer('x', self: 1)).verdict, Verdict.right);
      expect(g(free, const TextAnswer('x', self: 0.5)).score, 0.5);
      expect(
        g(free, const TextAnswer('x', self: 0.5)).verdict,
        Verdict.partial,
      );
      expect(g(free, const TextAnswer('x', self: 0)).verdict, Verdict.wrong);
    });
  });

  group('réponse absente ou d\'un autre genre', () {
    test('passée', () {
      final q = qcm([true, false]);
      expect(g(q, null).verdict, Verdict.skipped);
      expect(g(q, const TcsAnswer(1)).verdict, Verdict.skipped);
      expect(g(q, null).max, 1);
    });
  });

  group('Answer JSON', () {
    test('aller-retour', () {
      final a1 = Answer.fromJson(QuestionKind.qcm, t([3, 1]).toJson());
      expect((a1 as ChoiceAnswer).ticked, {1, 3});
      final a2 = Answer.fromJson(
        QuestionKind.qroc,
        const TextAnswer('abc', self: 0.5).toJson(),
      ) as TextAnswer;
      expect(a2.text, 'abc');
      expect(a2.self, 0.5);
      final a3 = Answer.fromJson(
        QuestionKind.tcs,
        const TcsAnswer(-2).toJson(),
      );
      expect((a3 as TcsAnswer).level, -2);
      final a4 = Answer.fromJson(
        QuestionKind.qzp,
        const PointAnswer(0.25, 0.75).toJson(),
      ) as PointAnswer;
      expect(a4.x, 0.25);
      expect(a4.y, 0.75);
    });

    test('illisible : null', () {
      expect(Answer.fromJson(QuestionKind.qcm, 'x'), isNull);
      expect(Answer.fromJson(QuestionKind.tcs, {'level': 7}), isNull);
      expect(Answer.fromJson(QuestionKind.qzp, {'x': 'a'}), isNull);
      expect(Answer.fromJson(QuestionKind.qroc, {'text': 3}), isNull);
    });
  });

  group('Totals', () {
    test('somme, comptes et note sur 20', () {
      final t = Totals.of(const [
        Grade(1, 1, Verdict.right),
        Grade(0.5, 1, Verdict.partial),
        Grade(0, 1, Verdict.wrong),
        Grade(0, 1, Verdict.skipped),
      ]);
      expect(t.score, 1.5);
      expect(t.max, 4);
      expect(t.right, 1);
      expect(t.partial, 1);
      expect(t.wrong, 1);
      expect(t.skipped, 1);
      expect(t.count, 4);
      expect(t.outOf20, 7.5);
      expect(t.ratio, 0.375);
    });

    test('épreuve vide', () {
      final t = Totals.of(const []);
      expect(t.outOf20, 0);
      expect(t.ratio, 0);
    });

    test('pas d\'erreur d\'arrondi visible', () {
      final t = Totals.of([
        for (var i = 0; i < 10; i++) const Grade(0.1, 1, Verdict.partial),
      ]);
      expect(t.score, 1);
    });
  });
}
