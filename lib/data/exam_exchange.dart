import 'dart:convert';
import 'dart:typed_data';

import '../domain/qcm/exam_file.dart';
import 'courses_repository.dart';
import 'errors.dart';
import 'media_store.dart';
import 'names.dart';
import 'qcm_repository.dart';

/// Ce qu'a donné l'ouverture d'un fichier d'épreuve.
class ExamImportReport {
  const ExamImportReport({
    required this.examId,
    required this.title,
    required this.questions,
    required this.mediaAdded,
    required this.mediaMissing,
    required this.mediaRejected,
    required this.subjectLinked,
    required this.replaced,
  });

  final int examId;
  final String title;
  final int questions;

  /// Images et articles repris du fichier.
  final int mediaAdded;

  /// Médias cités par l'épreuve mais absents du fichier (et de l'appareil).
  final int mediaMissing;

  /// Médias du fichier refusés (format non pris en charge, PDF invalide).
  final int mediaRejected;

  /// La matière du fichier existe ici et a été reprise.
  final bool subjectLinked;
  final bool replaced;
}

/// Partage d'épreuves : écriture et lecture des fichiers `.qcm.json`.
class ExamExchange {
  ExamExchange(this.qcm, this.courses, this.media);

  final QcmRepository qcm;
  final CoursesRepository courses;
  final MediaStore media;

  /// Nom de fichier proposé pour partager une épreuve.
  static String fileNameFor(String title) => '${safeFileName(title)}.qcm.json';

  /// Fichier d'une épreuve, images et articles compris.
  ({String fileName, Uint8List bytes, int missingMedia}) exportExam(
    int examId,
  ) {
    final exam = qcm.exam(examId);
    var subjectName = '';
    final sid = exam.subjectId;
    if (sid != null) {
      for (final (s, _, _) in courses.allSubjects()) {
        if (s.id == sid) subjectName = s.name;
      }
    }
    final doc = qcm.toDoc(examId, subjectName: subjectName);
    final files = <String, Uint8List>{};
    var missing = 0;
    for (final name in doc.mediaNames) {
      final bytes = media.exists(name) ? media.read(name) : null;
      if (bytes == null) {
        missing++;
      } else {
        files[name] = bytes;
      }
    }
    return (
      fileName: fileNameFor(exam.title),
      bytes: Uint8List.fromList(utf8.encode(encodeExamFile(doc, files))),
      missingMedia: missing,
    );
  }

  /// Lit un fichier d'épreuve (sans rien enregistrer).
  ExamFile parse(Uint8List bytes) => parseBytes(bytes);

  /// Comme [parse], sans dépôt : peut tourner hors du fil de l'interface.
  static ExamFile parseBytes(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ExchangeError(ImportProblem.unreadable);
    }
    final ExamFile file;
    try {
      file = decodeExamFile(text);
    } on NewerExamFile {
      throw const ExchangeError(ImportProblem.newerFormat);
    } on FormatException catch (e) {
      throw ExchangeError(ImportProblem.unreadable, e.message);
    }
    if (file.exam.questionCount == 0) {
      throw const ExchangeError(ImportProblem.empty);
    }
    return file;
  }

  /// Épreuve déjà présente qui porte le même identifiant, le cas échéant.
  int? existingId(ExamFile file) => qcm.examByGuid(file.exam.guid)?.id;

  /// Enregistre l'épreuve. Avec [replace], le contenu de l'épreuve de même
  /// identifiant est remplacé (ses copies sont gardées).
  ExamImportReport apply(ExamFile file, {bool replace = false}) {
    final rename = <String, String>{};
    var added = 0;
    var rejected = 0;
    for (final e in file.media.entries) {
      final ext = e.key.substring(e.key.lastIndexOf('.') + 1);
      try {
        rename[e.key] = media.addBytes(e.value, ext);
        added++;
      } on UnsupportedFileError {
        rejected++;
      }
    }
    final doc = file.exam.remapMedia((n) => rename[n] ?? n);
    var missing = 0;
    for (final name in doc.mediaNames) {
      if (!media.exists(name)) missing++;
    }

    int? subjectId;
    if (doc.subjectName.isNotEmpty) {
      final wanted = doc.subjectName.toLowerCase();
      final found = [
        for (final (s, _, _) in courses.allSubjects())
          if (s.name.toLowerCase() == wanted) s.id,
      ];
      if (found.length == 1) subjectId = found.single;
    }

    final existing = replace ? existingId(file) : null;
    final id = qcm.saveDoc(doc, subjectId: subjectId, replaceExamId: existing);
    return ExamImportReport(
      examId: id,
      title: doc.title,
      questions: doc.questionCount,
      mediaAdded: added,
      mediaMissing: missing,
      mediaRejected: rejected,
      subjectLinked: subjectId != null,
      replaced: existing != null,
    );
  }
}
