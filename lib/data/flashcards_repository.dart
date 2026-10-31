import 'dart:math';

import '../domain/note_types.dart';
import '../domain/scheduling.dart';
import '../domain/study_options.dart';
import 'database.dart';
import 'errors.dart';
import 'flashcard_models.dart';
import 'names.dart';
import 'settings_repository.dart';

/// Fenêtre dans laquelle une carte en apprentissage est déjà présentée.
const Duration learnAhead = Duration(minutes: 20);

/// Heure à laquelle un « jour d'étude » change (réviser après minuit compte
/// encore pour la veille).
const int studyDayRolloverHour = 4;

/// Début (heure locale) du jour d'étude qui contient [now].
DateTime studyDayStart(DateTime now) {
  final local = now.toLocal();
  final base = DateTime(
    local.year,
    local.month,
    local.day,
    studyDayRolloverHour,
  );
  return local.isBefore(base)
      ? DateTime(base.year, base.month, base.day - 1, studyDayRolloverHour)
      : base;
}

DateTime studyDayEnd(DateTime now) {
  final s = studyDayStart(now);
  return DateTime(s.year, s.month, s.day + 1, studyDayRolloverHour);
}

/// Annulation d'une réponse.
class UndoToken {
  const UndoToken._(
    this.cardId,
    this.previous,
    this.logId,
    this.previousBuried,
  );
  final int cardId;
  final CardRow previous;
  final int logId;
  final int? previousBuried;
}

class AnswerResult {
  const AnswerResult(this.undo, this.schedule, this.interval, this.becameLeech);
  final UndoToken undo;
  final Schedule schedule;
  final Duration interval;
  final bool becameLeech;
}

class RetentionStats {
  const RetentionStats(this.recalled, this.total);
  final int recalled;
  final int total;
  double? get rate => total == 0 ? null : recalled / total;
}

class StockStats {
  const StockStats({
    required this.fresh,
    required this.learning,
    required this.young,
    required this.mature,
  });
  final int fresh;
  final int learning;
  final int young;
  final int mature;
  int get total => fresh + learning + young + mature;
}

