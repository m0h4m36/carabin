import 'package:sqlite3/sqlite3.dart';

import '../domain/exchange.dart';
import '../domain/note_types.dart';
import '../domain/scheduling.dart';
import '../domain/study_options.dart';
import 'database.dart';
import 'errors.dart';
import 'flashcard_models.dart';
import 'flashcards_repository.dart';
import 'names.dart';

/// Lecture et écriture de paquets pour les échanges de fichiers (partage,
/// progression d'un appareil à l'autre, imports).
///
/// Une note est reconnue par son identifiant stable : réimporter un paquet
/// n'en double jamais les notes, et la progression ne remplace celle d'une
/// carte que si elle est plus récente.
class DeckExchange {
  DeckExchange(this.db, this.flashcards);

  final AppDatabase db;
  final FlashcardsRepository flashcards;

  // ----------------------------------------------------------------- export

  /// Contenu d'un paquet, avec l'avancement des cartes si [progress].
  IncomingDeck exportDeck(int deckId, {required bool progress}) {
    final deck = flashcards.deck(deckId);
    final cardsByNote = <int, List<IncomingCard>>{};
    if (progress) {
      final logsByCard = <int, List<IncomingLog>>{};
      for (final r in db.select(
        'SELECT l.* FROM review_logs l '
        'JOIN cards c ON c.id = l.card_id JOIN notes n ON n.id = c.note_id '
        'WHERE n.deck_id = ? ORDER BY l.reviewed_at, l.id',
        [deckId],
      )) {
        (logsByCard[r['card_id'] as int] ??= []).add(
          IncomingLog(
            rating: r['rating'] as int,
            atMs: r['reviewed_at'] as int,
            stateBefore: r['state_before'] as int,
            durationMs: r['duration_ms'] as int?,
            dueBeforeMs: r['due_before'] as int?,
            intervalDays: (r['interval_days'] as num?)?.toDouble(),
          ),
        );
      }
      for (final r in db.select(
        'SELECT c.* FROM cards c JOIN notes n ON n.id = c.note_id '
        'WHERE n.deck_id = ? ORDER BY c.note_id, c.ord',
        [deckId],
      )) {
        final c = CardRow.fromRow(r);
        (cardsByNote[c.noteId] ??= []).add(
          IncomingCard(
            ord: c.ord,
            schedule: c.schedule,
            suspended: c.suspended,
            logs: logsByCard[c.id] ?? const [],
          ),
        );
      }
    }
    final notes = <IncomingNote>[];
    for (final r in db.select(
      'SELECT * FROM notes WHERE deck_id = ? ORDER BY id',
      [deckId],
    )) {
      notes.add(
        IncomingNote(
          guid: r['guid'] as String,
          type: NoteType.values.byName(r['type'] as String),
          fields: NoteFields.fromJson(r['fields_json'] as String),
          tags: [
            for (final t in (r['tags'] as String).split(' '))
              if (t.isNotEmpty) t,
          ],
          createdAtMs: r['created_at'] as int,
          updatedAtMs: r['updated_at'] as int,
          cards: cardsByNote[r['id'] as int] ?? const [],
        ),
      );
    }
    return IncomingDeck(
      name: deck.name,
      options: flashcards.deckOptions(deckId),
      notes: notes,
    );
  }

  /// Fichiers de médias cités par les notes de ces paquets.
  Set<String> mediaOf(Iterable<int> deckIds) {
    final out = <String>{};
    for (final id in deckIds) {
      for (final r in db.select(
        'SELECT type, fields_json FROM notes WHERE deck_id = ?',
        [id],
      )) {
        out.addAll(noteMedia(NoteFields.fromJson(r['fields_json'] as String)));
      }
    }
    return out;
  }

  // ----------------------------------------------------------------- import

  /// Le paquet de ce nom, ou un nouveau. Le nom est comparé sans tenir compte
  /// des majuscules ni des accents, quelle que soit la matière du paquet.
  ({Deck deck, bool created}) ensureDeck(
    String rawName, {
    StudyOptions? options,
  }) {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const EmptyNameError();
    final key = normalize(name);
    for (final d in flashcards.decks()) {
      if (normalize(d.name) == key) return (deck: d, created: false);
    }
    final d = flashcards.createDeck(name);
    if (options != null) flashcards.setDeckOptions(d.id, options);
    return (deck: d, created: true);
  }

