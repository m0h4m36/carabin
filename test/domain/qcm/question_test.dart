import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter_test/flutter_test.dart';

ChoiceQuestion choice({
  String body = 'Énoncé',
  List<Proposition>? props,
  bool pointed = false,
}) => ChoiceQuestion(
  body: body,
  pointed: pointed,
  propositions:
      props ??
      const [Proposition(text: 'A', correct: true), Proposition(text: 'B')],
);

void main() {
  group('validation', () {
    test('QCM prêt', () {
      expect(choice().isReady, isTrue);
    });

    test('énoncé, propositions et bonne réponse requis', () {
      expect(choice(body: '  ').issues, contains(QuestionIssue.emptyBody));
      final few = choice(props: const [Proposition(text: 'A', correct: true)]);
      expect(few.issues, contains(QuestionIssue.tooFewPropositions));
      final none = choice(
        props: const [
          Proposition(text: 'A'),
          Proposition(text: 'B'),
        ],
      );
      expect(none.issues, [QuestionIssue.noCorrectProposition]);
    });

    test('les propositions vides ne comptent pas', () {
      final q = choice(
        props: const [
          Proposition(text: 'A', correct: true),
          Proposition(text: ' '),
          Proposition(text: 'B'),
          Proposition(),
        ],
      );
      expect(q.isReady, isTrue);
      expect(q.written, hasLength(2));
      expect(q.cleaned().propositions, hasLength(2));
      final onlyBlank = choice(
        props: const [
          Proposition(text: 'A', correct: true),
          Proposition(),
        ],
      );
      expect(onlyBlank.issues, contains(QuestionIssue.tooFewPropositions));
    });

    test('forme : QRU, QRM, QRP', () {
      expect(choice().shape, ChoiceShape.qru);
      final qrm = choice(
        props: const [
          Proposition(text: 'A', correct: true),
          Proposition(text: 'B', correct: true),
        ],
      );
      expect(qrm.shape, ChoiceShape.qrm);
      expect(choice(pointed: true).shape, ChoiceShape.qrp);
      expect(choice(pointed: true).kind, QuestionKind.qrp);
    });

    test('QROC : réponse modèle ou éléments attendus', () {
      const q = QrocQuestion(body: 'Q');
      expect(q.issues, [QuestionIssue.qrocNothingToCompare]);
      expect(q.withCommon(body: 'Q'), isA<QrocQuestion>());
      expect(q.copyWith(model: 'réponse').isReady, isTrue);
      final withElements = q.copyWith(
        elements: const [ExpectedElement(pattern: 'foie')],
      );
      expect(withElements.isReady, isTrue);
      expect(withElements.autoGraded, isTrue);
      // élément vide ou sans point : ignoré
      final unusable = q.copyWith(
        elements: const [
          ExpectedElement(pattern: ' '),
          ExpectedElement(pattern: 'foie', points: 0),
        ],
      );
      expect(unusable.autoGraded, isFalse);
      expect(unusable.isReady, isFalse);
    });

    test('TCS : hypothèse, information, panel', () {
      const q = TcsQuestion();
      expect(q.issues, [
        QuestionIssue.tcsHypothesis,
        QuestionIssue.tcsNewInfo,
        QuestionIssue.tcsPanel,
      ]);
      final ok = q.copyWith(
        hypothesis: 'h',
        newInfo: 'i',
        panel: const [0, 1, 3, 1, 0],
      );
      expect(ok.isReady, isTrue);
      expect(ok.panelTotal, 5);
      expect(ok.panelMax, 3);
    });

    test('QZP : énoncé, image, zone', () {
      const q = QzpQuestion();
      expect(q.issues, [
        QuestionIssue.emptyBody,
        QuestionIssue.qzpImage,
        QuestionIssue.qzpZone,
      ]);
      final ok = QzpQuestion(
        body: 'Où ?',
        image: 'abcdef0123.png',
        zones: const [Zone(left: 0.1, top: 0.1, width: 0.2, height: 0.2)],
      );
      expect(ok.isReady, isTrue);
      expect(ok.mediaNames, {'abcdef0123.png'});
    });
  });

  group('JSON', () {
    test('aller-retour pour chaque genre', () {
      final list = <Question>[
        choice().withCommon(
          images: ['0123456789abcdef.png'],
          explanation: 'Parce que',
          points: 2,
        ),
        choice(pointed: true),
        const QrocQuestion(
          body: 'Q',
          nature: 'Un diagnostic',
          maxLines: 3,
          model: 'M',
          elements: [ExpectedElement(pattern: 'a|b;c', points: 2)],
        ),
        const TcsQuestion(
          body: 'Situation',
          hypothesis: 'h',
          newInfo: 'i',
          lowLabel: 'bas',
          highLabel: 'haut',
          panel: [0, 2, 5, 1, 0],
        ),
        const QzpQuestion(
          body: 'Où ?',
          image: 'abcdef0123.png',
          zones: [Zone(left: 0, top: 0.5, width: 0.5, height: 0.5)],
        ),
      ];
      for (final q in list) {
        final back = Question.fromJson(q.toJson());
        expect(back.toJson(), q.toJson());
        expect(back.runtimeType, q.runtimeType);
        expect(back.kind, q.kind);
      }
    });

    test('critique et points conservés', () {
      final q = choice(
        props: const [
          Proposition(text: 'A', correct: true, critical: true),
          Proposition(text: 'B'),
        ],
      ).withCommon(points: 3);
      final back = Question.fromJson(q.toJson()) as ChoiceQuestion;
      expect(back.propositions.first.critical, isTrue);
      expect(back.points, 3);
    });

    test('entrées invalides refusées', () {
      expect(() => Question.fromJson('x'), throwsFormatException);
      expect(() => Question.fromJson({'kind': 'zzz'}), throwsFormatException);
      expect(
        () => Question.fromJson({'kind': 'qcm', 'points': 0}),
        throwsFormatException,
      );
      expect(
        () => Question.fromJson({'kind': 'qcm', 'points': 'a'}),
        throwsFormatException,
      );
      expect(
        () => Question.fromJson({
          'kind': 'qcm',
          'images': ['../../etc/passwd'],
        }),
        throwsFormatException,
      );
      expect(
        () => Question.fromJson({
          'kind': 'qcm',
          'propositions': List.filled(maxPropositions + 1, {'text': 'x'}),
        }),
        throwsFormatException,
      );
      expect(
        () => Question.fromJson({
          'kind': 'qzp',
          'zones': [
            {'x': 0.9, 'y': 0, 'w': 0.5, 'h': 0.1},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => Question.fromJson({
          'kind': 'tcs',
          'panel': [1, -1, 0, 0, 0],
        }),
        throwsFormatException,
      );
    });

    test('panel TCS complété à cinq niveaux', () {
      final q = Question.fromJson({
        'kind': 'tcs',
        'panel': [1, 2],
      }) as TcsQuestion;
      expect(q.panel, [1, 2, 0, 0, 0]);
    });

    test('lignes de QROC trop longues ignorées', () {
      final q =
          Question.fromJson({'kind': 'qroc', 'maxLines': 999}) as QrocQuestion;
      expect(q.maxLines, isNull);
    });
  });

  group('changement de genre', () {
    test('garde le commun et les propositions entre QCM et QRP', () {
      final q = choice().withCommon(explanation: 'E', points: 2);
      final qrp = q.convertTo(QuestionKind.qrp) as ChoiceQuestion;
      expect(qrp.pointed, isTrue);
      expect(qrp.propositions, q.propositions);
      expect(qrp.explanation, 'E');
      expect(qrp.points, 2);
      final back = qrp.convertTo(QuestionKind.qcm) as ChoiceQuestion;
      expect(back.pointed, isFalse);
    });

    test('vers un autre genre : propositions perdues, énoncé gardé', () {
      final q = choice(body: 'Mon énoncé');
      final tcs = q.convertTo(QuestionKind.tcs);
      expect(tcs, isA<TcsQuestion>());
      expect(tcs.body, 'Mon énoncé');
      expect(identical(q.convertTo(QuestionKind.qcm), q), isTrue);
    });
  });

  group('médias', () {
    test('renommage', () {
      const q = QzpQuestion(
        body: 'Q',
        images: ['aaaaaaaa.png'],
        image: 'bbbbbbbb.png',
        zones: [Zone(left: 0, top: 0, width: 1, height: 1)],
      );
      final r = q.remapMedia((n) => 'x$n');
      expect(r.images, ['xaaaaaaaa.png']);
      expect(r.image, 'xbbbbbbbb.png');
      expect(q.mediaNames, {'aaaaaaaa.png', 'bbbbbbbb.png'});
    });
  });

  group('Zone', () {
    test('contains inclut les bords', () {
      const z = Zone(left: 0.2, top: 0.2, width: 0.2, height: 0.2);
      expect(z.contains(0.2, 0.2), isTrue);
      expect(z.contains(0.4, 0.4), isTrue);
      expect(z.contains(0.41, 0.3), isFalse);
    });
  });
}
