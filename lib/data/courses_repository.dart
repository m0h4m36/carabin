import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show Row;

import 'database.dart';
import 'errors.dart';
import 'models.dart';
import 'names.dart';
import 'workspace.dart';

/// Donne le nombre de pages d'un fichier (null si inconnu).
typedef PageCounter = Future<int?> Function(String absolutePath);

enum CourseLevel { year, semester, subject, topic }

/// Résultat de « Synchroniser » : ce qui a été repris du disque.
class SyncReport {
  const SyncReport({required this.added, required this.missing});

  /// Fichiers trouvés dans le dossier et ajoutés à l'appli.
  final int added;

  /// Documents connus de l'appli dont le fichier a disparu du disque
  /// (jamais supprimés automatiquement).
  final int missing;
}

class DocHit {
  const DocHit(this.doc, this.trail);
  final Doc doc;
  final Trail? trail;
}

/// Cours : année › semestre › matière › thème, et leurs documents.
///
/// Chaque niveau a un dossier sur le disque
/// (`Cours/<année>/<semestre>/<matière>/<thème>/`). Les noms de dossiers
/// suivent les noms saisis ; renommer ou déplacer renomme ou déplace aussi
/// le dossier et met à jour le chemin des documents.
class CoursesRepository {
  CoursesRepository(
    this.db,
    this.workspace, {
    this.pageCounter,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final Workspace workspace;
  final PageCounter? pageCounter;
  final DateTime Function() _clock;

  String _stamp() => _clock().toUtc().toIso8601String();

  // ---------------------------------------------------------------- noms

  String _cleanName(String raw) {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const EmptyNameError();
    return name;
  }

  /// Vérifie qu'aucun frère ne porte déjà [name] (ou un nom de même dossier).
  void _checkFree({
    required String table,
    required String? parentColumn,
    required int? parentId,
    required String name,
    int? exceptId,
  }) {
    final rows = parentColumn == null
        ? db.select('SELECT id, name FROM $table')
        : db.select(
            'SELECT id, name FROM $table WHERE $parentColumn = ?',
            [parentId],
          );
    final wanted = safeFileName(name).toLowerCase();
    for (final r in rows) {
      if (r['id'] == exceptId) continue;
      final other = r['name'] as String;
      if (other.toLowerCase() == name.toLowerCase() ||
          safeFileName(other).toLowerCase() == wanted) {
        throw NameTakenError(name);
      }
    }
  }

  int _nextPosition(String table, String? column, int? parentId) {
    final r = column == null
        ? db.select('SELECT COALESCE(MAX(position), -1) + 1 AS n FROM $table')
        : db.select(
            'SELECT COALESCE(MAX(position), -1) + 1 AS n FROM $table '
            'WHERE $column = ?',
            [parentId],
          );
    return r.first['n'] as int;
  }

  // ------------------------------------------------------------- chemins

  /// Noms (année, semestre, matière, thème) jusqu'au niveau demandé.
  List<String> _names(CourseLevel level, int id) {
    final sql = switch (level) {
      CourseLevel.year => 'SELECT y.name AS a FROM years y WHERE y.id = ?',
      CourseLevel.semester =>
        'SELECT y.name AS a, s.name AS b FROM semesters s '
            'JOIN years y ON y.id = s.year_id WHERE s.id = ?',
      CourseLevel.subject =>
        'SELECT y.name AS a, s.name AS b, m.name AS c FROM subjects m '
            'JOIN semesters s ON s.id = m.semester_id '
            'JOIN years y ON y.id = s.year_id WHERE m.id = ?',
      CourseLevel.topic =>
        'SELECT y.name AS a, s.name AS b, m.name AS c, t.name AS d '
            'FROM topics t JOIN subjects m ON m.id = t.subject_id '
            'JOIN semesters s ON s.id = m.semester_id '
            'JOIN years y ON y.id = s.year_id WHERE t.id = ?',
    };
    final rows = db.select(sql, [id]);
    if (rows.isEmpty) throw const NotFoundError();
    final row = rows.first;
    return [
      for (final k in ['a', 'b', 'c', 'd'])
        if (row.containsKey(k)) row[k] as String,
    ];
  }

  /// Chemin relatif (« / ») du dossier d'un élément.
  String relDir(CourseLevel level, int id) => [
        Workspace.coursName,
        ..._names(level, id).map(safeFileName),
      ].join('/');

  String _join(String parent, String child) => '$parent/${safeFileName(child)}';

  void _mkdir(String rel) {
    try {
      Directory(workspace.absolute(rel)).createSync(recursive: true);
    } on FileSystemException catch (e) {
      throw FileProblemError(e.message);
    }
  }

  static const _trailSelect =
      'SELECT t.id AS t_id, t.subject_id AS t_subject, t.name AS t_name, '
      't.position AS t_pos, '
      'm.id AS m_id, m.semester_id AS m_sem, m.name AS m_name, '
      'm.color AS m_color, m.position AS m_pos, m.exam_date AS m_exam, '
      's.id AS s_id, s.year_id AS s_year, s.name AS s_name, '
      's.position AS s_pos, y.id AS y_id, y.name AS y_name, '
      'y.position AS y_pos '
      'FROM topics t JOIN subjects m ON m.id = t.subject_id '
      'JOIN semesters s ON s.id = m.semester_id '
      'JOIN years y ON y.id = s.year_id';

  Trail _trailFromRow(Row r) => Trail(
        year: Year(
          id: r['y_id'] as int,
          name: r['y_name'] as String,
          position: r['y_pos'] as int,
        ),
        semester: Semester(
          id: r['s_id'] as int,
          yearId: r['s_year'] as int,
          name: r['s_name'] as String,
          position: r['s_pos'] as int,
        ),
        subject: Subject(
          id: r['m_id'] as int,
          semesterId: r['m_sem'] as int,
          name: r['m_name'] as String,
          color: r['m_color'] as int,
          position: r['m_pos'] as int,
          examDate: r['m_exam'] as String?,
        ),
        topic: Topic(
          id: r['t_id'] as int,
          subjectId: r['t_subject'] as int,
          name: r['t_name'] as String,
          position: r['t_pos'] as int,
        ),
      );

  Trail trailOfTopic(int topicId) {
    final rows = db.select('$_trailSelect WHERE t.id = ?', [topicId]);
    if (rows.isEmpty) throw const NotFoundError();
    return _trailFromRow(rows.first);
  }

  /// Tous les thèmes avec leur chemin complet, dans l'ordre de l'arborescence
  /// (pour les listes de choix : déplacer, rattacher, examens).
  List<Trail> allTrails() => [
        for (final r in db.select(
          '$_trailSelect ORDER BY y.position, y.id, s.position, s.id, '
          'm.position, m.id, t.position, t.id',
        ))
          _trailFromRow(r),
      ];

  // --------------------------------------------------------------- lecture

  List<Year> years() => [
        for (final r in db.select(
          'SELECT * FROM years ORDER BY position, id',
        ))
          Year.fromRow(r),
      ];

  Year year(int id) {
    final rows = db.select('SELECT * FROM years WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return Year.fromRow(rows.first);
  }

  List<Semester> semesters(int yearId) => [
        for (final r in db.select(
          'SELECT * FROM semesters WHERE year_id = ? ORDER BY position, id',
          [yearId],
        ))
          Semester.fromRow(r),
      ];

  List<Subject> subjects(int semesterId) => [
        for (final r in db.select(
          'SELECT * FROM subjects WHERE semester_id = ? ORDER BY position, id',
          [semesterId],
        ))
          Subject.fromRow(r),
      ];

  Subject subject(int id) {
    final rows = db.select('SELECT * FROM subjects WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return Subject.fromRow(rows.first);
  }

  /// Toutes les matières, avec leur semestre et leur année (pour les listes
  /// de choix : QCM, examens, paquets).
  List<(Subject, Semester, Year)> allSubjects() => [
        for (final r in db.select(
          'SELECT m.id AS m_id, m.semester_id AS m_sem, m.name AS m_name, '
          'm.color AS m_color, m.position AS m_pos, m.exam_date AS m_exam, '
          's.id AS s_id, s.year_id AS s_year, s.name AS s_name, '
          's.position AS s_pos, y.id AS y_id, y.name AS y_name, '
          'y.position AS y_pos FROM subjects m '
          'JOIN semesters s ON s.id = m.semester_id '
          'JOIN years y ON y.id = s.year_id '
          'ORDER BY y.position, y.id, s.position, s.id, m.position, m.id',
        ))
          (
            Subject(
              id: r['m_id'] as int,
              semesterId: r['m_sem'] as int,
              name: r['m_name'] as String,
              color: r['m_color'] as int,
              position: r['m_pos'] as int,
              examDate: r['m_exam'] as String?,
            ),
            Semester(
              id: r['s_id'] as int,
              yearId: r['s_year'] as int,
              name: r['s_name'] as String,
              position: r['s_pos'] as int,
            ),
            Year(
              id: r['y_id'] as int,
              name: r['y_name'] as String,
              position: r['y_pos'] as int,
            ),
          ),
      ];

  List<Topic> topics(int subjectId) => [
        for (final r in db.select(
          'SELECT * FROM topics WHERE subject_id = ? ORDER BY position, id',
          [subjectId],
        ))
          Topic.fromRow(r),
      ];

  List<Doc> documents(int topicId) => [
        for (final r in db.select(
          'SELECT * FROM documents WHERE topic_id = ? AND archived_at IS NULL '
          'ORDER BY position, id',
          [topicId],
        ))
          Doc.fromRow(r),
      ];

  Doc? document(int id) {
    final rows = db.select('SELECT * FROM documents WHERE id = ?', [id]);
    return rows.isEmpty ? null : Doc.fromRow(rows.first);
  }

  /// Nombre de thèmes et de documents d'une matière.
  (int topics, int docs) subjectCounts(int subjectId) {
    final t = db.select(
      'SELECT COUNT(*) AS n FROM topics WHERE subject_id = ?',
      [subjectId],
    ).first['n'] as int;
    final d = db.select(
      'SELECT COUNT(*) AS n FROM documents d JOIN topics t ON t.id = d.topic_id '
      'WHERE t.subject_id = ? AND d.archived_at IS NULL',
      [subjectId],
    ).first['n'] as int;
    return (t, d);
  }

  /// Documents récemment ouverts, du plus récent au plus ancien.
  List<Doc> recents({int limit = 8}) => [
        for (final r in db.select(
          'SELECT * FROM documents WHERE last_opened_at IS NOT NULL '
          'AND archived_at IS NULL ORDER BY last_opened_at DESC LIMIT ?',
          [limit],
        ))
          Doc.fromRow(r),
      ];

  /// Documents dont le titre contient [query] (sans tenir compte des
  /// majuscules ni des accents).
  List<DocHit> searchDocuments(String query, {int limit = 30}) {
    final q = normalize(query.trim());
    if (q.isEmpty) return const [];
    final hits = <DocHit>[];
    for (final r in db.select(
      'SELECT * FROM documents WHERE archived_at IS NULL '
      'ORDER BY last_opened_at DESC, id DESC',
    )) {
      final doc = Doc.fromRow(r);
      if (normalize(doc.title).contains(q)) {
        Trail? trail;
        if (doc.topicId != null) {
          try {
            trail = trailOfTopic(doc.topicId!);
          } on NotFoundError {
            trail = null;
          }
        }
        hits.add(DocHit(doc, trail));
        if (hits.length >= limit) break;
      }
    }
    return hits;
  }

  // ------------------------------------------------------------ création

  Year createYear(String rawName) {
    final name = _cleanName(rawName);
    _checkFree(table: 'years', parentColumn: null, parentId: null, name: name);
    _mkdir('${Workspace.coursName}/${safeFileName(name)}');
    final id = db.transaction(() {
      db.execute(
        'INSERT INTO years(name, position) VALUES (?, ?)',
        [name, _nextPosition('years', null, null)],
      );
      return db.lastInsertId;
    });
    return year(id);
  }

  Semester createSemester(int yearId, String rawName) {
    final name = _cleanName(rawName);
    year(yearId);
    _checkFree(
      table: 'semesters',
      parentColumn: 'year_id',
      parentId: yearId,
      name: name,
    );
    _mkdir(_join(relDir(CourseLevel.year, yearId), name));
    final id = db.transaction(() {
      db.execute(
        'INSERT INTO semesters(year_id, name, position) VALUES (?, ?, ?)',
        [yearId, name, _nextPosition('semesters', 'year_id', yearId)],
      );
      return db.lastInsertId;
    });
    return Semester.fromRow(
      db.select('SELECT * FROM semesters WHERE id = ?', [id]).first,
    );
  }

  Subject createSubject(int semesterId, String rawName, {required int color}) {
    final name = _cleanName(rawName);
    _checkFree(
      table: 'subjects',
      parentColumn: 'semester_id',
      parentId: semesterId,
      name: name,
    );
    _mkdir(_join(relDir(CourseLevel.semester, semesterId), name));
    final id = db.transaction(() {
      db.execute(
        'INSERT INTO subjects(semester_id, name, color, position) '
        'VALUES (?, ?, ?, ?)',
        [
          semesterId,
          name,
          color,
          _nextPosition('subjects', 'semester_id', semesterId),
        ],
      );
      return db.lastInsertId;
    });
    return subject(id);
  }

  Topic createTopic(int subjectId, String rawName) {
    final name = _cleanName(rawName);
    _checkFree(
      table: 'topics',
      parentColumn: 'subject_id',
      parentId: subjectId,
      name: name,
    );
    _mkdir(_join(relDir(CourseLevel.subject, subjectId), name));
    final id = db.transaction(() {
      db.execute(
        'INSERT INTO topics(subject_id, name, position) VALUES (?, ?, ?)',
        [subjectId, name, _nextPosition('topics', 'subject_id', subjectId)],
      );
      return db.lastInsertId;
    });
    return Topic.fromRow(
      db.select('SELECT * FROM topics WHERE id = ?', [id]).first,
    );
  }

  // ------------------------------------------------------------ renommer

  static const _tables = {
    CourseLevel.year: 'years',
    CourseLevel.semester: 'semesters',
    CourseLevel.subject: 'subjects',
    CourseLevel.topic: 'topics',
  };

  static const _parentColumns = {
    CourseLevel.year: null,
    CourseLevel.semester: 'year_id',
    CourseLevel.subject: 'semester_id',
    CourseLevel.topic: 'subject_id',
  };

  int? _parentIdOf(CourseLevel level, int id) {
    final col = _parentColumns[level];
    if (col == null) return null;
    final rows = db.select(
      'SELECT $col AS parent FROM ${_tables[level]} WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) throw const NotFoundError();
    return rows.first['parent'] as int;
  }

  /// Réécrit le début du chemin des documents d'un dossier déplacé.
  void _rewritePrefix(String oldRel, String newRel, {required bool archive}) {
    final oldLen = oldRel.runes.length;
    db.execute(
      'UPDATE documents SET rel_path = ? || substr(rel_path, ?)'
      '${archive ? ', archived_at = ?' : ''} '
      'WHERE archived_at IS NULL AND substr(rel_path, 1, ?) = ? '
      "AND substr(rel_path, ?, 1) = '/'",
      [
        newRel,
        oldLen + 1,
        if (archive) _stamp(),
        oldLen,
        oldRel,
        oldLen + 1,
      ],
    );
  }

  /// Déplace un dossier du disque ; renvoie une fonction qui annule le
  /// déplacement (si l'écriture en base échoue ensuite).
  void Function() _moveDir(String oldRel, String newRel) {
    final from = Directory(workspace.absolute(oldRel));
    final to = workspace.absolute(newRel);
    if (oldRel == newRel) return () {};
    final sameFolderOtherCase = oldRel.toLowerCase() == newRel.toLowerCase();
    try {
      if (!from.existsSync()) {
        Directory(to).createSync(recursive: true);
        return () {};
      }
      if (!sameFolderOtherCase &&
          (Directory(to).existsSync() || File(to).existsSync())) {
        throw FileProblemError('Le dossier existe déjà : $newRel');
      }
      Directory(p.dirname(to)).createSync(recursive: true);
      if (sameFolderOtherCase) {
        // Sur Windows et macOS, « Anatomie » et « anatomie » désignent le même
        // dossier : on passe par un nom provisoire.
        final tmp = '$to.carabin-tmp';
        from.renameSync(tmp);
        Directory(tmp).renameSync(to);
      } else {
        from.renameSync(to);
      }
    } on FileSystemException catch (e) {
      throw FileProblemError(e.message);
    }
    return () {
      try {
        Directory(to).renameSync(workspace.absolute(oldRel));
      } on FileSystemException {
        // Rien de plus à faire : l'erreur d'origine est relancée.
      }
    };
  }

  void rename(CourseLevel level, int id, String rawName) {
    final name = _cleanName(rawName);
    final oldRel = relDir(level, id);
    _checkFree(
      table: _tables[level]!,
      parentColumn: _parentColumns[level],
      parentId: _parentIdOf(level, id),
      name: name,
      exceptId: id,
    );
    final newRel = '${p.posix.dirname(oldRel)}/${safeFileName(name)}';
    final undo = _moveDir(oldRel, newRel);
    try {
      db.transaction(() {
        db.execute('UPDATE ${_tables[level]} SET name = ? WHERE id = ?', [
          name,
          id,
        ]);
        _rewritePrefix(oldRel, newRel, archive: false);
      });
    } catch (_) {
      undo();
      rethrow;
    }
  }

  void setSubjectColor(int subjectId, int color) {
    db.transaction(() {
      db.execute('UPDATE subjects SET color = ? WHERE id = ?', [
        color,
        subjectId,
      ]);
    });
  }

  void setExamDate(int subjectId, String? isoDate) {
    db.transaction(() {
      db.execute('UPDATE subjects SET exam_date = ? WHERE id = ?', [
        isoDate,
        subjectId,
      ]);
    });
  }

  /// Enregistre un nouvel ordre (liste d'identifiants dans l'ordre voulu).
  void reorder(CourseLevel level, List<int> orderedIds) {
    db.transaction(() {
      for (var i = 0; i < orderedIds.length; i++) {
        db.execute(
          'UPDATE ${_tables[level]} SET position = ? WHERE id = ?',
          [i, orderedIds[i]],
        );
      }
    });
  }

  void reorderDocuments(List<int> orderedIds) {
    db.transaction(() {
      for (var i = 0; i < orderedIds.length; i++) {
        db.execute('UPDATE documents SET position = ? WHERE id = ?', [
          i,
          orderedIds[i],
        ]);
      }
    });
  }

  // ----------------------------------------------------------- déplacer

  /// Déplace un thème (et ses documents) dans une autre matière.
  void moveTopic(int topicId, int newSubjectId) {
    final oldRel = relDir(CourseLevel.topic, topicId);
    final topic = db
        .select('SELECT * FROM topics WHERE id = ?', [topicId])
        .map(Topic.fromRow)
        .first;
    if (topic.subjectId == newSubjectId) return;
    _checkFree(
      table: 'topics',
      parentColumn: 'subject_id',
      parentId: newSubjectId,
      name: topic.name,
    );
    final newRel = _join(relDir(CourseLevel.subject, newSubjectId), topic.name);
    final undo = _moveDir(oldRel, newRel);
    try {
      db.transaction(() {
        db.execute(
          'UPDATE topics SET subject_id = ?, position = ? WHERE id = ?',
          [
            newSubjectId,
            _nextPosition('topics', 'subject_id', newSubjectId),
            topicId,
          ],
        );
        _rewritePrefix(oldRel, newRel, archive: false);
      });
    } catch (_) {
      undo();
      rethrow;
    }
  }

  /// Déplace un document dans un autre thème.
  void moveDocument(int docId, int newTopicId) {
    final doc = document(docId);
    if (doc == null || doc.archivedAt != null) throw const NotFoundError();
    if (doc.topicId == newTopicId) return;
    final destDir = relDir(CourseLevel.topic, newTopicId);
    final newName = _uniqueFileName(destDir, p.posix.basename(doc.relPath));
    final newRel = '$destDir/$newName';
    final from = File(workspace.absolute(doc.relPath));
    final to = workspace.absolute(newRel);
    try {
      Directory(p.dirname(to)).createSync(recursive: true);
      if (from.existsSync()) from.renameSync(to);
    } on FileSystemException catch (e) {
      throw FileProblemError(e.message);
    }
    try {
      db.transaction(() {
        db.execute(
          'UPDATE documents SET topic_id = ?, rel_path = ?, position = ? '
          'WHERE id = ?',
          [
            newTopicId,
            newRel,
            _nextPosition('documents', 'topic_id', newTopicId),
            docId,
          ],
        );
      });
    } catch (_) {
      try {
        File(to).renameSync(from.path);
      } on FileSystemException {
        // voir _moveDir
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------ archives

  String _archiveTarget(String label) {
    final safeStamp = _stamp().replaceAll(':', '-').replaceAll('.', '-');
    return '${Workspace.archivesName}/${Workspace.coursName}/'
        '${safeStamp}_${safeFileName(label)}';
  }

  /// Supprime un élément : son dossier part dans `Archives/Cours/` et ses
  /// documents sont marqués archivés (rien n'est effacé du disque).
  void delete(CourseLevel level, int id) {
    final names = _names(level, id);
    final oldRel = relDir(level, id);
    final newRel = _archiveTarget(names.join(' - '));
    final undo = _moveDir(oldRel, newRel);
    try {
      db.transaction(() {
        _rewritePrefix(oldRel, newRel, archive: true);
        db.execute('DELETE FROM ${_tables[level]} WHERE id = ?', [id]);
      });
    } catch (_) {
      undo();
      rethrow;
    }
  }

  /// Archive un seul document.
  void archiveDocument(int docId) {
    final doc = document(docId);
    if (doc == null || doc.archivedAt != null) throw const NotFoundError();
    final destDir = '${Workspace.archivesName}/${Workspace.coursName}';
    final safeStamp = _stamp().replaceAll(':', '-').replaceAll('.', '-');
    final newRel =
        '$destDir/${safeStamp}_${safeFileName(p.posix.basename(doc.relPath))}';
    final from = File(workspace.absolute(doc.relPath));
    final to = workspace.absolute(newRel);
    try {
      Directory(p.dirname(to)).createSync(recursive: true);
      if (from.existsSync()) from.renameSync(to);
    } on FileSystemException catch (e) {
      throw FileProblemError(e.message);
    }
    db.transaction(() {
      db.execute(
        'UPDATE documents SET rel_path = ?, archived_at = ? WHERE id = ?',
        [newRel, _stamp(), docId],
      );
    });
  }

  /// Supprime définitivement un document (fichier compris).
  void deleteDocumentPermanently(int docId) {
    final doc = document(docId);
    if (doc == null) throw const NotFoundError();
    try {
      final f = File(workspace.absolute(doc.relPath));
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException catch (e) {
      throw FileProblemError(e.message);
    }
    db.transaction(() {
      db.execute('DELETE FROM documents WHERE id = ?', [docId]);
    });
  }

  // ----------------------------------------------------------- documents

  void renameDocument(int docId, String rawTitle) {
    final title = _cleanName(rawTitle);
    db.transaction(() {
      db.execute('UPDATE documents SET title = ? WHERE id = ?', [
        title,
        docId,
      ]);
    });
  }

  void markOpened(int docId) {
    db.transaction(() {
      db.execute('UPDATE documents SET last_opened_at = ? WHERE id = ?', [
        _stamp(),
        docId,
      ]);
    });
  }

  /// Coche ou décoche la lecture n° [index] (0 à 5).
  void setRead(int docId, int index, bool value) {
    if (index < 0 || index >= Doc.maxReads) {
      throw RangeError.range(index, 0, Doc.maxReads - 1, 'index');
    }
    db.transaction(() {
      final bit = 1 << index;
      db.execute(
        value
            ? 'UPDATE documents SET reads_mask = reads_mask | ? WHERE id = ?'
            : 'UPDATE documents SET reads_mask = reads_mask & ~? WHERE id = ?',
        [bit, docId],
      );
    });
  }

  void setPageCount(int docId, int pages) {
    db.transaction(() {
      db.execute('UPDATE documents SET page_count = ? WHERE id = ?', [
        pages,
        docId,
      ]);
    });
  }

  /// Nom de fichier libre dans [relDir] (ajoute « (2) », « (3) »… au besoin).
  String _uniqueFileName(String relDir, String wanted) {
    final safe = safeFileName(wanted);
    final stem = p.posix.basenameWithoutExtension(safe);
    final ext = p.posix.extension(safe);
    var candidate = safe;
    var n = 2;
    while (_fileTaken('$relDir/$candidate')) {
      candidate = '$stem ($n)$ext';
      n++;
    }
    return candidate;
  }

  bool _fileTaken(String rel) {
    if (File(workspace.absolute(rel)).existsSync()) return true;
    return db.select(
      'SELECT 1 FROM documents WHERE lower(rel_path) = lower(?)',
      [rel],
    ).isNotEmpty;
  }

  /// Copie [sourcePath] dans le dossier du thème. L'original n'est jamais
  /// modifié ni supprimé.
  Future<Doc> importFile(int topicId, String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw FileProblemError('Fichier introuvable : $sourcePath');
    }
    final destDir = relDir(CourseLevel.topic, topicId);
    final fileName = _uniqueFileName(destDir, p.basename(sourcePath));
    final rel = '$destDir/$fileName';
    final dest = File(workspace.absolute(rel));
    int size;
    try {
      dest.parent.createSync(recursive: true);
      await source.copy(dest.path);
      size = dest.lengthSync();
    } on FileSystemException catch (e) {
      throw FileProblemError(e.message);
    }
    final kind = docKindForExtension(p.extension(fileName));
    int? pages;
    if (kind == DocKind.pdf && pageCounter != null) {
      try {
        pages = await pageCounter!(dest.path);
      } catch (_) {
        pages = null; // fichier illisible : on garde le document quand même
      }
    }
    try {
      final id = db.transaction(() {
        db.execute(
          'INSERT INTO documents(topic_id, title, kind, rel_path, size_bytes, '
          'page_count, position, imported_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            topicId,
            p.basenameWithoutExtension(fileName),
            kind.name,
            rel,
            size,
            pages,
            _nextPosition('documents', 'topic_id', topicId),
            _stamp(),
          ],
        );
        return db.lastInsertId;
      });
      return document(id)!;
    } catch (_) {
      try {
        dest.deleteSync();
      } on FileSystemException {
        // la copie reste sur le disque, sans effet sur la base
      }
      rethrow;
    }
  }

  // ------------------------------------------------------- synchronisation

  bool _ignorable(String name) =>
      name.startsWith('.') ||
      name.startsWith('~\$') ||
      name.endsWith('.tmp') ||
      name.endsWith('.carabin-tmp') ||
      name == 'Thumbs.db' ||
      name == 'desktop.ini';

  List<FileSystemEntity> _children(String abs) {
    final d = Directory(abs);
    if (!d.existsSync()) return const [];
    return d.listSync(followLinks: false).where((e) {
      return !_ignorable(p.basename(e.path));
    }).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Relit `Cours/` : ajoute les dossiers et fichiers inconnus. Rien n'est
  /// jamais supprimé.
  SyncReport syncFolder({int defaultColor = 0xFF2F6FED}) {
    var added = 0;
    db.transaction(() {
      for (final yDir in _children(workspace.coursDir).whereType<Directory>()) {
        final yName = p.basename(yDir.path);
        final yearId = _findOrCreate(
          'years',
          null,
          null,
          yName,
          extra: const {},
        );
        for (final sDir in _children(yDir.path).whereType<Directory>()) {
          final sName = p.basename(sDir.path);
          final semId = _findOrCreate('semesters', 'year_id', yearId, sName);
          for (final mDir in _children(sDir.path).whereType<Directory>()) {
            final mName = p.basename(mDir.path);
            final subId = _findOrCreate(
              'subjects',
              'semester_id',
              semId,
              mName,
              extra: {'color': defaultColor},
            );
            for (final tDir in _children(mDir.path).whereType<Directory>()) {
              final tName = p.basename(tDir.path);
              final topicId = _findOrCreate('topics', 'subject_id', subId, tName);
              for (final f in _children(tDir.path).whereType<File>()) {
                final rel = workspace.relative(f.path);
                final known = db.select(
                  'SELECT 1 FROM documents WHERE lower(rel_path) = lower(?)',
                  [rel],
                );
                if (known.isNotEmpty) continue;
                final fileName = p.basename(f.path);
                db.execute(
                  'INSERT INTO documents(topic_id, title, kind, rel_path, '
                  'size_bytes, position, imported_at) '
                  'VALUES (?, ?, ?, ?, ?, ?, ?)',
                  [
                    topicId,
                    p.basenameWithoutExtension(fileName),
                    docKindForExtension(p.extension(fileName)).name,
                    rel,
                    f.lengthSync(),
                    _nextPosition('documents', 'topic_id', topicId),
                    _stamp(),
                  ],
                );
                added++;
              }
            }
          }
        }
      }
    });
    var missing = 0;
    for (final r in db.select(
      'SELECT rel_path FROM documents WHERE archived_at IS NULL',
    )) {
      if (!File(workspace.absolute(r['rel_path'] as String)).existsSync()) {
        missing++;
      }
    }
    return SyncReport(added: added, missing: missing);
  }

  /// Trouve (sans tenir compte de la casse) ou crée une ligne dont le dossier
  /// porte ce nom.
  int _findOrCreate(
    String table,
    String? parentColumn,
    int? parentId,
    String name, {
    Map<String, Object?> extra = const {},
  }) {
    final rows = parentColumn == null
        ? db.select('SELECT id, name FROM $table')
        : db.select(
            'SELECT id, name FROM $table WHERE $parentColumn = ?',
            [parentId],
          );
    for (final r in rows) {
      final other = r['name'] as String;
      if (other.toLowerCase() == name.toLowerCase() ||
          safeFileName(other).toLowerCase() == name.toLowerCase()) {
        return r['id'] as int;
      }
    }
    final cols = [?parentColumn, 'name', 'position'];
    final vals = <Object?>[
      if (parentColumn != null) parentId,
      name,
      _nextPosition(table, parentColumn, parentId),
    ];
    for (final e in extra.entries) {
      cols.add(e.key);
      vals.add(e.value);
    }
    db.execute(
      'INSERT INTO $table(${cols.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')})',
      vals,
    );
    return db.lastInsertId;
  }
}
