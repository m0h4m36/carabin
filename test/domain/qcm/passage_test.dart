import 'dart:math';

import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/domain/qcm/passage.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter_test/flutter_test.dart';

ChoiceQuestion q(String body, {bool ready = true}) => ChoiceQuestion(
  body: body,
  propositions: [
    Proposition(text: 'A', correct: ready),
    const Proposition(text: 'B'),
    const Proposition(text: ''),
  ],
);

SourceQuestion sq(String body, {bool ready = true, int exam = 1}) =>
    SourceQuestion(
      question: q(body, ready: ready),
      examId: exam,
    );

PlannedQuestion pq(String body, {int group = -1, CaseGenre? genre}) =>
    PlannedQuestion(
      question: q(body).cleaned(),
      caseGroup: group,
      info: genre == null ? null : CaseInfo(genre: genre),
    );

class Clock {
  DateTime now = DateTime(2026, 10, 31, 10);
  DateTime call() => now;
}

void main() {
  group('planSession', () {
    final units = [
      SourceUnit([sq('1')]),
      SourceUnit([
        sq('2a'),
        sq('2b'),
      ], info: const CaseInfo(genre: CaseGenre.kfp)),
      SourceUnit([sq('3', ready: false)]),
      SourceUnit([sq('4')]),
      SourceUnit([
        sq('5a'),
        sq('5b', ready: false),
      ], info: const CaseInfo(genre: CaseGenre.progressive)),
    ];

    test('ne garde que les questions prêtes, dans l\'ordre', () {
      final plan = planSession(units, const PassageSettings(), Random(1));
      expect(plan.map((p) => p.question.body), ['1', '2a', '2b', '4', '5a']);
    });

    test('les cas partagent un numéro de groupe', () {
      final plan = planSession(units, const PassageSettings(), Random(1));
      expect(plan.map((p) => p.caseGroup), [-1, 0, 0, -1, 1]);
      expect(plan[1].info?.genre, CaseGenre.kfp);
    });

    test('propositions vides retirées, ordre conservé sans mélange', () {
      final plan = planSession(
        units,
        const PassageSettings(shuffleProps: false),
        Random(1),
      );
      final c = plan.first.question as ChoiceQuestion;
      expect(c.propositions, hasLength(2));
      expect(plan.first.order, [0, 1]);
    });

    test('mélange des propositions : permutation valide', () {
      final big = SourceUnit([
        SourceQuestion(
          question: ChoiceQuestion(
            body: 'Q',
            propositions: [
              for (var i = 0; i < 8; i++)
                Proposition(text: 'P$i', correct: i == 0),
            ],
          ),
        ),
      ]);
      final order = planSession(
        [big],
        const PassageSettings(),
        Random(7),
      ).single.order;
      expect(order.toList()..sort(), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(order, isNot([0, 1, 2, 3, 4, 5, 6, 7]));
    });

    test('une partie : cas entiers, nombre atteint ou dépassé', () {
      final plan = planSession(
        units,
        const PassageSettings(part: true, partCount: 2),
        Random(1),
      );
      // "1" (1 question) puis le cas 2a/2b (2) : 3 questions, jamais coupé
      expect(plan.map((p) => p.question.body), ['1', '2a', '2b']);
    });

    test('une partie au hasard : tirage sans doublon', () {
      final plan = planSession(
        units,
        const PassageSettings(part: true, partCount: 3, random: true),
        Random(3),
      );
      final bodies = plan.map((p) => p.question.body).toList();
      expect(bodies.toSet(), hasLength(bodies.length));
      expect(bodies.length, greaterThanOrEqualTo(3));
      // un cas est toujours entier et dans son ordre
      if (bodies.contains('2a')) {
        expect(bodies.indexOf('2b'), bodies.indexOf('2a') + 1);
      }
    });

    test('cas sans question prête abandonné', () {
      final plan = planSession(
        [
          SourceUnit([
            sq('x', ready: false),
          ], info: const CaseInfo(genre: CaseGenre.lca)),
          SourceUnit([sq('y')]),
        ],
        const PassageSettings(),
        Random(1),
      );
      expect(plan.map((p) => p.question.body), ['y']);
    });
  });

  group('PassageSettings', () {
    test('JSON', () {
      const s = PassageSettings(
        part: true,
        partCount: 7,
        random: true,
        correction: Correction.each,
        backAllowed: true,
        timerMinutes: 90,
        scoring: Scoring.points,
        shuffleProps: false,
      );
      final back = PassageSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(back.timerMinutes, 90);
      expect(back.correction, Correction.each);
    });

    test('valeurs par défaut quand tout manque ou est absurde', () {
      for (final j in <Object?>[null, 'x', <String, Object?>{}]) {
        final s = PassageSettings.fromJson(j);
        expect(s.part, isFalse);
        expect(s.correction, Correction.end);
        expect(s.backAllowed, isFalse);
        expect(s.timerMinutes, isNull);
        expect(s.scoring, Scoring.edn);
        expect(s.shuffleProps, isTrue);
      }
      expect(PassageSettings.fromJson({'timer': -3}).timerMinutes, isNull);
      expect(PassageSettings.fromJson({'partCount': 0}).partCount, 10);
    });

    test('copyWith peut retirer le minuteur', () {
      const s = PassageSettings(timerMinutes: 30);
      expect(s.copyWith(timerMinutes: null).timerMinutes, isNull);
      expect(s.copyWith().timerMinutes, 30);
    });
  });

  group('Passage : déroulé', () {
    Passage three({PassageSettings? settings, Clock? clock}) => Passage(
      [pq('1'), pq('2'), pq('3')],
      settings ?? const PassageSettings(),
      clock: clock?.call,
    );

    test('valider puis avancer jusqu\'à la fin rend la copie', () {
      final p = three();
      expect(p.current, 0);
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      expect(p.current, 1);
      p.validate(const ChoiceAnswer({1}));
      p.advance();
      expect(p.current, 2);
      expect(p.finished, isFalse);
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      expect(p.finished, isTrue);
      final t = p.totals();
      expect(t.right, 2);
      expect(t.wrong, 1);
    });

    test('passer une question', () {
      final p = three();
      p.skip();
      expect(p.status[0], QStatus.skipped);
      p.advance();
      expect(p.current, 1);
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      // plus aucune question neuve : la copie est rendue, la première reste passée
      expect(p.finished, isTrue);
      final t = p.totals();
      expect(t.skipped, 1);
      expect(t.right, 2);
    });

    test('une question passée peut être rouverte avant la fin', () {
      final p = three();
      p.skip();
      p.advance();
      expect(p.canOpen(0), isTrue);
      p.open(0);
      p.validate(const ChoiceAnswer({0}));
      expect(p.status[0], QStatus.validated);
    });

    test('retour en arrière interdit par défaut', () {
      final p = three();
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      expect(p.canOpen(0), isFalse);
      expect(() => p.open(0), throwsStateError);
      expect(p.canEdit(0), isFalse);
    });

    test('retour permis : on peut rouvrir et corriger', () {
      final p = three(settings: const PassageSettings(backAllowed: true));
      p.validate(const ChoiceAnswer({1}));
      p.advance();
      p.open(0);
      expect(p.canEdit(0), isTrue);
      p.validate(const ChoiceAnswer({0}));
      expect(p.gradeOf(0).verdict, Verdict.right);
    });

    test(
      'correction à chaque question : réponse figée même si retour permis',
      () {
        final p = three(
          settings: const PassageSettings(
            backAllowed: true,
            correction: Correction.each,
          ),
        );
        p.validate(const ChoiceAnswer({1}));
        p.advance();
        p.open(0); // on peut relire la correction
        expect(p.canEdit(0), isFalse);
        expect(() => p.validate(const ChoiceAnswer({0})), throwsStateError);
      },
    );

    test('avancer saute les questions déjà traitées et revient en arrière', () {
      final p = three(settings: const PassageSettings(backAllowed: true));
      p.open(2);
      p.validate(const ChoiceAnswer({0}));
      p.advance(); // aucune neuve après 2 : retour à la 0
      expect(p.current, 0);
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      expect(p.current, 1);
    });

    test('doute', () {
      final p = three();
      p.toggleDoubt();
      expect(p.doubt[0], isTrue);
      p.toggleDoubt(1);
      expect(p.doubt[1], isTrue);
      p.toggleDoubt();
      expect(p.doubt[0], isFalse);
    });

    test('brouillon conservé quand on change de question', () {
      final p = three();
      p.setDraft(0, const ChoiceAnswer({1}));
      p.open(1);
      expect((p.draft(0) as ChoiceAnswer).ticked, {1});
      p.validate(const ChoiceAnswer({0}));
      expect(p.draft(1), isNull);
    });

    test('rendre la copie avec des questions jamais ouvertes', () {
      final p = three();
      p.validate(const ChoiceAnswer({0}));
      p.finish();
      expect(p.finished, isTrue);
      final t = p.totals();
      expect(t.right, 1);
      expect(t.skipped, 2);
      expect(p.canOpen(1), isFalse);
      expect(p.nextTarget(), isNull);
    });

    test('compteurs', () {
      final p = three();
      p.validate(const ChoiceAnswer({0}));
      p.advance();
      p.skip();
      expect(p.validatedCount, 1);
      expect(p.skippedCount, 1);
      expect(p.count, 3);
    });

    test('passage vide', () {
      final p = Passage(const [], const PassageSettings());
      expect(p.count, 0);
      expect(p.nextTarget(), isNull);
      p.advance();
      expect(p.finished, isTrue);
      expect(p.totals().outOf20, 0);
    });
  });

  group('Passage : dossier progressif', () {
    Passage story({bool back = false}) => Passage([
      pq('a', group: 0, genre: CaseGenre.progressive),
      pq('b', group: 0, genre: CaseGenre.progressive),
      pq('c', group: 0, genre: CaseGenre.progressive),
      pq('z'),
    ], PassageSettings(backAllowed: back));

    test(
      'la suite de l\'histoire n\'est accessible qu\'après la précédente',
      () {
        final p = story();
        // a est ouverte donc vue : b est accessible
        expect(p.canOpen(1), isTrue);
        // c exige que b ait été vue
        expect(p.canOpen(2), isFalse);
        p.open(1);
        expect(p.canOpen(2), isTrue);
      },
    );

    test('une question ne se rouvre plus quand la suite a été vue', () {
      final p = story(back: true);
      p.skip();
      p.open(1); // la suite est vue
      expect(p.canOpen(0), isFalse);
      // hors dossier progressif, le retour reste libre
      p.open(3);
      expect(p.canOpen(3), isTrue);
    });

    test('KFP et LCA : pas de verrou', () {
      final p = Passage([
        pq('a', group: 0, genre: CaseGenre.kfp),
        pq('b', group: 0, genre: CaseGenre.kfp),
      ], const PassageSettings());
      p.skip();
      p.open(1);
      expect(p.canOpen(0), isTrue);
    });
  });

  group('Passage : temps', () {
    test('durée et temps restant', () {
      final c = Clock();
      final p = Passage(
        [pq('1')],
        const PassageSettings(timerMinutes: 10),
        clock: c.call,
      );
      expect(p.remaining(), const Duration(minutes: 10));
      c.now = c.now.add(const Duration(minutes: 4, seconds: 30));
      expect(p.elapsed(), const Duration(minutes: 4, seconds: 30));
      expect(p.remaining(), const Duration(minutes: 5, seconds: 30));
      p.finish();
      c.now = c.now.add(const Duration(hours: 1));
      expect(p.duration, const Duration(minutes: 4, seconds: 30));
      expect(p.timedOut, isFalse);
    });

    test('sans minuteur', () {
      final p = Passage([pq('1')], const PassageSettings());
      expect(p.limit, isNull);
      expect(p.remaining(), isNull);
    });

    test('temps écoulé : copie rendue, durée plafonnée', () {
      final c = Clock();
      final p = Passage(
        [pq('1'), pq('2')],
        const PassageSettings(timerMinutes: 1),
        clock: c.call,
      );
      p.validate(const ChoiceAnswer({0}));
      c.now = c.now.add(const Duration(minutes: 5));
      expect(p.remaining(), Duration.zero);
      p.expire();
      expect(p.finished, isTrue);
      expect(p.timedOut, isTrue);
      expect(p.duration, const Duration(minutes: 1));
      expect(p.totals().skipped, 1);
    });
  });
}
