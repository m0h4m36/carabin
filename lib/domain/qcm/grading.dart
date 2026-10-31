/// Réponses des étudiants et barème (EDN ou « Points »).
library;

import 'question.dart';
import 'text_match.dart';

/// Barème appliqué à une copie.
enum Scoring {
  /// Règles nationales des EDN (voir [gradeQuestion]).
  edn,

  /// Points proportionnels : chaque proposition bien traitée compte.
  points,
}

/// Sort d'une question dans une copie.
enum Verdict {
  right,
  partial,
  wrong,

  /// Question passée ou jamais ouverte.
  skipped,

  /// QROC sans éléments attendus : l'étudiant ne s'est pas encore évalué.
  pending,
}

/// Réponse d'un étudiant à une question.
sealed class Answer {
  const Answer();

  Map<String, Object?> toJson();

  /// Lit une réponse enregistrée pour une question du genre [kind] ; null si
  /// elle est illisible.
  static Answer? fromJson(QuestionKind kind, Object? j) {
    if (j is! Map) return null;
    switch (kind) {
      case QuestionKind.qcm:
      case QuestionKind.qrp:
        final t = j['ticked'];
        if (t is! List) return null;
        return ChoiceAnswer({
          for (final i in t)
            if (i is int && i >= 0) i,
        });
      case QuestionKind.qroc:
        final text = j['text'];
        if (text is! String) return null;
        final self = j['self'];
        return TextAnswer(text, self: self is num ? self.toDouble() : null);
      case QuestionKind.tcs:
        final level = j['level'];
        if (level is! int || level < -2 || level > 2) return null;
        return TcsAnswer(level);
      case QuestionKind.qzp:
        final x = j['x'], y = j['y'];
        if (x is! num || y is! num) return null;
        return PointAnswer(x.toDouble(), y.toDouble());
    }
  }
}

/// Propositions cochées (positions dans la liste de la question).
class ChoiceAnswer extends Answer {
  const ChoiceAnswer(this.ticked);
  final Set<int> ticked;

  @override
  Map<String, Object?> toJson() => {'ticked': (ticked.toList()..sort())};
}

/// Texte écrit, avec l'auto-évaluation (0, 0,5 ou 1) quand le QROC n'a pas
/// d'éléments attendus.
class TextAnswer extends Answer {
  const TextAnswer(this.text, {this.self});
  final String text;
  final double? self;

  TextAnswer withSelf(double? self) => TextAnswer(text, self: self);

  @override
  Map<String, Object?> toJson() => {
    'text': text,
    if (self != null) 'self': self,
  };
}

/// Niveau choisi sur l'échelle, de −2 à +2.
class TcsAnswer extends Answer {
  const TcsAnswer(this.level);
  final int level;

  @override
  Map<String, Object?> toJson() => {'level': level};
}

/// Point touché sur l'image, en fractions de sa largeur / hauteur.
class PointAnswer extends Answer {
  const PointAnswer(this.x, this.y);
  final double x;
  final double y;

  @override
  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

/// Note d'une question.
class Grade {
  const Grade(this.score, this.max, this.verdict);

  final double score;
  final double max;
  final Verdict verdict;

