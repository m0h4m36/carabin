import 'package:fsrs/fsrs.dart' as fsrs;

/// États d'une carte, tels qu'ils sont stockés en base.
abstract final class CardState {
  static const newCard = 0;
  static const learning = 1;
  static const review = 2;
  static const relearning = 3;
}

/// Les quatre réponses possibles.
enum Grade {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Grade(this.value);
  final int value;

  static Grade fromValue(int v) => Grade.values.firstWhere((g) => g.value == v);

  fsrs.Rating get _rating => fsrs.Rating.fromValue(value);
}

/// État d'ordonnancement d'une carte (sans son contenu).
class Schedule {
  const Schedule({
    required this.state,
    this.step,
    this.stability,
    this.difficulty,
    required this.dueMs,
    this.lastReviewMs,
    this.reps = 0,
    this.lapses = 0,
  });

  final int state;
  final int? step;
  final double? stability;
  final double? difficulty;

  /// Échéance en millisecondes depuis 1970 (UTC).
  final int dueMs;
  final int? lastReviewMs;
  final int reps;
  final int lapses;

  /// Carte neuve : jamais révisée.
  factory Schedule.fresh(int nowMs) =>
      Schedule(state: CardState.newCard, dueMs: nowMs);

  bool get isNew => state == CardState.newCard;
}

/// Résultat d'une réponse : nouvel état et délai jusqu'au prochain passage.
class Outcome {
  const Outcome(this.schedule, this.interval);
  final Schedule schedule;
  final Duration interval;
}

/// Enveloppe autour de la bibliothèque FSRS.
///
/// Le « fuzzing » (petit hasard sur les intervalles) est désactivé : ainsi le
/// délai affiché sous chaque bouton est exactement celui qui sera appliqué.
class SchedulingService {
  final Map<double, fsrs.Scheduler> _cache = {};

  fsrs.Scheduler _scheduler(double retention) => _cache.putIfAbsent(
    retention,
    () => fsrs.Scheduler(desiredRetention: retention, enableFuzzing: false),
  );

  fsrs.Card _toCard(int id, Schedule s, DateTime now) {
    if (s.isNew) {
      return fsrs.Card(
        cardId: id,
        state: fsrs.State.learning,
        step: 0,
        due: now,
      );
    }
    return fsrs.Card(
      cardId: id,
      state: fsrs.State.fromValue(s.state),
      step: s.state == CardState.review ? null : (s.step ?? 0),
      stability: s.stability,
      difficulty: s.difficulty,
      due: DateTime.fromMillisecondsSinceEpoch(s.dueMs, isUtc: true),
      lastReview: s.lastReviewMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(s.lastReviewMs!, isUtc: true),
    );
  }

  /// Applique une réponse à une carte.
  Outcome answer(
    int cardId,
    Schedule current,
    Grade grade,
    DateTime now, {
    required double retention,
  }) {
    final nowUtc = now.toUtc();
    final result = _scheduler(retention).reviewCard(
      _toCard(cardId, current, nowUtc),
      grade._rating,
      reviewDateTime: nowUtc,
    );
    final c = result.card;
    final lapsed = current.state == CardState.review && grade == Grade.again;
    return Outcome(
      Schedule(
        state: c.state.value,
        step: c.step,
        stability: c.stability,
        difficulty: c.difficulty,
        dueMs: c.due.millisecondsSinceEpoch,
        lastReviewMs: nowUtc.millisecondsSinceEpoch,
        reps: current.reps + 1,
        lapses: current.lapses + (lapsed ? 1 : 0),
      ),
      c.due.difference(nowUtc),
    );
  }

  /// Délai qui suivrait chacune des quatre réponses.
  Map<Grade, Duration> preview(
    int cardId,
    Schedule current,
    DateTime now, {
    required double retention,
  }) => {
    for (final g in Grade.values)
      g: answer(cardId, current, g, now, retention: retention).interval,
  };

  /// Probabilité de se souvenir de la carte à l'instant [now] (0 à 1).
  double retrievability(Schedule s, DateTime now) {
    if (s.isNew || s.lastReviewMs == null || s.stability == null) return 0;
    return _scheduler(0.9).getCardRetrievability(
      _toCard(0, s, now.toUtc()),
      currentDateTime: now.toUtc(),
    );
  }

  /// Jours cumulés (J+n) des premières révisions réussies d'une carte neuve
  /// quand on répond « Bien » à chaque échéance, pour un objectif de rétention
  /// donné. Sert à afficher les jalons du curseur d'exigence et à construire
  /// la séquence « Espacée » de la méthode des J.
  List<int> milestones(double retention, {int count = 4}) {
    final start = DateTime.utc(2030, 1, 1, 8);
    var now = start;
    var sched = Schedule.fresh(start.millisecondsSinceEpoch);
    final out = <int>[];
    var guard = 0;
    while (out.length < count && guard++ < 50) {
      final o = answer(1, sched, Grade.good, now, retention: retention);
      sched = o.schedule;
      now = DateTime.fromMillisecondsSinceEpoch(sched.dueMs, isUtc: true);
      if (sched.state == CardState.review) {
        out.add(now.difference(start).inDays);
      }
    }
    return out;
  }

  /// Nombre de jours distincts où une carte neuve, toujours répondue « Bien »,
  /// est révisée pendant [days] jours (sert à estimer la charge quotidienne :
  /// n nouvelles cartes par jour reviennent à n × ce nombre de révisions par
  /// jour une fois le rythme installé).
  int reviewDaysWithin(double retention, {int days = 365}) {
    final start = DateTime.utc(2030, 1, 1, 8);
    var now = start;
    var sched = Schedule.fresh(start.millisecondsSinceEpoch);
    final seen = <int>{};
    var guard = 0;
    while (guard++ < 100) {
      final d = now.difference(start).inDays;
      if (d > days) break;
      seen.add(d);
      sched = answer(1, sched, Grade.good, now, retention: retention).schedule;
      now = DateTime.fromMillisecondsSinceEpoch(sched.dueMs, isUtc: true);
    }
    return seen.length;
  }
}