/// Paquets, notes, cartes, révision.
class FlashcardsRepository {
  FlashcardsRepository(
    this.db,
    this.settings, {
    DateTime Function()? clock,
    SchedulingService? scheduling,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       scheduling = scheduling ?? SchedulingService(),
       _random = random ?? Random();

  final AppDatabase db;
  final SettingsRepository settings;
  final SchedulingService scheduling;
  final DateTime Function() _clock;
  final Random _random;

  static const globalOptionsKey = 'etude.reglages';

  DateTime now() => _clock();
  int _nowMs() => _clock().toUtc().millisecondsSinceEpoch;

  // ------------------------------------------------------------- réglages

  StudyOptions globalOptions() =>
      StudyOptions.fromJson(settings.get(globalOptionsKey));

  void setGlobalOptions(StudyOptions o) =>
      settings.set(globalOptionsKey, o.toJson());

  /// Réglages propres au paquet, ou null s'il suit les réglages généraux.
  StudyOptions? deckOptions(int deckId) {
    final rows = db.select('SELECT options_json FROM decks WHERE id = ?', [
      deckId,
    ]);
    if (rows.isEmpty) throw const NotFoundError();
    final json = rows.first['options_json'] as String?;
    return json == null ? null : StudyOptions.fromJson(json);
  }

  void setDeckOptions(int deckId, StudyOptions? o) {
    db.transaction(() {
      db.execute('UPDATE decks SET options_json = ? WHERE id = ?', [
        o?.toJson(),
        deckId,
      ]);
    });
  }

  StudyOptions effectiveOptions(int deckId) =>
      deckOptions(deckId) ?? globalOptions();

  // --------------------------------------------------------------- paquets

  String _cleanName(String raw) {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const EmptyNameError();
    return name;
  }

  void _checkDeckName(String name, int? subjectId, {int? exceptId}) {
    final rows = subjectId == null
        ? db.select('SELECT id, name FROM decks WHERE subject_id IS NULL')
        : db.select('SELECT id, name FROM decks WHERE subject_id = ?', [
            subjectId,
          ]);
    for (final r in rows) {
      if (r['id'] == exceptId) continue;
      if (normalize(r['name'] as String) == normalize(name)) {
        throw NameTakenError(name);
      }
    }
  }

  List<Deck> decks() => [
    for (final r in db.select('SELECT * FROM decks ORDER BY position, id'))
      Deck.fromRow(r),
  ];

  Deck deck(int id) {
    final rows = db.select('SELECT * FROM decks WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return Deck.fromRow(rows.first);
  }

  Deck createDeck(String rawName, {int? subjectId, int? documentId}) {
    final name = _cleanName(rawName);
    _checkDeckName(name, subjectId);
    final id = db.transaction(() {
      final pos =
          db
                  .select(
                    'SELECT COALESCE(MAX(position), -1) + 1 AS n FROM decks',
                  )
                  .first['n']
              as int;
      db.execute(
        'INSERT INTO decks(name, subject_id, document_id, position, created_at) VALUES (?, ?, ?, ?, ?)',
        [name, subjectId, documentId, pos, _nowMs()],
      );
      return db.lastInsertId;
    });
    return deck(id);
  }

  void renameDeck(int id, String rawName) {
    final name = _cleanName(rawName);
    final d = deck(id);
    _checkDeckName(name, d.subjectId, exceptId: id);
    db.transaction(
      () => db.execute('UPDATE decks SET name = ? WHERE id = ?', [name, id]),
    );
  }

  void setDeckSubject(int id, int? subjectId) {
    final d = deck(id);
    _checkDeckName(d.name, subjectId, exceptId: id);
    db.transaction(
      () => db.execute('UPDATE decks SET subject_id = ? WHERE id = ?', [
        subjectId,
        id,
      ]),
    );
  }

  void setDeckDocument(int id, int? documentId) {
    db.transaction(
      () => db.execute('UPDATE decks SET document_id = ? WHERE id = ?', [
        documentId,
        id,
      ]),
    );
  }

  void deleteDeck(int id) {
    db.transaction(() => db.execute('DELETE FROM decks WHERE id = ?', [id]));
  }

  // ----------------------------------------------------------------- notes

  List<NoteRow> notes(int deckId, {String query = ''}) {
    final rows = db.select(
      'SELECT n.*, COUNT(c.id) AS card_count, '
      'COALESCE(SUM(c.suspended), 0) AS suspended_count '
      'FROM notes n LEFT JOIN cards c ON c.note_id = n.id '
      'WHERE n.deck_id = ? GROUP BY n.id ORDER BY n.id',
      [deckId],
    );
    final all = [for (final r in rows) NoteRow.fromRow(r)];
    final q = normalize(query.trim());
    if (q.isEmpty) return all;
    return [
      for (final n in all)
        if (normalize(n.preview).contains(q) ||
            normalize(n.tags.join(' ')).contains(q))
          n,
    ];
  }

  NoteRow note(int id) {
    final rows = db.select(
      'SELECT n.*, COUNT(c.id) AS card_count, '
      'COALESCE(SUM(c.suspended), 0) AS suspended_count '
      'FROM notes n LEFT JOIN cards c ON c.note_id = n.id WHERE n.id = ? GROUP BY n.id',
      [id],
    );
    if (rows.isEmpty) throw const NotFoundError();
    return NoteRow.fromRow(rows.first);
  }

  /// Nombre de notes d'un paquet qui contiennent déjà ce texte (pour
  /// signaler un doublon à l'utilisateur).
  bool hasDuplicate(
    int deckId,
    NoteType type,
    NoteFields fields, {
    int? exceptId,
  }) {
    final key = duplicateKey(type, fields);
    for (final n in notes(deckId)) {
      if (n.id != exceptId &&
          n.type == type &&
          duplicateKey(n.type, n.fields) == key) {
        return true;
      }
    }
    return false;
  }

  static final _secure = Random.secure();

  /// Identifiant aléatoire de 128 bits, en hexadécimal.
  static String newGuid() => [
    for (var i = 0; i < 16; i++)
      _secure.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// Étiquettes normalisées (sans doublon ni espace), séparées par des espaces.
  String joinTags(List<String> tags) => {
    for (final t in tags)
      if (t.trim().isNotEmpty) t.trim().replaceAll(RegExp(r'\s+'), '_'),
  }.join(' ');

  /// Ajoute une note et fabrique ses cartes (neuves).
  NoteRow addNote(
    int deckId,
    NoteType type,
    NoteFields fields, {
    List<String> tags = const [],
    int? documentId,
  }) {
    deck(deckId);
    final issue = validateNote(type, fields);
    if (issue != null) throw InvalidNoteError(issue);
    final nowMs = _nowMs();
    final id = db.transaction(() {
      db.execute(
        'INSERT INTO notes(guid, deck_id, type, fields_json, tags, document_id, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          newGuid(),
          deckId,
          type.name,
          fields.toJson(),
          joinTags(tags),
          documentId,
          nowMs,
          nowMs,
        ],
      );
      final noteId = db.lastInsertId;
      for (final ord in cardOrdinals(type, fields)) {
        _insertCard(noteId, ord, nowMs);
      }
      return noteId;
    });
    return note(id);
  }

  void _insertCard(int noteId, int ord, int nowMs) {
    db.execute(
      'INSERT INTO cards(note_id, ord, state, due) VALUES (?, ?, 0, ?)',
      [noteId, ord, nowMs],
    );
  }

  /// Modifie les champs d'une note. Les cartes dont le numéro subsiste gardent
  /// leur historique ; les nouvelles sont créées neuves ; celles qui n'ont plus
  /// lieu d'être (un trou supprimé) sont effacées.
  void updateNote(int noteId, NoteFields fields, {List<String>? tags}) {
    final n = note(noteId);
    final issue = validateNote(n.type, fields);
    if (issue != null) throw InvalidNoteError(issue);
    final wanted = cardOrdinals(n.type, fields).toSet();
    final nowMs = _nowMs();
    db.transaction(() {
      db.execute(
        'UPDATE notes SET fields_json = ?, tags = ?, updated_at = ? WHERE id = ?',
        [
          fields.toJson(),
          tags == null ? joinTags(n.tags) : joinTags(tags),
          nowMs,
          noteId,
        ],
      );
      final existing = {
        for (final r in db.select('SELECT ord FROM cards WHERE note_id = ?', [
          noteId,
        ]))
          r['ord'] as int,
      };
      for (final ord in existing.difference(wanted)) {
        db.execute('DELETE FROM cards WHERE note_id = ? AND ord = ?', [
          noteId,
          ord,
        ]);
      }
      for (final ord in wanted.difference(existing)) {
        _insertCard(noteId, ord, nowMs);
      }
    });
  }

  void deleteNote(int noteId) {
    db.transaction(
      () => db.execute('DELETE FROM notes WHERE id = ?', [noteId]),
    );
  }

  void moveNote(int noteId, int deckId) {
    deck(deckId);
    db.transaction(
      () => db.execute('UPDATE notes SET deck_id = ? WHERE id = ?', [
        deckId,
        noteId,
      ]),
    );
  }

  // ----------------------------------------------------------------- cartes

  List<CardRow> cardsOfNote(int noteId) => [
    for (final r in db.select(
      'SELECT * FROM cards WHERE note_id = ? ORDER BY ord',
      [noteId],
    ))
      CardRow.fromRow(r),
  ];

  CardRow card(int id) {
    final rows = db.select('SELECT * FROM cards WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return CardRow.fromRow(rows.first);
  }

  StudyCard studyCard(int cardId) {
    final c = card(cardId);
    return StudyCard(c, note(c.noteId));
  }

  /// Met en pause (ou rétablit) toutes les cartes d'une notion.
  void setNoteSuspended(int noteId, bool suspended) {
    db.transaction(() {
      db.execute('UPDATE cards SET suspended = ? WHERE note_id = ?', [
        suspended ? 1 : 0,
        noteId,
      ]);
    });
  }

  void setCardSuspended(int cardId, bool suspended) {
    db.transaction(() {
      db.execute('UPDATE cards SET suspended = ? WHERE id = ?', [
        suspended ? 1 : 0,
        cardId,
      ]);
    });
  }

  /// Enterre une notion : toutes ses cartes reviennent au prochain jour d'étude.
  void buryNote(int noteId) {
    final until = studyDayEnd(_clock()).toUtc().millisecondsSinceEpoch;
    db.transaction(() {
      db.execute('UPDATE cards SET buried_until = ? WHERE note_id = ?', [
        until,
        noteId,
      ]);
    });
  }

  // ------------------------------------------------------------- la file

  /// Carte d'un paquet donné ? (null = tous les paquets)
  String _deckFilter(List<int>? deckIds, List<Object?> params) {
    if (deckIds == null) return '';
    if (deckIds.isEmpty) return ' AND 0';
    params.addAll(deckIds);
    return ' AND n.deck_id IN (${List.filled(deckIds.length, '?').join(',')})';
  }

  int _countLogs(String where, List<Object?> params) =>
      db
              .select(
                'SELECT COUNT(*) AS n FROM review_logs l JOIN cards c ON c.id = l.card_id '
                'JOIN notes n ON n.id = c.note_id WHERE $where',
                params,
              )
              .first['n']
          as int;

  int newDoneToday(int deckId) => _countLogs(
    'n.deck_id = ? AND l.state_before = 0 AND l.reviewed_at >= ?',
    [deckId, studyDayStart(_clock()).toUtc().millisecondsSinceEpoch],
  );

  int reviewsDoneToday(int deckId) => _countLogs(
    'n.deck_id = ? AND l.state_before = 2 AND l.reviewed_at >= ?',
    [deckId, studyDayStart(_clock()).toUtc().millisecondsSinceEpoch],
  );

  /// Identifiants des notes déjà révisées aujourd'hui (règle « une carte par
  /// notion et par jour »).
  Set<int> _notesStudiedToday() => {
    for (final r in db.select(
      'SELECT DISTINCT c.note_id AS id FROM review_logs l JOIN cards c ON c.id = l.card_id '
      'WHERE l.reviewed_at >= ?',
      [studyDayStart(_clock()).toUtc().millisecondsSinceEpoch],
    ))
      r['id'] as int,
  };

  /// Cartes en apprentissage dont l'heure est venue (ou presque).
  List<int> learningDue({List<int>? deckIds, Duration ahead = Duration.zero}) {
    final params = <Object?>[];
    final now = _nowMs();
    final limit = now + ahead.inMilliseconds;
    final f = _deckFilter(deckIds, params);
    return [
      for (final r in db.select(
        'SELECT c.id FROM cards c JOIN notes n ON n.id = c.note_id '
        'WHERE c.state IN (1, 3) AND c.suspended = 0 AND c.due <= ? '
        'AND (c.buried_until IS NULL OR c.buried_until <= ?)$f ORDER BY c.due, c.id',
        [limit, now, ...params],
      ))
        r['id'] as int,
    ];
  }

  /// Identifiants des cartes à passer aujourd'hui (révisions puis nouvelles),
  /// plafonds et règle « une carte par notion » appliqués, dans l'ordre choisi.
  /// Les cartes en apprentissage sont servies à part (voir [learningDue]).
  List<int> todayQueue({List<int>? deckIds, StudyOrder? order}) {
    final ids = deckIds ?? [for (final d in decks()) d.id];
    final nowMs = _nowMs();
    final endMs = studyDayEnd(_clock()).toUtc().millisecondsSinceEpoch;
    final global = globalOptions();
    // plafond général : le plus strict l'emporte avec celui du paquet
    var globalNewLeft = global.newPerDay == null
        ? null
        : global.newPerDay! - _globalNewDone();
    var globalReviewLeft = global.reviewsPerDay == null
        ? null
        : global.reviewsPerDay! - _globalReviewsDone();
    final studied = _notesStudiedToday();
    // une notion dont une carte est en cours d'apprentissage compte comme servie
    final seenNotes = <int>{
      for (final r in db.select(
        'SELECT DISTINCT note_id AS id FROM cards WHERE state IN (1, 3) AND suspended = 0 AND due <= ?',
        [nowMs + learnAhead.inMilliseconds],
      ))
        r['id'] as int,
    };
    final reviews = <int>[];
    final news = <int>[];

    for (final deckId in ids) {
      final opts = effectiveOptions(deckId);
      int? reviewLeft = opts.reviewsPerDay == null
          ? null
          : opts.reviewsPerDay! - reviewsDoneToday(deckId);
      int? newLeft = opts.newPerDay == null
          ? null
          : opts.newPerDay! - newDoneToday(deckId);
      if (globalReviewLeft != null) {
        reviewLeft = reviewLeft == null
            ? globalReviewLeft
            : min(reviewLeft, globalReviewLeft);
      }
      if (globalNewLeft != null) {
        newLeft = newLeft == null ? globalNewLeft : min(newLeft, globalNewLeft);
      }
      bool usable(int noteId) =>
          !opts.onePerNotePerDay ||
          (!studied.contains(noteId) && !seenNotes.contains(noteId));

      final dueRows = db.select(
        'SELECT c.id, c.note_id FROM cards c JOIN notes n ON n.id = c.note_id '
        'WHERE n.deck_id = ? AND c.state = 2 AND c.suspended = 0 AND c.due < ? '
        'AND (c.buried_until IS NULL OR c.buried_until <= ?) ORDER BY c.due, c.id',
        [deckId, endMs, nowMs],
      );
      final deckReviews = <int>[];
      for (final r in dueRows) {
        if (reviewLeft != null && deckReviews.length >= reviewLeft) break;
        final noteId = r['note_id'] as int;
        if (!usable(noteId)) continue;
        seenNotes.add(noteId);
        deckReviews.add(r['id'] as int);
      }
      final newRows = db.select(
        'SELECT c.id, c.note_id FROM cards c JOIN notes n ON n.id = c.note_id '
        'WHERE n.deck_id = ? AND c.state = 0 AND c.suspended = 0 '
        'AND (c.buried_until IS NULL OR c.buried_until <= ?) ORDER BY n.id, c.ord',
        [deckId, nowMs],
      );
      final deckNews = <int>[];
      for (final r in newRows) {
        if (newLeft != null && deckNews.length >= newLeft) break;
        final noteId = r['note_id'] as int;
        if (!usable(noteId)) continue;
        seenNotes.add(noteId);
        deckNews.add(r['id'] as int);
      }
      if (globalReviewLeft != null) globalReviewLeft -= deckReviews.length;
      if (globalNewLeft != null) globalNewLeft -= deckNews.length;
      if ((order ?? opts.order) == StudyOrder.shuffled) {
        deckReviews.shuffle(_random);
        deckNews.shuffle(_random);
      }
      reviews.addAll(deckReviews);
      news.addAll(deckNews);
    }
    return [...reviews, ...news];
  }

  int _globalNewDone() =>
      db.select(
            'SELECT COUNT(*) AS n FROM review_logs WHERE state_before = 0 AND reviewed_at >= ?',
            [studyDayStart(_clock()).toUtc().millisecondsSinceEpoch],
          ).first['n']
          as int;

  int _globalReviewsDone() =>
      db.select(
            'SELECT COUNT(*) AS n FROM review_logs WHERE state_before = 2 AND reviewed_at >= ?',
            [studyDayStart(_clock()).toUtc().millisecondsSinceEpoch],
          ).first['n']
          as int;

  /// Compteurs du jour pour un paquet ou pour tous.
  DeckCounts counts({int? deckId}) {
    final deckIds = deckId == null ? null : [deckId];
    final today = todayQueue(deckIds: deckIds);
    final learning = learningDue(deckIds: deckIds, ahead: learnAhead).length;
    final params = <Object?>[];
    final f = _deckFilter(deckIds, params);
    final total =
        db
                .select(
                  'SELECT COUNT(*) AS n FROM cards c JOIN notes n ON n.id = c.note_id WHERE 1 = 1$f',
                  params,
                )
                .first['n']
            as int;
    final notesCount =
        db
                .select(
                  'SELECT COUNT(*) AS n FROM notes n WHERE 1 = 1$f',
                  params,
                )
                .first['n']
            as int;
    final newTotal =
        db
                .select(
                  'SELECT COUNT(*) AS n FROM cards c JOIN notes n ON n.id = c.note_id '
                  'WHERE c.state = 0 AND c.suspended = 0$f',
                  params,
                )
                .first['n']
            as int;
    // parmi les cartes du jour, lesquelles sont neuves ?
    var newToday = 0;
    if (today.isNotEmpty) {
      final rows = db.select(
        'SELECT COUNT(*) AS n FROM cards WHERE id IN (${List.filled(today.length, '?').join(',')}) AND state = 0',
        today,
      );
      newToday = rows.first['n'] as int;
    }
    return DeckCounts(
      due: today.length - newToday + learning,
      newToday: newToday,
      newWaiting: max(0, newTotal - newToday),
      total: total,
      notes: notesCount,
    );
  }

  /// Prochaine échéance après maintenant : la date et le nombre de cartes
  /// programmées ce jour d'étude là. Null s'il n'y a plus rien de programmé.
  NextDue? nextDue({List<int>? deckIds}) {
    final params = <Object?>[_nowMs()];
    final f = _deckFilter(deckIds, params);
    final first = db
        .select(
          'SELECT MIN(c.due) AS d FROM cards c JOIN notes n ON n.id = c.note_id '
          'WHERE c.state IN (1, 2, 3) AND c.suspended = 0 AND c.due > ?$f',
          params,
        )
        .first['d'];
    if (first == null) return null;
    final firstDue = DateTime.fromMillisecondsSinceEpoch(first as int);
    final endMs = studyDayEnd(firstDue).toUtc().millisecondsSinceEpoch;
    final params2 = <Object?>[_nowMs(), endMs];
    final f2 = _deckFilter(deckIds, params2);
    final count =
        db
                .select(
                  'SELECT COUNT(*) AS n FROM cards c JOIN notes n ON n.id = c.note_id '
                  'WHERE c.state IN (1, 2, 3) AND c.suspended = 0 AND c.due > ? AND c.due < ?$f2',
                  params2,
                )
                .first['n']
            as int;
    return NextDue(firstDue, count);
  }

  /// Cartes jugées difficiles : difficulté FSRS élevée ou souvent oubliées.
  int hardCardCount() =>
      db
              .select(
                'SELECT COUNT(*) AS n FROM cards WHERE state IN (2, 3) AND suspended = 0 '
                'AND (difficulty >= 8 OR lapses >= 3)',
              )
              .first['n']
          as int;

  /// Durée moyenne d'une réponse, en secondes (8 s tant qu'on n'a pas de mesure).
  double averageSecondsPerCard() {
    final r = db
        .select(
          'SELECT AVG(duration_ms) AS a FROM (SELECT duration_ms FROM review_logs '
          'WHERE duration_ms IS NOT NULL AND duration_ms > 0 ORDER BY id DESC LIMIT 200)',
        )
        .first['a'];
    return r == null ? 8 : (r as num).toDouble() / 1000;
  }

  // ------------------------------------------------------------- réponse

  /// Prévisualisation des quatre délais d'une carte.
  Map<Grade, Duration> preview(int cardId) {
    final c = studyCard(cardId);
    final opts = effectiveOptions(c.note.deckId);
    return scheduling.preview(
      cardId,
      c.card.schedule,
      _clock(),
      retention: opts.retention,
    );
  }

  /// Enregistre une réponse : l'état de la carte change, l'historique garde la
  /// trace.
  AnswerResult answer(int cardId, Grade grade, {int? durationMs}) {
    final c = studyCard(cardId);
    final opts = effectiveOptions(c.note.deckId);
    final before = c.card;
    final out = scheduling.answer(
      cardId,
      before.schedule,
      grade,
      _clock(),
      retention: opts.retention,
    );
    final s = out.schedule;
    final nowMs = _nowMs();
    var leech = false;
    final logId = db.transaction(() {
      final suspend =
          opts.leechAction == LeechAction.suspend &&
          s.lapses >= opts.leechThreshold &&
          s.lapses > before.schedule.lapses;
      leech =
          s.lapses >= opts.leechThreshold && s.lapses > before.schedule.lapses;
      db.execute(
        'UPDATE cards SET state = ?, step = ?, stability = ?, difficulty = ?, due = ?, '
        'last_review = ?, reps = ?, lapses = ?, suspended = ?, buried_until = NULL WHERE id = ?',
        [
          s.state,
          s.step,
          s.stability,
          s.difficulty,
          s.dueMs,
          s.lastReviewMs,
          s.reps,
          s.lapses,
          suspend ? 1 : (before.suspended ? 1 : 0),
          cardId,
        ],
      );
      db.execute(
        'INSERT INTO review_logs(card_id, rating, reviewed_at, state_before, duration_ms, due_before, interval_days) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          cardId,
          grade.value,
          nowMs,
          before.schedule.state,
          durationMs,
          before.schedule.dueMs,
          out.interval.inMinutes / 1440,
        ],
      );
      return db.lastInsertId;
    });
    return AnswerResult(
      UndoToken._(cardId, before, logId, before.buriedUntilMs),
      s,
      out.interval,
      leech,
    );
  }

  /// Annule la réponse décrite par [token] (état de la carte et historique).
  void undo(UndoToken token) {
    final p = token.previous.schedule;
    db.transaction(() {
      db.execute(
        'UPDATE cards SET state = ?, step = ?, stability = ?, difficulty = ?, due = ?, '
        'last_review = ?, reps = ?, lapses = ?, suspended = ?, buried_until = ? WHERE id = ?',
        [
          p.state,
          p.step,
          p.stability,
          p.difficulty,
          p.dueMs,
          p.lastReviewMs,
          p.reps,
          p.lapses,
          token.previous.suspended ? 1 : 0,
          token.previousBuried,
          token.cardId,
        ],
      );
      db.execute('DELETE FROM review_logs WHERE id = ?', [token.logId]);
    });
  }

  // ------------------------------------------------------------ rattrapage

  /// Décale de [days] jours l'échéance des cartes en retard.
  int postponeOverdue(int days, {int? deckId}) {
    final params = <Object?>[
      days * 86400000,
      studyDayStart(_clock()).toUtc().millisecondsSinceEpoch,
    ];
    var where = 'state = 2 AND due < ?';
    if (deckId != null) {
      where += ' AND note_id IN (SELECT id FROM notes WHERE deck_id = ?)';
    }
    final args = [params[0], params[1], ?deckId];
    return db.transaction(() {
      db.execute('UPDATE cards SET due = due + ? WHERE $where', args);
      return db.changes;
    });
  }

  /// Étale les cartes en retard sur les [days] prochains jours.
  int spreadOverdue(int days, {int? deckId}) {
    final startMs = studyDayStart(_clock()).toUtc().millisecondsSinceEpoch;
    final rows = db.select(
      'SELECT id FROM cards WHERE state = 2 AND due < ?'
      '${deckId == null ? '' : ' AND note_id IN (SELECT id FROM notes WHERE deck_id = ?)'} ORDER BY due, id',
      [startMs, ?deckId],
    );
    if (rows.isEmpty || days < 1) return 0;
    db.transaction(() {
      for (var i = 0; i < rows.length; i++) {
        final day = (i * days) ~/ rows.length; // 0 .. days-1
        final newDue = startMs + (day + 1) * 86400000;
        db.execute('UPDATE cards SET due = ? WHERE id = ?', [
          newDue,
          rows[i]['id'],
        ]);
      }
    });
    return rows.length;
  }

  /// Date butoir : les cartes qui reviendraient après [deadline] sont
  /// ramenées avant, étalées sur les jours qui restent. Ne touche qu'aux dates.
  int applyDeadline(int deckId, DateTime deadline) {
    final startMs = studyDayStart(_clock()).toUtc().millisecondsSinceEpoch;
    final endOfDeadline = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
      studyDayRolloverHour,
    ).toUtc().millisecondsSinceEpoch;
    final daysLeft = ((endOfDeadline - startMs) / 86400000).floor();
    if (daysLeft < 1) return 0;
    final rows = db.select(
      'SELECT id FROM cards WHERE state = 2 AND due >= ? '
      'AND note_id IN (SELECT id FROM notes WHERE deck_id = ?) ORDER BY due, id',
      [endOfDeadline, deckId],
    );
    if (rows.isEmpty) return 0;
    db.transaction(() {
      for (var i = 0; i < rows.length; i++) {
        final day = (i * daysLeft) ~/ rows.length;
        db.execute('UPDATE cards SET due = ? WHERE id = ?', [
          startMs + (day + 1) * 86400000,
          rows[i]['id'],
        ]);
      }
    });
    return rows.length;
  }

  // ---------------------------------------------------------- statistiques

  /// Nombre de cartes révisées par jour d'étude sur les [days] derniers jours
  /// (le plus ancien d'abord).
  List<int> reviewsPerDay(int days) {
    final today = studyDayStart(_clock());
    final out = <int>[];
    for (var i = days - 1; i >= 0; i--) {
      final s = DateTime(
        today.year,
        today.month,
        today.day - i,
        studyDayRolloverHour,
      );
      final e = DateTime(
        today.year,
        today.month,
        today.day - i + 1,
        studyDayRolloverHour,
      );
      out.add(
        db.select(
              'SELECT COUNT(*) AS n FROM review_logs WHERE reviewed_at >= ? AND reviewed_at < ?',
              [
                s.toUtc().millisecondsSinceEpoch,
                e.toUtc().millisecondsSinceEpoch,
              ],
            ).first['n']
            as int,
      );
    }
    return out;
  }

  /// Jours d'étude consécutifs avec au moins une révision, en comptant
  /// aujourd'hui (ou hier si on n'a encore rien fait aujourd'hui).
  int streak() {
    final counts = reviewsPerDay(400);
    var i = counts.length - 1;
    if (counts[i] == 0) i--;
    var n = 0;
    while (i >= 0 && counts[i] > 0) {
      n++;
      i--;
    }
    return n;
  }

  /// Part des cartes déjà apprises retrouvées (réponse autre que « Encore »)
  /// sur les [days] derniers jours.
  RetentionStats retention(int days) {
    final since = _clock()
        .subtract(Duration(days: days))
        .toUtc()
        .millisecondsSinceEpoch;
    final r = db.select(
      'SELECT COUNT(*) AS total, COALESCE(SUM(CASE WHEN rating > 1 THEN 1 ELSE 0 END), 0) AS ok '
      'FROM review_logs WHERE state_before = 2 AND reviewed_at >= ?',
      [since],
    ).first;
    return RetentionStats(r['ok'] as int, r['total'] as int);
  }

  /// Cartes neuves / en apprentissage / jeunes / mûres (mûre : intervalle de
  /// 21 jours ou plus).
  StockStats stock() {
    final r = db
        .select(
          'SELECT '
          'COALESCE(SUM(CASE WHEN state = 0 THEN 1 ELSE 0 END), 0) AS fresh, '
          'COALESCE(SUM(CASE WHEN state IN (1, 3) THEN 1 ELSE 0 END), 0) AS learning, '
          'COALESCE(SUM(CASE WHEN state = 2 AND (due - last_review) < 21 * 86400000 THEN 1 ELSE 0 END), 0) AS young, '
          'COALESCE(SUM(CASE WHEN state = 2 AND (due - last_review) >= 21 * 86400000 THEN 1 ELSE 0 END), 0) AS mature '
          'FROM cards WHERE suspended = 0',
        )
        .first;
    return StockStats(
      fresh: r['fresh'] as int,
      learning: r['learning'] as int,
      young: r['young'] as int,
      mature: r['mature'] as int,
    );
  }

  // ------------------------------------------------------------ s'entraîner

  /// Tire des cartes dans les paquets choisis, pour s'entraîner (quelle que
  /// soit leur échéance). [count] null = toutes.
  List<int> drawCards(List<int> deckIds, {int? count, bool shuffled = true}) {
    if (deckIds.isEmpty) return const [];
    final params = <Object?>[];
    final f = _deckFilter(deckIds, params);
    final ids = [
      for (final r in db.select(
        'SELECT c.id FROM cards c JOIN notes n ON n.id = c.note_id '
        'WHERE c.suspended = 0$f ORDER BY n.id, c.ord',
        params,
      ))
        r['id'] as int,
    ];
    final List<int> picked;
    if (count == null || count >= ids.length) {
      picked = ids;
    } else {
      picked = ([...ids]..shuffle(_random)).sublist(0, max(0, count));
    }
    if (shuffled) {
      picked.shuffle(_random);
    } else {
      picked.sort(); // ordre du cours : celui de création
    }
    return picked;
  }

  /// Enregistre une séance « Se tester » (rien n'est reprogrammé).
  void recordPractice({
    required int total,
    required int correct,
    required int durationMs,
    required List<String> deckNames,
  }) {
    db.transaction(() {
      db.execute(
        'INSERT INTO practice_sessions(taken_at, total, correct, duration_ms, deck_names) VALUES (?, ?, ?, ?, ?)',
        [_nowMs(), total, correct, durationMs, deckNames.join(', ')],
      );
    });
  }

  List<PracticeRecord> practiceHistory() => [
    for (final r in db.select(
      'SELECT * FROM practice_sessions ORDER BY taken_at DESC, id DESC',
    ))
      PracticeRecord(
        id: r['id'] as int,
        takenAtMs: r['taken_at'] as int,
        total: r['total'] as int,
        correct: r['correct'] as int,
        durationMs: r['duration_ms'] as int,
        deckNames: r['deck_names'] as String,
      ),
  ];

  void deletePractice(int id) {
    db.transaction(
      () => db.execute('DELETE FROM practice_sessions WHERE id = ?', [id]),
    );
  }
}

/// Prochaine échéance de révision.
class NextDue {
  const NextDue(this.at, this.count);
  final DateTime at;
  final int count;
}

class PracticeRecord {
  const PracticeRecord({
    required this.id,
    required this.takenAtMs,
    required this.total,
    required this.correct,
    required this.durationMs,
    required this.deckNames,
  });
  final int id;
  final int takenAtMs;
  final int total;
  final int correct;
  final int durationMs;
  final String deckNames;

  /// Note sur 20 (arrondie au demi-point).
  double get score20 => total == 0 ? 0 : (correct / total * 40).round() / 2;
}