  @override
  String toString() => 'Grade($score/$max, $verdict)';
}

double _round(double v) => (v * 1e6).round() / 1e6;

Grade _fromFactor(double factor, double max) {
  final f = factor.clamp(0.0, 1.0);
  final verdict = f >= 1 - 1e-9
      ? Verdict.right
      : f <= 1e-9
      ? Verdict.wrong
      : Verdict.partial;
  return Grade(_round(max * f), max, verdict);
}

/// Note de [answer] à [question]. Une réponse absente (ou d'un genre qui ne
/// correspond pas à la question) donne une question passée.
///
/// Barème EDN pour les propositions :
/// - QRU : tout ou rien ;
/// - QRM : 1 sans discordance, 0,5 pour une, 0,2 pour deux, 0 au-delà (une
///   discordance est une proposition cochée à tort ou oubliée) ;
/// - QRP : bonnes réponses cochées sur réponses attendues ;
/// - annulation : une proposition indispensable oubliée ou une proposition
///   inacceptable cochée donne 0.
///
/// Barème « Points » : QRU tout ou rien ; QRM, part des propositions bien
/// traitées (cochée à raison ou laissée à raison) ; QRP comme en EDN, sans
/// annulation.
Grade gradeQuestion(Question question, Answer? answer, Scoring scoring) {
  final max = question.points;
  final skipped = Grade(0, max, Verdict.skipped);
  if (answer == null) return skipped;
  switch (question) {
    case ChoiceQuestion q:
      if (answer is! ChoiceAnswer) return skipped;
      return _fromFactor(_choiceFactor(q, answer.ticked, scoring), max);
    case QrocQuestion q:
      if (answer is! TextAnswer) return skipped;
      if (q.autoGraded) {
        return _fromFactor(_qrocFactor(q, answer.text), max);
      }
      final self = answer.self;
      if (self == null) return Grade(0, max, Verdict.pending);
      return _fromFactor(self, max);
    case TcsQuestion q:
      if (answer is! TcsAnswer) return skipped;
      final top = q.panelMax;
      if (top == 0) return _fromFactor(0, max);
      return _fromFactor(q.panel[answer.level + 2] / top, max);
    case QzpQuestion q:
      if (answer is! PointAnswer) return skipped;
      final hit = q.zones.any((z) => z.contains(answer.x, answer.y));
      return _fromFactor(hit ? 1 : 0, max);
  }
}

double _choiceFactor(ChoiceQuestion q, Set<int> rawTicked, Scoring scoring) {
  final props = q.propositions;
  final ticked = {
    for (final i in rawTicked)
      if (i >= 0 && i < props.length) i,
  };
  final correct = {
    for (var i = 0; i < props.length; i++)
      if (props[i].correct) i,
  };
  if (correct.isEmpty) return 0;
  final right = ticked.intersection(correct).length;
  final wrongTicks = ticked.length - right;
  final missed = correct.length - right;

  if (q.pointed) {
    if (scoring == Scoring.edn && _cancelled(props, ticked)) return 0;
    return right / correct.length;
  }
  if (q.shape == ChoiceShape.qru) {
    return wrongTicks == 0 && missed == 0 ? 1 : 0;
  }
  final discordances = wrongTicks + missed;
  switch (scoring) {
    case Scoring.edn:
      if (_cancelled(props, ticked)) return 0;
      return switch (discordances) {
        0 => 1,
        1 => 0.5,
        2 => 0.2,
        _ => 0,
      };
    case Scoring.points:
      return (props.length - discordances) / props.length;
  }
}

/// Annulation : une bonne réponse indispensable oubliée ou une mauvaise
/// réponse inacceptable cochée.
bool _cancelled(List<Proposition> props, Set<int> ticked) {
  for (var i = 0; i < props.length; i++) {
    final p = props[i];
    if (!p.critical) continue;
    if (p.correct && !ticked.contains(i)) return true;
    if (!p.correct && ticked.contains(i)) return true;
  }
  return false;
}

/// Éléments attendus trouvés dans [text] (même ordre que
/// `question.usableElements`).
List<bool> qrocHits(QrocQuestion question, String text) => [
  for (final e in question.usableElements) elementMatches(e.pattern, text),
];

double _qrocFactor(QrocQuestion q, String text) {
  final elements = q.usableElements;
  final total = elements.fold<double>(0, (a, e) => a + e.points);
  if (total <= 0) return 0;
  var earned = 0.0;
  for (final e in elements) {
    if (elementMatches(e.pattern, text)) earned += e.points;
  }
  return earned / total;
}

/// Total d'une copie.
class Totals {
  const Totals({
    required this.score,
    required this.max,
    required this.right,
    required this.partial,
    required this.wrong,
    required this.skipped,
    required this.pending,
  });

  factory Totals.of(Iterable<Grade> grades) {
    var score = 0.0, max = 0.0;
    var right = 0, partial = 0, wrong = 0, skipped = 0, pending = 0;
    for (final g in grades) {
      score += g.score;
      max += g.max;
      switch (g.verdict) {
        case Verdict.right:
          right++;
        case Verdict.partial:
          partial++;
        case Verdict.wrong:
          wrong++;
        case Verdict.skipped:
          skipped++;
        case Verdict.pending:
          pending++;
      }
    }
    return Totals(
      score: _round(score),
      max: _round(max),
      right: right,
      partial: partial,
      wrong: wrong,
      skipped: skipped,
      pending: pending,
    );
  }

  final double score;
  final double max;
  final int right;
  final int partial;
  final int wrong;
  final int skipped;
  final int pending;

  int get count => right + partial + wrong + skipped + pending;

  /// Note sur 20 (0 si l'épreuve ne vaut aucun point).
  double get outOf20 => max <= 0 ? 0 : _round(score / max * 20);

  /// Part des points obtenus, de 0 à 1.
  double get ratio => max <= 0 ? 0 : score / max;
}