  /// Ajoute ou fusionne des notes dans [deck]. À appeler dans une transaction
  /// ([AppDatabase.batch] pour un gros import).
  void importNotes(
    Deck deck,
    List<IncomingNote> notes,
    ImportReport report, {
    required bool progress,
    required int nowMs,
  }) {
    for (final n in notes) {
      if (validateNote(n.type, n.fields) != null || n.guid.isEmpty) {
        report.notesSkipped++;
        continue;
      }
      final existing = db.select(
        'SELECT id, updated_at, fields_json FROM notes WHERE guid = ?',
        [n.guid],
      );
      if (existing.isEmpty) {
        _insertNote(deck.id, n, report, progress: progress, nowMs: nowMs);
      } else {
        _mergeNote(existing.first, n, report, progress: progress, nowMs: nowMs);
      }
    }
  }

  void _insertNote(
    int deckId,
    IncomingNote n,
    ImportReport report, {
    required bool progress,
    required int nowMs,
  }) {
    db.execute(
      'INSERT INTO notes(guid, deck_id, type, fields_json, tags, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        n.guid,
        deckId,
        n.type.name,
        n.fields.toJson(),
        flashcards.joinTags(n.tags),
        n.createdAtMs,
        n.updatedAtMs,
      ],
    );
    final noteId = db.lastInsertId;
    report.notesAdded++;
    final byOrd = {for (final c in n.cards) c.ord: c};
    for (final ord in cardOrdinals(n.type, n.fields)) {
      final inc = progress ? byOrd[ord] : null;
      final s = inc?.schedule ?? Schedule.fresh(nowMs);
      db.execute(
        'INSERT INTO cards(note_id, ord, state, step, stability, difficulty, due, '
        'last_review, reps, lapses, suspended) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          noteId,
          ord,
          s.state,
          s.step,
          s.stability,
          s.difficulty,
          s.dueMs,
          s.lastReviewMs,
          s.reps,
          s.lapses,
          (inc?.suspended ?? false) ? 1 : 0,
        ],
      );
      report.cardsAdded++;
      if (inc != null) _insertLogs(db.lastInsertId, inc.logs, report);
    }
  }

  void _insertLogs(int cardId, List<IncomingLog> logs, ImportReport report) {
    for (final l in logs) {
      final dup = db.select(
        'SELECT 1 FROM review_logs WHERE card_id = ? AND reviewed_at = ?',
        [cardId, l.atMs],
      );
      if (dup.isNotEmpty) continue;
      db.execute(
        'INSERT INTO review_logs(card_id, rating, reviewed_at, state_before, '
        'duration_ms, due_before, interval_days) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          cardId,
          l.rating,
          l.atMs,
          l.stateBefore,
          l.durationMs,
          l.dueBeforeMs,
          l.intervalDays,
        ],
      );
      report.logsAdded++;
    }
  }

  void _mergeNote(
    Row existing,
    IncomingNote n,
    ImportReport report, {
    required bool progress,
    required int nowMs,
  }) {
    final noteId = existing['id'] as int;
    var touched = false;

    // contenu : le plus récent l'emporte
    final newer = n.updatedAtMs > (existing['updated_at'] as int);
    final localFields = NoteFields.fromJson(existing['fields_json'] as String);
    if (newer && localFields.toJson() != n.fields.toJson()) {
      final before = flashcards.cardsOfNote(noteId).length;
      flashcards.updateNote(noteId, n.fields, tags: n.tags);
      final after = flashcards.cardsOfNote(noteId).length;
      if (after > before) report.cardsAdded += after - before;
      db.execute('UPDATE notes SET updated_at = ? WHERE id = ?', [
        n.updatedAtMs,
        noteId,
      ]);
      report.notesUpdated++;
      touched = true;
    }

    // avancement : la carte révisée le plus récemment l'emporte
    if (progress) {
      var progressed = false;
      for (final inc in n.cards) {
        final rows = db.select(
          'SELECT id, last_review FROM cards WHERE note_id = ? AND ord = ?',
          [noteId, inc.ord],
        );
        if (rows.isEmpty) continue;
        final cardId = rows.first['id'] as int;
        final local = rows.first['last_review'] as int?;
        final theirs = inc.schedule.lastReviewMs;
        if (theirs != null && (local == null || theirs > local)) {
          final s = inc.schedule;
          db.execute(
            'UPDATE cards SET state = ?, step = ?, stability = ?, difficulty = ?, '
            'due = ?, last_review = ?, reps = ?, lapses = ?, suspended = ? WHERE id = ?',
            [
              s.state,
              s.step,
              s.stability,
              s.difficulty,
              s.dueMs,
              s.lastReviewMs,
              s.reps,
              s.lapses,
              inc.suspended ? 1 : 0,
              cardId,
            ],
          );
          report.cardsProgressed++;
          progressed = true;
        }
        final before = report.logsAdded;
        _insertLogs(cardId, inc.logs, report);
        if (report.logsAdded > before) progressed = true;
      }
      touched = touched || progressed;
    }
    if (!touched) report.notesPresent++;
  }
}
