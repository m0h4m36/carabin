import 'dart:convert';

import 'note_types.dart';
import 'scheduling.dart';
import 'study_options.dart';

/// Une réponse passée à une carte, telle qu'elle voyage dans un fichier.
class IncomingLog {
  const IncomingLog({
    required this.rating,
    required this.atMs,
    required this.stateBefore,
    this.durationMs,
    this.dueBeforeMs,
    this.intervalDays,
  });

  final int rating;
  final int atMs;
  final int stateBefore;
  final int? durationMs;
  final int? dueBeforeMs;
  final double? intervalDays;

  List<Object?> toJson() => [
    rating,
    atMs,
    stateBefore,
    durationMs,
    dueBeforeMs,
    intervalDays,
  ];

  factory IncomingLog.fromJson(Object? j) {
    final l = j as List;
    return IncomingLog(
      rating: l[0] as int,
      atMs: l[1] as int,
      stateBefore: l[2] as int,
      durationMs: l[3] as int?,
      dueBeforeMs: l[4] as int?,
      intervalDays: (l[5] as num?)?.toDouble(),
    );
  }
}

/// Une carte avec son avancement.
class IncomingCard {
  const IncomingCard({
    required this.ord,
    required this.schedule,
    this.suspended = false,
    this.logs = const [],
  });

  final int ord;
  final Schedule schedule;
  final bool suspended;
  final List<IncomingLog> logs;

  Map<String, Object?> toJson() => {
    'ord': ord,
    'state': schedule.state,
    'step': schedule.step,
    'stability': schedule.stability,
    'difficulty': schedule.difficulty,
    'due': schedule.dueMs,
    'last': schedule.lastReviewMs,
    'reps': schedule.reps,
    'lapses': schedule.lapses,
    'suspended': suspended,
    if (logs.isNotEmpty) 'logs': [for (final l in logs) l.toJson()],
  };

  factory IncomingCard.fromJson(Map<String, dynamic> j) => IncomingCard(
    ord: j['ord'] as int,
    schedule: Schedule(
      state: _state(j['state'] as int),
      step: j['step'] as int?,
      stability: (j['stability'] as num?)?.toDouble(),
      difficulty: (j['difficulty'] as num?)?.toDouble(),
      dueMs: j['due'] as int,
      lastReviewMs: j['last'] as int?,
      reps: (j['reps'] as int?) ?? 0,
      lapses: (j['lapses'] as int?) ?? 0,
    ),
    suspended: (j['suspended'] as bool?) ?? false,
    logs: [
      for (final l in (j['logs'] as List? ?? const [])) IncomingLog.fromJson(l),
    ],
  );

  static int _state(int s) {
    if (s < CardState.newCard || s > CardState.relearning) {
      throw const FormatException('état de carte inconnu');
    }
    return s;
  }
}

/// Une note à ajouter (ou à fusionner) dans un paquet.
class IncomingNote {
  const IncomingNote({
    required this.guid,
    required this.type,
    required this.fields,
    this.tags = const [],
    required this.createdAtMs,
    required this.updatedAtMs,
    this.cards = const [],
  });

  /// Identifiant stable ; deux notes de même identifiant sont la même note.
  final String guid;
  final NoteType type;
  final NoteFields fields;
  final List<String> tags;
  final int createdAtMs;
  final int updatedAtMs;

  /// Avancement des cartes ; vide = cartes neuves.
  final List<IncomingCard> cards;

  Map<String, Object?> toJson() => {
    'guid': guid,
    'type': type.name,
    'fields': fields.toMap(),
    'tags': tags.join(' '),
    'created': createdAtMs,
    'updated': updatedAtMs,
    if (cards.isNotEmpty) 'cards': [for (final c in cards) c.toJson()],
  };

  factory IncomingNote.fromJson(Map<String, dynamic> j) => IncomingNote(
    guid: _guid(j['guid'] as String),
    type: NoteType.values.byName(j['type'] as String),
    fields: NoteFields((j['fields'] as Map).cast<String, dynamic>()),
    tags: [
      for (final t in ((j['tags'] as String?) ?? '').split(' '))
        if (t.isNotEmpty) t,
    ],
    createdAtMs: j['created'] as int,
    updatedAtMs: j['updated'] as int,
    cards: [
      for (final c in (j['cards'] as List? ?? const []))
        IncomingCard.fromJson((c as Map).cast<String, dynamic>()),
    ],
  );

  static String _guid(String g) {
    if (g.isEmpty || g.length > 200) {
      throw const FormatException('identifiant de note invalide');
    }
    return g;
  }
}

/// Un paquet complet : nom, réglages propres et notes.
class IncomingDeck {
  const IncomingDeck({required this.name, this.options, required this.notes});

  final String name;
  final StudyOptions? options;
  final List<IncomingNote> notes;

  Map<String, Object?> toJson() => {
    'name': name,
    if (options != null) 'options': options!.toMap(),
    'notes': [for (final n in notes) n.toJson()],
  };

  factory IncomingDeck.fromJson(Map<String, dynamic> j) => IncomingDeck(
    name: j['name'] as String,
    options: j['options'] == null
        ? null
        : StudyOptions.fromJson(jsonEncode(j['options'])),
    notes: [
      for (final n in (j['notes'] as List))
        IncomingNote.fromJson((n as Map).cast<String, dynamic>()),
    ],
  );
}

/// Ce qu'un import a fait.
class ImportReport {
  ImportReport();

  int decksCreated = 0;
  int notesAdded = 0;
  int notesUpdated = 0;
  int notesPresent = 0;
  int notesSkipped = 0;
  int cardsAdded = 0;
  int cardsProgressed = 0;
  int logsAdded = 0;
  int mediaAdded = 0;
  int mediaSkipped = 0;

  /// Images citées mais introuvables ou non prises en charge ; sons et vidéos
  /// ignorés ; zones d'occlusion remplacées par un rectangle ou abandonnées
  /// (paquets venus d'autres applications).
  int imagesDropped = 0;
  int soundsDropped = 0;
  int shapesApproximated = 0;
  int shapesDropped = 0;

  /// Noms des paquets concernés (créés ou complétés), dans l'ordre.
  final List<String> deckNames = [];

  bool get changedAnything =>
      notesAdded > 0 ||
      notesUpdated > 0 ||
      cardsProgressed > 0 ||
      logsAdded > 0 ||
      decksCreated > 0;

  void add(ImportReport o) {
    decksCreated += o.decksCreated;
    notesAdded += o.notesAdded;
    notesUpdated += o.notesUpdated;
    notesPresent += o.notesPresent;
    notesSkipped += o.notesSkipped;
    cardsAdded += o.cardsAdded;
    cardsProgressed += o.cardsProgressed;
    logsAdded += o.logsAdded;
    mediaAdded += o.mediaAdded;
    mediaSkipped += o.mediaSkipped;
    imagesDropped += o.imagesDropped;
    soundsDropped += o.soundsDropped;
    shapesApproximated += o.shapesApproximated;
    shapesDropped += o.shapesDropped;
    for (final n in o.deckNames) {
      if (!deckNames.contains(n)) deckNames.add(n);
    }
  }
}
