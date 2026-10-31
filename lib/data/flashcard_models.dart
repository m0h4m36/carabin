import 'package:sqlite3/sqlite3.dart';

import '../domain/note_types.dart';
import '../domain/scheduling.dart';

class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.subjectId,
    required this.documentId,
    required this.position,
    required this.hasOwnOptions,
  });
  factory Deck.fromRow(Row r) => Deck(
        id: r['id'] as int,
        name: r['name'] as String,
        subjectId: r['subject_id'] as int?,
        documentId: r['document_id'] as int?,
        position: r['position'] as int,
        hasOwnOptions: r['options_json'] != null,
      );
  final int id;
  final String name;
  final int? subjectId;
  final int? documentId;
  final int position;
  final bool hasOwnOptions;
}

class NoteRow {
  const NoteRow({
    required this.id,
    required this.deckId,
    required this.type,
    required this.fields,
    required this.tags,
    required this.documentId,
    required this.createdAtMs,
    required this.cardCount,
    required this.suspendedCount,
  });
  factory NoteRow.fromRow(Row r) => NoteRow(
        id: r['id'] as int,
        deckId: r['deck_id'] as int,
        type: NoteType.values.byName(r['type'] as String),
        fields: NoteFields.fromJson(r['fields_json'] as String),
        tags: [
          for (final t in (r['tags'] as String).split(' '))
            if (t.isNotEmpty) t,
        ],
        documentId: r['document_id'] as int?,
        createdAtMs: r['created_at'] as int,
        cardCount: (r['card_count'] as int?) ?? 0,
        suspendedCount: (r['suspended_count'] as int?) ?? 0,
      );
  final int id;
  final int deckId;
  final NoteType type;
  final NoteFields fields;
  final List<String> tags;
  final int? documentId;
  final int createdAtMs;
  final int cardCount;
  final int suspendedCount;

  bool get allSuspended => cardCount > 0 && suspendedCount == cardCount;
  String get preview => plainText(type, fields);
}

class CardRow {
  const CardRow({
    required this.id,
    required this.noteId,
    required this.ord,
    required this.schedule,
    required this.suspended,
    required this.buriedUntilMs,
  });
  factory CardRow.fromRow(Row r) => CardRow(
        id: r['id'] as int,
        noteId: r['note_id'] as int,
        ord: r['ord'] as int,
        schedule: Schedule(
          state: r['state'] as int,
          step: r['step'] as int?,
          stability: (r['stability'] as num?)?.toDouble(),
          difficulty: (r['difficulty'] as num?)?.toDouble(),
          dueMs: r['due'] as int,
          lastReviewMs: r['last_review'] as int?,
          reps: r['reps'] as int,
          lapses: r['lapses'] as int,
        ),
        suspended: (r['suspended'] as int) == 1,
        buriedUntilMs: r['buried_until'] as int?,
      );
  final int id;
  final int noteId;
  final int ord;
  final Schedule schedule;
  final bool suspended;
  final int? buriedUntilMs;
}

/// Une carte avec sa note, prête à être affichée.
class StudyCard {
  const StudyCard(this.card, this.note);
  final CardRow card;
  final NoteRow note;

  CardFace get face => renderFace(note.type, note.fields, card.ord);
}

/// Compteurs d'un paquet (ou de tous).
class DeckCounts {
  const DeckCounts({
    required this.due,
    required this.newToday,
    required this.newWaiting,
    required this.total,
    required this.notes,
  });

  /// Cartes à revoir aujourd'hui (apprentissage + révisions plafonnées).
  final int due;

  /// Nouvelles cartes proposées aujourd'hui (plafonnées).
  final int newToday;

  /// Nouvelles cartes qui attendent (au-delà du plafond du jour).
  final int newWaiting;
  final int total;
  final int notes;

  int get todayTotal => due + newToday;
}
