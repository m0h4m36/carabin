import '../../data/flashcards_repository.dart';
import '../../domain/scheduling.dart';
import '../../domain/study_options.dart';

/// D'où vient la carte affichée.
enum _Source { queue, learning }

class _Learning {
  _Learning(this.cardId, this.dueMs);
  final int cardId;
  int dueMs;
}

class _Done {
  _Done(this.token, this.durationMs);
  final UndoToken token;
  final int durationMs;
}

/// Déroulé d'une séance de révision : quelle carte vient ensuite, quand
/// reviennent les cartes en apprentissage, comment annuler.
///
/// Les cartes sont servies dans cet ordre : une carte en apprentissage dont
/// l'heure est venue passe d'abord ; sinon la suivante de la file (révisions
/// puis nouvelles) ; sinon, s'il ne reste que des cartes en apprentissage
/// proches, on les présente sans attendre.
class ReviewSession {
  ReviewSession(
    this.repo, {
    List<int>? deckIds,
    List<int>? cardIds,
    StudyOrder? order,
  }) {
    final queue = cardIds ?? repo.todayQueue(deckIds: deckIds, order: order);
    _queue.addAll(queue);
    if (cardIds == null) {
      for (final id in repo.learningDue(deckIds: deckIds, ahead: learnAhead)) {
        _learning.add(_Learning(id, repo.card(id).schedule.dueMs));
      }
    }
    _newIds.addAll([
      for (final id in _queue)
        if (repo.card(id).schedule.isNew) id,
    ]);
    initialTotal = _queue.length + _learning.length;
    _advance();
  }

  final FlashcardsRepository repo;
  final List<int> _queue = [];
  final List<_Learning> _learning = [];
  final Set<int> _newIds = {};
  final Set<int> _shown = {};
  final List<_Done> _history = [];

  /// Nombre de cartes à passer au départ.
  late final int initialTotal;

  int? _current;
  _Source _source = _Source.queue;
  int _answered = 0;
  int _totalMs = 0;

  /// Carte affichée, ou null quand la séance est terminée.
  int? get current => _current;
  bool get finished => _current == null;

  /// Nombre de réponses données (annulations déduites).
  int get answered => _answered;

  /// Rang de la carte affichée parmi les cartes distinctes déjà présentées.
  int get position => _shown.length;

  /// Durée cumulée des réponses.
  Duration get spent => Duration(milliseconds: _totalMs);

  bool get canUndo => _history.isNotEmpty;

  /// Pastilles : nouvelles / en apprentissage / à revoir restantes
  /// (la carte affichée comprise).
  ({int fresh, int learning, int review}) get pills {
    var fresh = 0;
    var review = 0;
    for (final id in _queue) {
      _newIds.contains(id) ? fresh++ : review++;
    }
    var learning = _learning.length;
    final c = _current;
    if (c != null && _source == _Source.queue) {
      if (_newIds.contains(c)) {
        fresh++;
      } else if (_isLearningNow(c)) {
        learning++;
      } else {
        review++;
      }
    }
    return (fresh: fresh, learning: learning, review: review);
  }

  bool _isLearningNow(int id) {
    final st = repo.card(id).schedule.state;
    return st == CardState.learning || st == CardState.relearning;
  }

  /// Catégorie de la carte affichée.
  ({bool fresh, bool learning, bool review})? get currentKind {
    final c = _current;
    if (c == null) return null;
    final st = repo.card(c).schedule.state;
    return (
      fresh: st == CardState.newCard,
      learning: st == CardState.learning || st == CardState.relearning,
      review: st == CardState.review,
    );
  }

  int get remaining => _queue.length + _learning.length + (_current != null && _source == _Source.queue ? 1 : 0);

  /// Les quatre délais de la carte affichée.
  Map<Grade, Duration> get preview => repo.preview(_current!);

  // --------------------------------------------------------------- suite

  void _advance() {
    final nowMs = repo.now().toUtc().millisecondsSinceEpoch;
    _learning.sort((a, b) => a.dueMs.compareTo(b.dueMs));
    if (_learning.isNotEmpty && _learning.first.dueMs <= nowMs) {
      _current = _learning.first.cardId;
      _source = _Source.learning;
    } else if (_queue.isNotEmpty) {
      _current = _queue.removeAt(0);
      _source = _Source.queue;
    } else if (_learning.isNotEmpty) {
      _current = _learning.first.cardId;
      _source = _Source.learning;
    } else {
      _current = null;
    }
    if (_current != null) _shown.add(_current!);
  }

  void _dropLearning(int cardId) => _learning.removeWhere((l) => l.cardId == cardId);

  /// Remet la carte affichée en tête de sa source avant d'en afficher une autre.
  void _putBackCurrent() {
    final c = _current;
    if (c == null) return;
    if (_source == _Source.queue) _queue.insert(0, c);
    _current = null;
  }

  /// Donne la réponse [grade] à la carte affichée.
  AnswerResult answer(Grade grade, {int? durationMs}) {
    final id = _current!;
    final capped = durationMs?.clamp(0, 10 * 60 * 1000).toInt();
    final result = repo.answer(id, grade, durationMs: capped);
    _dropLearning(id);
    final s = result.schedule;
    final inLearning = s.state == CardState.learning || s.state == CardState.relearning;
    final soon = s.dueMs <= repo.now().toUtc().millisecondsSinceEpoch + learnAhead.inMilliseconds;
    if (inLearning && soon) _learning.add(_Learning(id, s.dueMs));
    _history.add(_Done(result.undo, capped ?? 0));
    _answered++;
    _totalMs += capped ?? 0;
    if (result.becameLeech) {
      // une carte maudite mise de côté ne revient pas dans la séance
      _dropLearning(id);
    }
    _advance();
    return result;
  }

  /// Annule la dernière réponse : la carte revient en tête.
  bool undo() {
    if (_history.isEmpty) return false;
    final last = _history.removeLast();
    repo.undo(last.token);
    _putBackCurrent();
    final id = last.token.cardId;
    _dropLearning(id);
    _current = id;
    _source = _Source.queue; // si on revient plus loin en arrière, elle repart en tête de file
    _shown.add(id);
    _answered--;
    _totalMs -= last.durationMs;
    return true;
  }

  // -------------------------------------------------- actions sur la carte

  void _removeNote(int noteId) {
    bool same(int id) => repo.card(id).noteId == noteId;
    _queue.removeWhere(same);
    _learning.removeWhere((l) => same(l.cardId));
  }

  /// Met la carte affichée de côté (suspendue).
  void suspendCurrent() {
    final id = _current!;
    repo.setCardSuspended(id, true);
    _dropLearning(id);
    _advance();
  }

  /// Enterre la notion de la carte affichée jusqu'au prochain jour d'étude.
  void buryCurrent() {
    final id = _current!;
    final noteId = repo.card(id).noteId;
    repo.buryNote(noteId);
    _dropLearning(id);
    _removeNote(noteId);
    _advance();
  }

  /// Supprime définitivement la notion de la carte affichée.
  void deleteCurrent() {
    final id = _current!;
    final noteId = repo.card(id).noteId;
    _history.removeWhere((h) => repo.cardsOfNote(noteId).any((c) => c.id == h.token.cardId));
    _dropLearning(id);
    _removeNote(noteId);
    repo.deleteNote(noteId);
    _advance();
  }
}
