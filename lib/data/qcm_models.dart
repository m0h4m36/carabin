import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/qcm/exam.dart';
import '../domain/qcm/grading.dart';
import '../domain/qcm/question.dart';

/// Une épreuve (série de questions).
class ExamRow {
  const ExamRow({
    required this.id,
    required this.guid,
    required this.title,
    required this.subjectId,
    required this.documentId,
    required this.items,
    required this.pastPaper,
    required this.imported,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExamRow.fromRow(Row r) => ExamRow(
    id: r['id'] as int,
    guid: r['guid'] as String,
    title: r['title'] as String,
    subjectId: r['subject_id'] as int?,
    documentId: r['document_id'] as int?,
    items: r['items'] as String,
    pastPaper: (r['past_paper'] as int) == 1,
    imported: (r['imported'] as int) == 1,
    position: r['position'] as int,
    createdAt: r['created_at'] as int,
    updatedAt: r['updated_at'] as int,
  );

  final int id;
  final String guid;
  final String title;
  final int? subjectId;
  final int? documentId;

  /// Numéros d'items des EDN, tels que saisis.
  final String items;
  final bool pastPaper;

  /// Arrivée d'un camarade (fichier) plutôt qu'écrite ici.
  final bool imported;
  final int position;
  final int createdAt;
  final int updatedAt;

  /// Rangée dans les annales : au choix, ou parce que le titre le dit.
  bool get isPastPaper =>
      pastPaper || title.toLowerCase().contains(RegExp('annales?'));
}

/// Une épreuve avec ce qu'il faut pour sa carte.
class ExamSummary {
  const ExamSummary({
    required this.exam,
    required this.questions,
    required this.ready,
    required this.attempts,
    this.lastNote,
    this.lastAt,
  });

  final ExamRow exam;
  final int questions;
  final int ready;
  final int attempts;

  /// Dernière note sur 20, ou null si jamais passée.
  final double? lastNote;
  final int? lastAt;

  int get unfinished => questions - ready;
}

class CaseRow {
  const CaseRow({
    required this.id,
    required this.examId,
    required this.info,
    required this.position,
  });

  final int id;
  final int examId;
  final CaseInfo info;
  final int position;
}

class QuestionRow {
  const QuestionRow({
    required this.id,
    required this.examId,
    required this.caseId,
    required this.position,
    required this.question,
    required this.ready,
  });

  final int id;
  final int examId;
  final int? caseId;
  final int position;
  final Question question;
  final bool ready;
}

/// Un bloc de l'épreuve : question isolée ou cas avec ses questions.
sealed class UnitRow {
  const UnitRow();
  List<QuestionRow> get questions;
}

class SingleUnit extends UnitRow {
  const SingleUnit(this.question);
  final QuestionRow question;

  @override
  List<QuestionRow> get questions => [question];
}

class CaseUnit extends UnitRow {
  const CaseUnit(this.kase, this.questions);
  final CaseRow kase;

  @override
  final List<QuestionRow> questions;
}

/// Contenu complet d'une épreuve.
class ExamContent {
  const ExamContent(this.exam, this.units);

  final ExamRow exam;
  final List<UnitRow> units;

  List<QuestionRow> get questions => [for (final u in units) ...u.questions];
  int get readyCount => questions.where((q) => q.ready).length;
}

/// Question, avec son cas et d'où elle vient, telle qu'elle a été posée.
class AnswerDraft {
  const AnswerDraft({
    required this.question,
    required this.grade,
    this.info,
    this.caseGroup = -1,
    this.order = const [],
    this.answer,
    this.doubt = false,
    this.subjectId,
    this.topicId,
    this.examId,
  });

  final Question question;
  final CaseInfo? info;
  final int caseGroup;
  final List<int> order;
  final Answer? answer;
  final Grade grade;
  final bool doubt;
  final int? subjectId;
  final int? topicId;
  final int? examId;
}

/// Copie à enregistrer.
class AttemptDraft {
  const AttemptDraft({
    required this.title,
    required this.settings,
    required this.startedAt,
    required this.duration,
    required this.answers,
    this.examId,
    this.practice = false,
    this.handwritten = true,
    this.timedOut = false,
    this.examTotal,
  });

  final String title;
  final int? examId;

  /// Entraînement : plusieurs épreuves, ou une partie d'une seule.
  final bool practice;
  final bool handwritten;
  final PassageSettings settings;
  final DateTime startedAt;
  final Duration duration;
  final bool timedOut;

  /// Nombre de questions prêtes de l'épreuve (pour la part d'un
  /// entraînement), ou null s'il y a plusieurs épreuves.
  final int? examTotal;
  final List<AnswerDraft> answers;
}

/// Une copie rendue (sans le détail des questions).
class AttemptRow {
  const AttemptRow({
    required this.id,
    required this.examId,
    required this.title,
    required this.practice,
    required this.handwritten,
    required this.settings,
    required this.startedAt,
    required this.duration,
    required this.timedOut,
    required this.score,
    required this.max,
    required this.questionCount,
    required this.examTotal,
  });

  factory AttemptRow.fromRow(Row r) => AttemptRow(
    id: r['id'] as int,
    examId: r['exam_id'] as int?,
    title: r['title'] as String,
    practice: (r['practice'] as int) == 1,
    handwritten: (r['handwritten'] as int) == 1,
    settings: PassageSettings.fromJson(_decode(r['settings_json'] as String)),
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      r['started_at'] as int,
      isUtc: true,
    ).toLocal(),
    duration: Duration(milliseconds: r['duration_ms'] as int),
    timedOut: (r['timed_out'] as int) == 1,
    score: (r['score'] as num).toDouble(),
    max: (r['max_score'] as num).toDouble(),
    questionCount: r['question_count'] as int,
    examTotal: r['exam_total'] as int?,
  );

  final int id;

  /// Épreuve passée, ou null (entraînement sur plusieurs épreuves, épreuve
  /// supprimée depuis).
  final int? examId;
  final String title;
  final bool practice;
  final bool handwritten;
  final PassageSettings settings;
  final DateTime startedAt;
  final Duration duration;
  final bool timedOut;
  final double score;
  final double max;
  final int questionCount;
  final int? examTotal;

  double get note => max <= 0 ? 0 : (score / max * 20 * 1e6).round() / 1e6;

  /// Part de l'épreuve couverte (entraînement sur une seule épreuve).
  double? get part {
    final t = examTotal;
    if (t == null || t <= 0) return null;
    return (questionCount / t).clamp(0.0, 1.0);
  }
}

Object? _decode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Une question d'une copie.
class AnswerRow {
  const AnswerRow({
    required this.id,
    required this.attemptId,
    required this.position,
    required this.question,
    required this.info,
    required this.caseGroup,
    required this.order,
    required this.answer,
    required this.verdict,
    required this.score,
    required this.max,
    required this.doubt,
    required this.subjectId,
    required this.topicId,
    required this.examId,
    required this.notebook,
  });

