import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart' show Row;

import '../domain/qcm/exam.dart';
import '../domain/qcm/exam_file.dart';
import '../domain/qcm/grading.dart';
import '../domain/qcm/question.dart';
import 'database.dart';
import 'errors.dart';
import 'qcm_models.dart';
import 'settings_repository.dart';

/// Épreuves, cas, questions et copies.
class QcmRepository {
  QcmRepository(
    this.db,
    this.settings, {
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final AppDatabase db;
  final SettingsRepository settings;
  final DateTime Function() _clock;
  final Random _random;

  static const passageSettingsKey = 'qcm.reglages';

  int _nowMs() => _clock().toUtc().millisecondsSinceEpoch;

  // ------------------------------------------------------------- réglages

  /// Réglages du passage mémorisés (valables pour toutes les épreuves
  /// jusqu'à changement). « Une partie seulement » n'est jamais mémorisée.
  PassageSettings passageSettings() {
    final text = settings.get(passageSettingsKey);
    if (text == null) return const PassageSettings();
    try {
      return PassageSettings.fromJson(jsonDecode(text));
    } on FormatException {
      return const PassageSettings();
    }
  }

  void setPassageSettings(PassageSettings s) {
    settings.set(
      passageSettingsKey,
      jsonEncode(s.copyWith(part: false, random: false).toJson()),
    );
  }

  // --------------------------------------------------------------- épreuves

  String _newGuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  String _cleanTitle(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) throw const EmptyNameError();
    return t.length > 200 ? t.substring(0, 200).trimRight() : t;
  }

  ExamRow exam(int id) {
    final rows = db.select('SELECT * FROM exams WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return ExamRow.fromRow(rows.first);
  }

  ExamRow? examByGuid(String guid) {
    final rows = db.select('SELECT * FROM exams WHERE guid = ?', [guid]);
    return rows.isEmpty ? null : ExamRow.fromRow(rows.first);
  }

  /// Toutes les épreuves, dans l'ordre de la liste.
  List<ExamSummary> exams() {
    final rows = db.select('''
SELECT e.*,
  (SELECT COUNT(*) FROM exam_questions q WHERE q.exam_id = e.id) AS n,
  (SELECT COUNT(*) FROM exam_questions q
     WHERE q.exam_id = e.id AND q.ready = 1) AS r,
  (SELECT COUNT(*) FROM attempts a WHERE a.exam_id = e.id) AS tries,
  (SELECT CASE WHEN a.max_score > 0 THEN a.score / a.max_score * 20 ELSE 0 END
     FROM attempts a WHERE a.exam_id = e.id
     ORDER BY a.started_at DESC, a.id DESC LIMIT 1) AS last_note,
  (SELECT a.started_at FROM attempts a WHERE a.exam_id = e.id
     ORDER BY a.started_at DESC, a.id DESC LIMIT 1) AS last_at
FROM exams e
ORDER BY e.position, e.id
''');
    return [
      for (final r in rows)
        ExamSummary(
          exam: ExamRow.fromRow(r),
          questions: r['n'] as int,
          ready: r['r'] as int,
          attempts: r['tries'] as int,
          lastNote: (r['last_note'] as num?)?.toDouble(),
          lastAt: r['last_at'] as int?,
        ),
    ];
  }

  ExamRow createExam(
    String rawTitle, {
    int? subjectId,
    bool pastPaper = false,
    bool imported = false,
    String? guid,
    String items = '',
    int? documentId,
  }) {
    final title = _cleanTitle(rawTitle);
    final id = db.transaction(() {
      final pos =
          db
                  .select(
                    'SELECT COALESCE(MAX(position), -1) + 1 AS n FROM exams',
                  )
                  .first['n']
              as int;
      final now = _nowMs();
      db.execute(
        'INSERT INTO exams(guid, title, subject_id, document_id, items, '
        'past_paper, imported, position, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          guid ?? _newGuid(),
          title,
          subjectId,
          documentId,
          items,
          pastPaper ? 1 : 0,
          imported ? 1 : 0,
          pos,
          now,
          now,
        ],
      );
      return db.lastInsertId;
    });
    return exam(id);
  }

  void _touch(int examId) => db.execute(
    'UPDATE exams SET updated_at = ? WHERE id = ?',
    [_nowMs(), examId],
  );

  void renameExam(int id, String rawTitle) {
    final title = _cleanTitle(rawTitle);
    exam(id);
    db.transaction(() {
      db.execute('UPDATE exams SET title = ? WHERE id = ?', [title, id]);
      _touch(id);
    });
  }

  void setExamSubject(Iterable<int> ids, int? subjectId) {
    db.transaction(() {
      for (final id in ids) {
        db.execute('UPDATE exams SET subject_id = ? WHERE id = ?', [
          subjectId,
          id,
        ]);
        _touch(id);
      }
    });
  }

  void setPastPaper(Iterable<int> ids, bool value) {
    db.transaction(() {
      for (final id in ids) {
        db.execute('UPDATE exams SET past_paper = ? WHERE id = ?', [
          value ? 1 : 0,
          id,
        ]);
        _touch(id);
      }
    });
  }

  void setExamDocument(int id, int? documentId) {
    db.transaction(() {
      db.execute('UPDATE exams SET document_id = ? WHERE id = ?', [
        documentId,
        id,
      ]);
      _touch(id);
    });
  }

  void setExamItems(int id, String items) {
    final t = items.trim();
    db.transaction(() {
      db.execute('UPDATE exams SET items = ? WHERE id = ?', [
        t.length > 500 ? t.substring(0, 500) : t,
        id,
      ]);
      _touch(id);
    });
  }

  void deleteExams(Iterable<int> ids) {
    db.transaction(() {
      for (final id in ids) {
        db.execute('DELETE FROM exams WHERE id = ?', [id]);
      }
    });
  }

  /// Copie une épreuve (cas et questions compris) sous un nouveau titre.
  ExamRow duplicateExam(int id, {required String title}) {
    final src = content(id);
    final copy = createExam(
      title,
      subjectId: src.exam.subjectId,
      pastPaper: src.exam.pastPaper,
      items: src.exam.items,
      documentId: src.exam.documentId,
    );
    db.transaction(() {
      for (final u in src.units) {
        switch (u) {
          case SingleUnit(:final question):
            addQuestion(copy.id, question.question);
          case CaseUnit(:final kase, :final questions):
            final c = addCase(copy.id, kase.info);
            for (final q in questions) {
              addQuestion(copy.id, q.question, caseId: c.id);
            }
        }
      }
    });
    return exam(copy.id);
  }

  /// Enregistre une épreuve venue d'un fichier. Si [replaceExamId] est
  /// donné, son contenu est remplacé (ses copies sont conservées) ; sinon une
  /// nouvelle épreuve est créée, avec un nouvel identifiant si celui du
  /// fichier existe déjà.
  int saveDoc(ExamDoc doc, {int? subjectId, int? replaceExamId}) {
    return db.transaction(() {
      final int examId;
      if (replaceExamId != null) {
        exam(replaceExamId);
        examId = replaceExamId;
        db.execute('DELETE FROM exam_questions WHERE exam_id = ?', [examId]);
        db.execute('DELETE FROM exam_cases WHERE exam_id = ?', [examId]);
        db.execute(
          'UPDATE exams SET title = ?, subject_id = COALESCE(?, subject_id), items = ?, '
          'past_paper = ? WHERE id = ?',
          [
            _cleanTitle(doc.title),
            subjectId,
            doc.items,
            doc.pastPaper ? 1 : 0,
            examId,
          ],
        );
        _touch(examId);
      } else {
        examId = createExam(
          doc.title,
          subjectId: subjectId,
          pastPaper: doc.pastPaper,
          imported: true,
          items: doc.items,
          guid: examByGuid(doc.guid) == null ? doc.guid : null,
        ).id;
      }
      for (final u in doc.units) {
        final info = u.info;
        final int? caseId = info == null ? null : addCase(examId, info).id;
        for (final q in u.questions) {
          addQuestion(examId, q, caseId: caseId);
        }
      }
      return examId;
    });
  }

  // --------------------------------------------------------------- contenu

  ExamContent content(int examId) {
    final e = exam(examId);
    final cases = {
      for (final r in db.select('SELECT * FROM exam_cases WHERE exam_id = ?', [
        examId,
      ]))
        r['id'] as int: _caseRow(r),
    };
    final standalone = <QuestionRow>[];
    final inCase = <int, List<QuestionRow>>{};
    for (final r in db.select(
      'SELECT * FROM exam_questions WHERE exam_id = ? ORDER BY position, id',
      [examId],
    )) {
      final q = _questionRow(r);
      final c = q.caseId;
      if (c == null) {
        standalone.add(q);
      } else {
        (inCase[c] ??= []).add(q);
      }
    }
    final units = <(int, int, UnitRow)>[];
    for (final q in standalone) {
      units.add((q.position, 0, SingleUnit(q)));
    }
    for (final c in cases.values) {
      units.add((c.position, 1, CaseUnit(c, inCase[c.id] ?? const [])));
    }
    units.sort((a, b) {
      final p = a.$1.compareTo(b.$1);
      if (p != 0) return p;
      return a.$2.compareTo(b.$2);
    });
    return ExamContent(e, [for (final u in units) u.$3]);
  }

  CaseRow _caseRow(Row row) => CaseRow(
    id: row['id'] as int,
    examId: row['exam_id'] as int,
    position: row['position'] as int,
    info: CaseInfo(
      genre: caseGenreOf(row['genre']),
      title: row['title'] as String,
      context: row['context'] as String,
      articleText: row['article_text'] as String,
      articleFile: row['article_file'] as String,
    ),
  );

  QuestionRow _questionRow(Row row) => QuestionRow(
    id: row['id'] as int,
    examId: row['exam_id'] as int,
    caseId: row['case_id'] as int?,
    position: row['position'] as int,
    question: decodeQuestion(row['data_json'] as String),
    ready: (row['ready'] as int) == 1,
  );

  QuestionRow question(int id) {
    final rows = db.select('SELECT * FROM exam_questions WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return _questionRow(rows.first);
  }

  CaseRow caseRow(int id) {
    final rows = db.select('SELECT * FROM exam_cases WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return _caseRow(rows.first);
  }

  // ------------------------------------------------------ ordre des blocs

  List<(bool, int)> _unitKeys(int examId) {
    final rows = db.select(
      '''
SELECT is_case, id, position FROM (
  SELECT 1 AS is_case, id, position FROM exam_cases WHERE exam_id = ?
  UNION ALL
  SELECT 0 AS is_case, id, position FROM exam_questions
    WHERE exam_id = ? AND case_id IS NULL
) ORDER BY position, is_case DESC, id
''',
      [examId, examId],
    );
    return [for (final r in rows) ((r['is_case'] as int) == 1, r['id'] as int)];
  }

  void _writeUnitKeys(List<(bool, int)> keys) {
    for (var i = 0; i < keys.length; i++) {
      final (isCase, id) = keys[i];
      db.execute(
        'UPDATE ${isCase ? 'exam_cases' : 'exam_questions'} '
        'SET position = ? WHERE id = ?',
        [i, id],
      );
    }
  }

  List<int> _members(int caseId) => [
    for (final r in db.select(
      'SELECT id FROM exam_questions WHERE case_id = ? ORDER BY position, id',
      [caseId],
    ))
      r['id'] as int,
  ];

  void _writeMembers(List<int> ids) {
    for (var i = 0; i < ids.length; i++) {
      db.execute('UPDATE exam_questions SET position = ? WHERE id = ?', [
        i,
        ids[i],
      ]);
    }
  }

  int _nextUnitPosition(int examId) =>
      db
              .select(
                '''
SELECT COALESCE(MAX(p), -1) + 1 AS n FROM (
  SELECT position AS p FROM exam_cases WHERE exam_id = ?
  UNION ALL
  SELECT position AS p FROM exam_questions
    WHERE exam_id = ? AND case_id IS NULL
)
''',
                [examId, examId],
              )
              .first['n']
          as int;

  // -------------------------------------------------------------- questions

  int addQuestion(int examId, Question question, {int? caseId}) {
    exam(examId);
    return db.transaction(() {
      final int pos;
      if (caseId != null) {
        final c = caseRow(caseId);
        if (c.examId != examId) throw const NotFoundError();
        pos =
            db.select(
                  'SELECT COALESCE(MAX(position), -1) + 1 AS n '
                  'FROM exam_questions WHERE case_id = ?',
                  [caseId],
                ).first['n']
                as int;
      } else {
        pos = _nextUnitPosition(examId);
      }
      db.execute(
        'INSERT INTO exam_questions(exam_id, case_id, position, kind, '
        'data_json, ready) VALUES (?, ?, ?, ?, ?, ?)',
        [
          examId,
          caseId,
          pos,
          question.kind.name,
          jsonEncode(question.toJson()),
          question.isReady ? 1 : 0,
        ],
      );
      final id = db.lastInsertId;
      _touch(examId);
      return id;
    });
  }

  void updateQuestion(int id, Question updated) {
    final row = question(id);
    db.transaction(() {
      db.execute(
        'UPDATE exam_questions SET kind = ?, data_json = ?, ready = ? '
        'WHERE id = ?',
        [
          updated.kind.name,
          jsonEncode(updated.toJson()),
          updated.isReady ? 1 : 0,
          id,
        ],
      );
      _touch(row.examId);
    });
  }

  void deleteQuestion(int id) {
    final row = question(id);
    db.transaction(() {
      db.execute('DELETE FROM exam_questions WHERE id = ?', [id]);
      final c = row.caseId;
      if (c != null) {
        _writeMembers(_members(c));
      } else {
        _writeUnitKeys(_unitKeys(row.examId));
      }
      _touch(row.examId);
    });
  }

  /// Duplique une question juste après elle (dans son cas, le cas échéant).
  int duplicateQuestion(int id) {
    final row = question(id);
    return db.transaction(() {
      final newId = addQuestion(row.examId, row.question, caseId: row.caseId);
      final c = row.caseId;
      if (c != null) {
        final ids = _members(c)..remove(newId);
        ids.insert(ids.indexOf(id) + 1, newId);
        _writeMembers(ids);
      } else {
        final keys = _unitKeys(row.examId)..remove((false, newId));
        keys.insert(keys.indexOf((false, id)) + 1, (false, newId));
        _writeUnitKeys(keys);
      }
      return newId;
    });
  }

  /// Monte ([delta] = −1) ou descend (+1) une question dans sa liste.
  void moveQuestion(int id, int delta) {
    final row = question(id);
    db.transaction(() {
      final c = row.caseId;
      if (c != null) {
        final ids = _members(c);
        final from = ids.indexOf(id);
        final to = from + delta;
        if (to < 0 || to >= ids.length) return;
        ids.removeAt(from);
        ids.insert(to, id);
        _writeMembers(ids);
      } else {
        _moveUnit(row.examId, (false, id), delta);
      }
      _touch(row.examId);
    });
  }

  void moveCase(int id, int delta) {
    final c = caseRow(id);
    db.transaction(() {
      _moveUnit(c.examId, (true, id), delta);
      _touch(c.examId);
    });
  }

  void _moveUnit(int examId, (bool, int) key, int delta) {
    final keys = _unitKeys(examId);
    final from = keys.indexOf(key);
    if (from < 0) return;
    final to = from + delta;
    if (to < 0 || to >= keys.length) return;
    keys.removeAt(from);
    keys.insert(to, key);
    _writeUnitKeys(keys);
  }

  /// Range une question dans un cas, ou la remet isolée (juste après le cas
  /// qu'elle quitte).
  void setQuestionCase(int id, int? caseId) {
    final row = question(id);
    if (row.caseId == caseId) return;
    db.transaction(() {
      if (caseId != null) {
        final c = caseRow(caseId);
        if (c.examId != row.examId) throw const NotFoundError();
        final next =
            db.select(
                  'SELECT COALESCE(MAX(position), -1) + 1 AS n '
                  'FROM exam_questions WHERE case_id = ?',
                  [caseId],
                ).first['n']
                as int;
        final old = row.caseId;
        db.execute(
          'UPDATE exam_questions SET case_id = ?, position = ? WHERE id = ?',
          [caseId, next, id],
        );
        if (old != null) {
          _writeMembers(_members(old));
        } else {
          _writeUnitKeys(_unitKeys(row.examId));
        }
      } else {
        final old = row.caseId!;
        final keys = _unitKeys(row.examId);
        final at = keys.indexOf((true, old));
        db.execute(
          'UPDATE exam_questions SET case_id = NULL, position = ? WHERE id = ?',
          [-1, id],
        );
        keys.insert(at < 0 ? keys.length : at + 1, (false, id));
        _writeUnitKeys(keys);
        _writeMembers(_members(old));
      }
      _touch(row.examId);
    });
  }

  // -------------------------------------------------------------------- cas

  CaseRow addCase(int examId, CaseInfo info) {
    exam(examId);
    final id = db.transaction(() {
      db.execute(
        'INSERT INTO exam_cases(exam_id, genre, title, context, '
        'article_text, article_file, position) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          examId,
          info.genre.name,
          info.title,
          info.context,
          info.articleText,
          info.articleFile,
          _nextUnitPosition(examId),
        ],
      );
      final id = db.lastInsertId;
      _touch(examId);
      return id;
    });
    return caseRow(id);
  }

  void updateCase(int id, CaseInfo info) {
    final c = caseRow(id);
    db.transaction(() {
      db.execute(
        'UPDATE exam_cases SET genre = ?, title = ?, context = ?, '
        'article_text = ?, article_file = ? WHERE id = ?',
        [
          info.genre.name,
          info.title,
          info.context,
          info.articleText,
          info.articleFile,
          id,
        ],
      );
      _touch(c.examId);
    });
  }

  /// Supprime un cas et ses questions.
  void deleteCase(int id) {
    final c = caseRow(id);
    db.transaction(() {
      db.execute('DELETE FROM exam_cases WHERE id = ?', [id]);
      _writeUnitKeys(_unitKeys(c.examId));
      _touch(c.examId);
    });
  }

  /// Mélange l'ordre des blocs (un cas reste entier et dans son ordre).
  void shuffleUnits(int examId, Random random) {
    db.transaction(() {
      final keys = _unitKeys(examId)..shuffle(random);
      _writeUnitKeys(keys);
      _touch(examId);
    });
  }

  // --------------------------------------------------- questions à poser

  /// Blocs d'une ou plusieurs épreuves, prêts pour [planSession].
  List<SourceUnit> sourceUnits(Iterable<int> examIds) {
    final out = <SourceUnit>[];
    for (final examId in examIds) {
      final c = content(examId);
      final topicId = _topicOf(c.exam.documentId);
      final subjectId = c.exam.subjectId ?? _subjectOfTopic(topicId);
      SourceQuestion src(QuestionRow q) => SourceQuestion(
        question: q.question,
        examId: examId,
        questionId: q.id,
        subjectId: subjectId,
        topicId: topicId,
      );
      for (final u in c.units) {
        switch (u) {
          case SingleUnit(:final question):
            out.add(SourceUnit([src(question)]));
          case CaseUnit(:final kase, :final questions):
            out.add(
              SourceUnit([for (final q in questions) src(q)], info: kase.info),
            );
        }
      }
    }
    return out;
  }

  int? _topicOf(int? documentId) {
    if (documentId == null) return null;
    final rows = db.select('SELECT topic_id FROM documents WHERE id = ?', [
      documentId,
    ]);
    return rows.isEmpty ? null : rows.first['topic_id'] as int?;
  }

  int? _subjectOfTopic(int? topicId) {
    if (topicId == null) return null;
    final rows = db.select('SELECT subject_id FROM topics WHERE id = ?', [
      topicId,
    ]);
    return rows.isEmpty ? null : rows.first['subject_id'] as int?;
  }

  /// Épreuve proposée par « Prochaine épreuve » : la première jamais passée
  /// (dans l'ordre de la liste), sinon celle passée il y a le plus longtemps.
  ///
  /// [except] écarte une épreuve (celle qu'on vient de passer).
  ExamSummary? nextExam({int? except}) {
    final list = [
      for (final s in exams())
        if (s.ready > 0 && s.exam.id != except) s,
    ];
    if (list.isEmpty) return null;
    for (final s in list) {
      if (s.attempts == 0) return s;
    }
    list.sort((a, b) => (a.lastAt ?? 0).compareTo(b.lastAt ?? 0));
    return list.first;
  }

  // ----------------------------------------------------------------- copies

  int saveAttempt(AttemptDraft d) {
    final totals = Totals.of([for (final a in d.answers) a.grade]);
    return db.transaction(() {
      db.execute(
        'INSERT INTO attempts(exam_id, title, practice, handwritten, scoring, '
        'correction, settings_json, started_at, duration_ms, timed_out, '
        'score, max_score, question_count, exam_total) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          d.examId,
          d.title,
          d.practice ? 1 : 0,
          d.handwritten ? 1 : 0,
          d.settings.scoring.name,
          d.settings.correction.name,
          jsonEncode(d.settings.toJson()),
          d.startedAt.toUtc().millisecondsSinceEpoch,
          d.duration.inMilliseconds,
          d.timedOut ? 1 : 0,
          totals.score,
          totals.max,
          d.answers.length,
          d.examTotal,
        ],
      );
      final attemptId = db.lastInsertId;
      for (var i = 0; i < d.answers.length; i++) {
        final a = d.answers[i];
        db.execute(
          'INSERT INTO attempt_answers(attempt_id, position, question_json, '
          'case_json, case_group, order_json, answer_json, verdict, score, '
          'max_score, doubt, subject_id, topic_id, exam_id) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            attemptId,
            i,
            jsonEncode(a.question.toJson()),
            a.info == null ? null : jsonEncode(a.info!.toJson()),
            a.caseGroup,
            jsonEncode(a.order),
            a.answer == null ? null : jsonEncode(a.answer!.toJson()),
            a.grade.verdict.name,
            a.grade.score,
            a.grade.max,
            a.doubt ? 1 : 0,
            a.subjectId,
            a.topicId,
            a.examId,
          ],
        );
      }
      return attemptId;
    });
  }

