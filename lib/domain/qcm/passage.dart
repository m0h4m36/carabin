/// Déroulé d'un passage : quelle question est ouverte, lesquelles sont
/// validées ou passées, et ce qui est permis.
library;

import 'exam.dart';
import 'grading.dart';

/// État d'une question pendant le passage.
enum QStatus { fresh, skipped, validated }

class Passage {
  Passage(this.plan, this.settings, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      status = List.filled(plan.length, QStatus.fresh),
      answers = List.filled(plan.length, null),
      doubt = List.filled(plan.length, false),
      seen = List.filled(plan.length, false),
      _drafts = List.filled(plan.length, null) {
    startedAt = _clock();
    if (plan.isNotEmpty) seen[0] = true;
  }

  final List<PlannedQuestion> plan;
  final PassageSettings settings;
  final DateTime Function() _clock;
  late final DateTime startedAt;
  DateTime? endedAt;

  /// Fin due au minuteur.
  bool timedOut = false;

  int current = 0;
  final List<QStatus> status;

  /// Dernière réponse validée de chaque question.
  final List<Answer?> answers;
  final List<bool> doubt;
  final List<bool> seen;
  final List<Answer?> _drafts;

  int get count => plan.length;
  bool get finished => endedAt != null;

  int get validatedCount => status.where((s) => s == QStatus.validated).length;
  int get skippedCount => status.where((s) => s == QStatus.skipped).length;

  /// Réponse en cours de saisie (non validée).
  Answer? draft(int i) => _drafts[i];
  void setDraft(int i, Answer? a) => _drafts[i] = a;

  // ---------------------------------------------------------- navigation

  /// Dernière question du même dossier progressif avant [i], ou null.
  int? _previousInCase(int i) {
    final g = plan[i].caseGroup;
    if (g < 0 || plan[i].info?.genre != CaseGenre.progressive) return null;
    return i > 0 && plan[i - 1].caseGroup == g ? i - 1 : null;
  }

  int? _nextInCase(int i) {
    final g = plan[i].caseGroup;
    if (g < 0 || plan[i].info?.genre != CaseGenre.progressive) return null;
    return i + 1 < count && plan[i + 1].caseGroup == g ? i + 1 : null;
  }

  /// Une question d'un dossier progressif ne se rouvre plus quand la suivante
  /// a été vue.
  bool _storyMovedOn(int i) {
    final next = _nextInCase(i);
    return next != null && seen[next];
  }

  bool canOpen(int i) {
    if (finished || i < 0 || i >= count) return false;
    if (i == current) return true;
    final before = _previousInCase(i);
    if (before != null && !seen[before]) return false;
    if (_storyMovedOn(i)) return false;
    if (status[i] == QStatus.validated) return settings.backAllowed;
    return true;
  }

  void open(int i) {
    if (!canOpen(i)) throw StateError('question $i inaccessible');
    current = i;
    seen[i] = true;
  }

  /// Vrai si la réponse de la question [i] peut encore être (re)donnée.
  bool canEdit(int i) {
    if (finished || i < 0 || i >= count) return false;
    if (status[i] != QStatus.validated) return true;
    return settings.correction == Correction.end &&
        settings.backAllowed &&
        !_storyMovedOn(i);
  }

  // -------------------------------------------------------------- actions

  void validate(Answer answer) {
    if (!canEdit(current)) throw StateError('question déjà validée');
    answers[current] = answer;
    status[current] = QStatus.validated;
    _drafts[current] = null;
  }

  void skip() {
    if (!canEdit(current)) throw StateError('question déjà validée');
    if (status[current] == QStatus.fresh) status[current] = QStatus.skipped;
  }

  void toggleDoubt([int? i]) {
    final k = i ?? current;
    doubt[k] = !doubt[k];
  }

  /// Prochaine question à traiter après la courante : la première jamais
  /// traitée après elle, sinon la première jamais traitée avant. Null s'il
  /// n'en reste aucune (la copie peut être rendue).
  int? nextTarget() {
    for (var j = current + 1; j < count; j++) {
      if (status[j] == QStatus.fresh && canOpen(j)) return j;
    }
    for (var j = 0; j < current; j++) {
      if (status[j] == QStatus.fresh && canOpen(j)) return j;
    }
    return null;
  }

  /// Passe à la question suivante ; rend la copie s'il n'en reste aucune.
  void advance() {
    final t = nextTarget();
    if (t == null) {
      finish();
    } else {
      open(t);
    }
  }

  // ---------------------------------------------------------------- temps

  Duration? get limit => settings.timerMinutes == null
      ? null
      : Duration(minutes: settings.timerMinutes!);

  Duration elapsed() => (endedAt ?? _clock()).difference(startedAt);

  /// Temps restant, ou null sans minuteur.
  Duration? remaining() {
    final l = limit;
    if (l == null) return null;
    final left = l - elapsed();
    return left.isNegative ? Duration.zero : left;
  }

  /// Rend la copie.
  void finish() {
    if (finished) return;
    endedAt = _clock();
  }

  /// Le temps est écoulé : la copie est rendue telle quelle.
  void expire() {
    if (finished) return;
    timedOut = true;
    endedAt = startedAt.add(limit ?? Duration.zero);
  }

  /// Durée comptée dans la copie (plafonnée par le minuteur).
  Duration get duration {
    final d = elapsed();
    final l = limit;
    return l != null && d > l ? l : d;
  }

  // ----------------------------------------------------------------- note

  Grade gradeOf(int i) {
    final a = status[i] == QStatus.validated ? answers[i] : null;
    return gradeQuestion(plan[i].question, a, settings.scoring);
  }

  List<Grade> grades() => [for (var i = 0; i < count; i++) gradeOf(i)];

  Totals totals() => Totals.of(grades());
}