  factory AnswerRow.fromRow(Row r) {
    final q = decodeQuestion(r['question_json'] as String);
    final caseJson = r['case_json'] as String?;
    CaseInfo? info;
    if (caseJson != null) {
      try {
        info = CaseInfo.fromJson(jsonDecode(caseJson));
      } on FormatException {
        info = null;
      }
    }
    final order = _decode(r['order_json'] as String);
    final answerJson = r['answer_json'] as String?;
    return AnswerRow(
      id: r['id'] as int,
      attemptId: r['attempt_id'] as int,
      position: r['position'] as int,
      question: q,
      info: info,
      caseGroup: r['case_group'] as int,
      order: order is List
          ? [
              for (final i in order)
                if (i is int) i,
            ]
          : const [],
      answer: answerJson == null
          ? null
          : Answer.fromJson(q.kind, _decode(answerJson)),
      verdict: Verdict.values.firstWhere(
        (v) => v.name == r['verdict'],
        orElse: () => Verdict.skipped,
      ),
      score: (r['score'] as num).toDouble(),
      max: (r['max_score'] as num).toDouble(),
      doubt: (r['doubt'] as int) == 1,
      subjectId: r['subject_id'] as int?,
      topicId: r['topic_id'] as int?,
      examId: r['exam_id'] as int?,
      notebook: (r['notebook'] as int) == 1,
    );
  }

  final int id;
  final int attemptId;
  final int position;
  final Question question;
  final CaseInfo? info;
  final int caseGroup;

  /// Ordre dans lequel les propositions ont été montrées.
  final List<int> order;
  final Answer? answer;
  final Verdict verdict;
  final double score;
  final double max;
  final bool doubt;
  final int? subjectId;
  final int? topicId;
  final int? examId;

  /// Envoyée au carnet d'erreurs.
  final bool notebook;
}

/// Question lue dans la base ; une question illisible devient une question
/// vide plutôt que de bloquer tout l'écran.
Question decodeQuestion(String json) {
  try {
    return Question.fromJson(jsonDecode(json));
  } on FormatException {
    return const ChoiceQuestion(body: '(question illisible)');
  }
}

class AttemptDetail {
  const AttemptDetail(this.attempt, this.answers);
  final AttemptRow attempt;
  final List<AnswerRow> answers;

  Totals get totals =>
      Totals.of([for (final a in answers) Grade(a.score, a.max, a.verdict)]);
}

/// Résultats regroupés (matière ou thème) pour « Où je chute ».
class WeakSpot {
  const WeakSpot({
    required this.id,
    required this.score,
    required this.max,
    required this.right,
    required this.total,
  });

  /// Matière ou thème ; null = non rangé.
  final int? id;
  final double score;
  final double max;
  final int right;
  final int total;

  double get ratio => max <= 0 ? 0 : score / max;
}
