import 'package:carabin/domain/scheduling.dart';
import 'package:carabin/domain/study_options.dart';
import 'package:carabin/l10n/textes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = SchedulingService();
  final t0 = DateTime.utc(2030, 3, 1, 9);

  group('FSRS', () {
    test('suite de référence de la bibliothèque (Bien×6, Encore×2, Bien×5)', () {
      // Intervalles en jours publiés par la bibliothèque `fsrs` pour la
      // même suite de réponses, paramètres par défaut, rétention 0,9.
      const reference = [0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40];
      const grades = [
        Grade.good, Grade.good, Grade.good, Grade.good, Grade.good, Grade.good,
        Grade.again, Grade.again,
        Grade.good, Grade.good, Grade.good, Grade.good, Grade.good,
      ];
      var now = t0;
      var sched = Schedule.fresh(t0.millisecondsSinceEpoch);
      final got = <int>[];
      for (final g in grades) {
        final o = service.answer(1, sched, g, now, retention: 0.9);
        sched = o.schedule;
        got.add(o.interval.inDays);
        now = DateTime.fromMillisecondsSinceEpoch(sched.dueMs, isUtc: true);
      }
      expect(got, reference);
    });

    test('une carte neuve répondue « Encore » reste en apprentissage', () {
      final o = service.answer(1, Schedule.fresh(t0.millisecondsSinceEpoch), Grade.again, t0, retention: 0.9);
      expect(o.schedule.state, CardState.learning);
      expect(o.interval, const Duration(minutes: 1));
      expect(o.schedule.lapses, 0);
      expect(o.schedule.reps, 1);
    });

    test('oublier une carte mûre compte une rechute et passe en réapprentissage', () {
      var sched = Schedule.fresh(t0.millisecondsSinceEpoch);
      var now = t0;
      for (var i = 0; i < 4; i++) {
        final o = service.answer(1, sched, Grade.good, now, retention: 0.9);
        sched = o.schedule;
        now = DateTime.fromMillisecondsSinceEpoch(sched.dueMs, isUtc: true);
      }
      expect(sched.state, CardState.review);
      final lapse = service.answer(1, sched, Grade.again, now, retention: 0.9);
      expect(lapse.schedule.state, CardState.relearning);
      expect(lapse.schedule.lapses, 1);
      expect(lapse.interval, const Duration(minutes: 10));
    });

    test('les quatre délais prévus sont croissants', () {
      final p = service.preview(1, Schedule.fresh(t0.millisecondsSinceEpoch), t0, retention: 0.9);
      expect(p.keys, Grade.values);
      expect(p[Grade.again]!, lessThan(p[Grade.good]!));
      expect(p[Grade.good]!, lessThan(p[Grade.easy]!));
      expect(p[Grade.hard]!, lessThanOrEqualTo(p[Grade.good]!));
    });

    test('le délai prévu est exactement celui appliqué', () {
      var sched = Schedule.fresh(t0.millisecondsSinceEpoch);
      var now = t0;
      for (var i = 0; i < 5; i++) {
        final p = service.preview(1, sched, now, retention: 0.9);
        final o = service.answer(1, sched, Grade.good, now, retention: 0.9);
        expect(o.interval, p[Grade.good]);
        sched = o.schedule;
        now = DateTime.fromMillisecondsSinceEpoch(sched.dueMs, isUtc: true);
      }
    });

    test('une exigence plus haute resserre les intervalles', () {
      final low = service.milestones(0.80);
      final def = service.milestones(0.90);
      final high = service.milestones(0.97);
      expect(def.first, 4);
      for (var i = 0; i < 4; i++) {
        expect(high[i], lessThanOrEqualTo(def[i]));
        expect(def[i], lessThanOrEqualTo(low[i]));
      }
      expect(high.last, lessThan(low.last));
    });

    test('jalons à 90 % : J+4, J+18, J+63, J+198', () {
      // Cumul des intervalles de référence 4, 14, 45, 135 (FSRS-6, paramètres
      // par défaut). La spécification donne « environ J4 J18 J62 J187 ».
      expect(service.milestones(0.90), [4, 18, 63, 198]);
    });

    test('charge estimée : 5 jours de révision la première année à 90 %', () {
      expect(service.reviewDaysWithin(0.90), 5); // J0, J4, J18, J63, J198
      expect(service.reviewDaysWithin(0.97), greaterThan(service.reviewDaysWithin(0.80)));
    });

    test('probabilité de souvenir : 0 pour une carte neuve, décroît avec le temps', () {
      expect(service.retrievability(Schedule.fresh(0), t0), 0);
      var sched = Schedule.fresh(t0.millisecondsSinceEpoch);
      var now = t0;
      for (var i = 0; i < 3; i++) {
        final o = service.answer(1, sched, Grade.good, now, retention: 0.9);
        sched = o.schedule;
        now = DateTime.fromMillisecondsSinceEpoch(sched.dueMs, isUtc: true);
      }
      final soon = service.retrievability(sched, now.subtract(const Duration(days: 5)));
      final late = service.retrievability(sched, now.add(const Duration(days: 60)));
      expect(soon, greaterThan(late));
      expect(soon, inInclusiveRange(0, 1));
    });
  });

  group('affichage des délais', () {
    test('unités', () {
      expect(Tx.interval(const Duration(seconds: 30)), '< 1 min');
      expect(Tx.interval(const Duration(minutes: 10)), '10 min');
      expect(Tx.interval(const Duration(hours: 5)), '5 h');
      expect(Tx.interval(const Duration(days: 4)), '4 j');
      expect(Tx.interval(const Duration(days: 62)), '2 mois');
      expect(Tx.interval(const Duration(days: 365)), '1 an');
      expect(Tx.interval(const Duration(days: 800)), '2,2 ans');
    });
  });

  group('réglages d\'étude', () {
    test('aller-retour JSON', () {
      const o = StudyOptions(
        onePerNotePerDay: false,
        order: StudyOrder.course,
        newPerDay: null,
        reviewsPerDay: 150,
        retention: 0.93,
        leechThreshold: 5,
        leechAction: LeechAction.none,
        showPassCounter: false,
      );
      final back = StudyOptions.fromJson(o.toJson());
      expect(back.onePerNotePerDay, isFalse);
      expect(back.order, StudyOrder.course);
      expect(back.newPerDay, isNull);
      expect(back.reviewsPerDay, 150);
      expect(back.retention, 0.93);
      expect(back.leechThreshold, 5);
      expect(back.leechAction, LeechAction.none);
      expect(back.showPassCounter, isFalse);
    });

    test('valeurs absentes ou invalides : retour aux valeurs par défaut', () {
      for (final bad in [null, '', 'pas du json', '[]', '{"retention": 5, "newPerDay": -3}']) {
        final o = StudyOptions.fromJson(bad);
        expect(o.retention, inInclusiveRange(StudyOptions.minRetention, StudyOptions.maxRetention));
        expect(o.newPerDay == null || o.newPerDay! >= 0, isTrue);
      }
      expect(StudyOptions.fromJson(null).newPerDay, 20);
      expect(StudyOptions.fromJson(null).reviewsPerDay, 200);
    });

    test('copyWith peut retirer un plafond', () {
      const o = StudyOptions();
      expect(o.copyWith(newPerDay: null).newPerDay, isNull);
      expect(o.copyWith(retention: 0.8).newPerDay, 20);
    });
  });
}
