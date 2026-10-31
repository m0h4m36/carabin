/// Migrations de la base, appliquées dans l'ordre. Ne jamais modifier une
/// migration déjà publiée : en ajouter une nouvelle à la fin de la liste.
const List<String> migrations = [
  // 1 : réglages et cours
  '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE years (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  position INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE semesters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  year_id INTEGER NOT NULL REFERENCES years(id) ON DELETE CASCADE,
  name TEXT NOT NULL COLLATE NOCASE,
  position INTEGER NOT NULL DEFAULT 0,
  UNIQUE (year_id, name)
);

CREATE TABLE subjects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  semester_id INTEGER NOT NULL REFERENCES semesters(id) ON DELETE CASCADE,
  name TEXT NOT NULL COLLATE NOCASE,
  color INTEGER NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  exam_date TEXT,
  UNIQUE (semester_id, name)
);

CREATE TABLE topics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  name TEXT NOT NULL COLLATE NOCASE,
  position INTEGER NOT NULL DEFAULT 0,
  UNIQUE (subject_id, name)
);

CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  kind TEXT NOT NULL,
  rel_path TEXT NOT NULL UNIQUE,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  page_count INTEGER,
  reads_mask INTEGER NOT NULL DEFAULT 0,
  position INTEGER NOT NULL DEFAULT 0,
  imported_at TEXT NOT NULL,
  last_opened_at TEXT,
  archived_at TEXT
);
CREATE INDEX documents_topic ON documents(topic_id);
''',

  // 2 : paquets, notes, cartes et historique de révision
  '''
CREATE TABLE decks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE,
  subject_id INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
  document_id INTEGER REFERENCES documents(id) ON DELETE SET NULL,
  options_json TEXT,
  position INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  fields_json TEXT NOT NULL,
  tags TEXT NOT NULL DEFAULT '',
  document_id INTEGER REFERENCES documents(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX notes_deck ON notes(deck_id);

CREATE TABLE cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  ord INTEGER NOT NULL,
  state INTEGER NOT NULL DEFAULT 0,
  step INTEGER,
  stability REAL,
  difficulty REAL,
  due INTEGER NOT NULL,
  last_review INTEGER,
  reps INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  suspended INTEGER NOT NULL DEFAULT 0,
  buried_until INTEGER,
  UNIQUE (note_id, ord)
);
CREATE INDEX cards_due ON cards(state, due);

CREATE TABLE review_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  card_id INTEGER NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL,
  reviewed_at INTEGER NOT NULL,
  state_before INTEGER NOT NULL,
  duration_ms INTEGER,
  due_before INTEGER,
  interval_days REAL
);
CREATE INDEX review_logs_time ON review_logs(reviewed_at);
CREATE INDEX review_logs_card ON review_logs(card_id);

CREATE TABLE practice_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  taken_at INTEGER NOT NULL,
  total INTEGER NOT NULL,
  correct INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  deck_names TEXT NOT NULL
);
''',

  // 3 : identifiant stable des notes (échange de paquets entre appareils,
  // réimport sans doublon)
  '''
ALTER TABLE notes ADD COLUMN guid TEXT;
UPDATE notes SET guid = lower(hex(randomblob(16)));
CREATE UNIQUE INDEX notes_guid ON notes(guid);
''',
];