  AttemptRow attemptRow(int id) {
    final rows = db.select('SELECT * FROM attempts WHERE id = ?', [id]);
    if (rows.isEmpty) throw const NotFoundError();
    return AttemptRow.fromRow(rows.first);
  }

  AttemptDetail attempt(int id) {
    final a = attemptRow(id);
    final rows = db.select(
      'SELECT * FROM attempt_answers WHERE attempt_id = ? ORDER BY position',
      [id],
    );
    return AttemptDetail(a, [for (final r in rows) AnswerRow.fromRow(r)]);
  }

  /// Copies rendues, de la plus récente à la plus ancienne.
  List<AttemptRow> attempts({bool? practice}) {
    final rows = db.select(
      'SELECT * FROM attempts '
      '${practice == null ? '' : 'WHERE practice = ${practice ? 1 : 0}'} '
      'ORDER BY started_at DESC, id DESC',
    );
    return [for (final r in rows) AttemptRow.fromRow(r)];
  }

  void deleteAttempt(int id) {
    db.transaction(() => db.execute('DELETE FROM attempts WHERE id = ?', [id]));
  }

  /// Auto-évaluation d'un QROC sans éléments attendus (0, 0,5 ou 1, ou null
  /// pour l'effacer) ; la note de la copie est recalculée.
  void setSelfScore(int answerId, double? self) {
    final rows = db.select('SELECT * FROM attempt_answers WHERE id = ?', [
      answerId,
    ]);
    if (rows.isEmpty) throw const NotFoundError();
    final a = AnswerRow.fromRow(rows.first);
    final q = a.question;
    final current = a.answer;
    if (q is! QrocQuestion || q.autoGraded || current is! TextAnswer) return;
    if (self != null && self != 0 && self != 0.5 && self != 1) {
      throw ArgumentError.value(self, 'self');
    }
    final scoring = attemptRow(a.attemptId).settings.scoring;
    final next = current.withSelf(self);
    final grade = gradeQuestion(q, next, scoring);
    db.transaction(() {
      db.execute(
        'UPDATE attempt_answers SET answer_json = ?, verdict = ?, score = ? '
        'WHERE id = ?',
        [jsonEncode(next.toJson()), grade.verdict.name, grade.score, answerId],
      );
      db.execute(
        'UPDATE attempts SET score = (SELECT COALESCE(SUM(score), 0) '
        'FROM attempt_answers WHERE attempt_id = ?) WHERE id = ?',
        [a.attemptId, a.attemptId],
      );
    });
  }

