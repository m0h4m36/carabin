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
];
