import 'package:sqlite3/sqlite3.dart';

class Year {
  const Year({required this.id, required this.name, required this.position});
  factory Year.fromRow(Row r) => Year(
        id: r['id'] as int,
        name: r['name'] as String,
        position: r['position'] as int,
      );
  final int id;
  final String name;
  final int position;
}

class Semester {
  const Semester({
    required this.id,
    required this.yearId,
    required this.name,
    required this.position,
  });
  factory Semester.fromRow(Row r) => Semester(
        id: r['id'] as int,
        yearId: r['year_id'] as int,
        name: r['name'] as String,
        position: r['position'] as int,
      );
  final int id;
  final int yearId;
  final String name;
  final int position;
}

class Subject {
  const Subject({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.color,
    required this.position,
    this.examDate,
  });
  factory Subject.fromRow(Row r) => Subject(
        id: r['id'] as int,
        semesterId: r['semester_id'] as int,
        name: r['name'] as String,
        color: r['color'] as int,
        position: r['position'] as int,
        examDate: r['exam_date'] as String?,
      );
  final int id;
  final int semesterId;
  final String name;

  /// Couleur ARGB (entier 0xAARRGGBB).
  final int color;
  final int position;

  /// Date d'examen au format AAAA-MM-JJ, ou null.
  final String? examDate;
}

class Topic {
  const Topic({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.position,
  });
  factory Topic.fromRow(Row r) => Topic(
        id: r['id'] as int,
        subjectId: r['subject_id'] as int,
        name: r['name'] as String,
        position: r['position'] as int,
      );
  final int id;
  final int subjectId;
  final String name;
  final int position;
}

enum DocKind { pdf, word, image, text, other }

DocKind docKindForExtension(String ext) {
  switch (ext.toLowerCase().replaceFirst('.', '')) {
    case 'pdf':
      return DocKind.pdf;
    case 'doc':
    case 'docx':
    case 'odt':
      return DocKind.word;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
      return DocKind.image;
    case 'txt':
    case 'md':
      return DocKind.text;
    default:
      return DocKind.other;
  }
}

class Doc {
  const Doc({
    required this.id,
    required this.topicId,
    required this.title,
    required this.kind,
    required this.relPath,
    required this.sizeBytes,
    required this.pageCount,
    required this.readsMask,
    required this.position,
    required this.importedAt,
    required this.lastOpenedAt,
    required this.archivedAt,
  });
  factory Doc.fromRow(Row r) => Doc(
        id: r['id'] as int,
        topicId: r['topic_id'] as int?,
        title: r['title'] as String,
        kind: DocKind.values.byName(r['kind'] as String),
        relPath: r['rel_path'] as String,
        sizeBytes: r['size_bytes'] as int,
        pageCount: r['page_count'] as int?,
        readsMask: r['reads_mask'] as int,
        position: r['position'] as int,
        importedAt: r['imported_at'] as String,
        lastOpenedAt: r['last_opened_at'] as String?,
        archivedAt: r['archived_at'] as String?,
      );
  final int id;
  final int? topicId;
  final String title;
  final DocKind kind;
  final String relPath;
  final int sizeBytes;
  final int? pageCount;

  /// Six bits : une lecture complète par bit (bit 0 = première lecture).
  final int readsMask;
  final int position;
  final String importedAt;
  final String? lastOpenedAt;
  final String? archivedAt;

  static const maxReads = 6;

  bool isRead(int index) => (readsMask >> index) & 1 == 1;
  int get readCount {
    var n = 0;
    for (var i = 0; i < maxReads; i++) {
      if (isRead(i)) n++;
    }
    return n;
  }
}

/// Chemin complet d'un thème : année › semestre › matière › thème.
class Trail {
  const Trail({
    required this.year,
    required this.semester,
    required this.subject,
    required this.topic,
  });
  final Year year;
  final Semester semester;
  final Subject subject;
  final Topic topic;
}