  /// Résultats par matière ou par thème, tous passages confondus (ou
  /// seulement les épreuves / les entraînements).
  List<WeakSpot> weakSpots({required bool byTopic, bool? practice}) {
    final col = byTopic ? 'aa.topic_id' : 'aa.subject_id';
    final where = practice == null
        ? ''
        : 'WHERE a.practice = ${practice ? 1 : 0}';
    final rows = db.select('''
SELECT $col AS k, SUM(aa.score) AS s, SUM(aa.max_score) AS m,
  SUM(CASE WHEN aa.verdict = 'right' THEN 1 ELSE 0 END) AS r,
  COUNT(*) AS n
FROM attempt_answers aa JOIN attempts a ON a.id = aa.attempt_id
$where
GROUP BY $col
''');
    final out = [
      for (final r in rows)
        WeakSpot(
          id: r['k'] as int?,
          score: (r['s'] as num).toDouble(),
          max: (r['m'] as num).toDouble(),
          right: r['r'] as int,
          total: r['n'] as int,
        ),
    ];
    out.sort((a, b) => a.ratio.compareTo(b.ratio));
    return out;
  }

  // ------------------------------------------------------------------ médias

  /// Médias cités par les épreuves et les copies (pour ne pas les effacer).
  Set<String> referencedMedia() {
    final names = <String>{};
    for (final r in db.select('SELECT data_json FROM exam_questions')) {
      names.addAll(decodeQuestion(r['data_json'] as String).mediaNames);
    }
    for (final r in db.select('SELECT question_json FROM attempt_answers')) {
      names.addAll(decodeQuestion(r['question_json'] as String).mediaNames);
    }
    for (final r in db.select(
      "SELECT article_file FROM exam_cases WHERE article_file != ''",
    )) {
      names.add(r['article_file'] as String);
    }
    for (final r in db.select(
      'SELECT case_json FROM attempt_answers WHERE case_json IS NOT NULL',
    )) {
      try {
        final f = CaseInfo.fromJson(jsonDecode(r['case_json'] as String));
        if (f.articleFile.isNotEmpty) names.add(f.articleFile);
      } on FormatException {
        // cas illisible : rien à garder
      }
    }
    return names;
  }

  /// Contenu d'une épreuve indépendant de la base (partage, copie).
  ExamDoc toDoc(int examId, {required String subjectName}) {
    final c = content(examId);
    return ExamDoc(
      guid: c.exam.guid,
      title: c.exam.title,
      subjectName: subjectName,
      items: c.exam.items,
      pastPaper: c.exam.pastPaper,
      units: [
        for (final u in c.units)
          if (u.questions.isNotEmpty)
            switch (u) {
              SingleUnit(:final question) => ExamUnitDoc([question.question]),
              CaseUnit(:final kase, :final questions) => ExamUnitDoc([
                for (final q in questions) q.question,
              ], info: kase.info),
            },
      ],
    );
  }
}
