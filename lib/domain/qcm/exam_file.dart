/// Fichier d'échange d'une épreuve (`<titre>.qcm.json`) : l'épreuve, ses
/// cas, ses questions et les images, le tout dans un seul fichier texte.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'exam.dart';
import 'question.dart';

const examFileFormat = 'carabin-qcm';
const examFileVersion = 1;
const maxExamQuestions = 2000;
const maxExamUnits = 2000;
const maxMediaBytes = 60 * 1024 * 1024;

/// Fichier fabriqué par une version plus récente de Carabin.
class NewerExamFile implements Exception {
  const NewerExamFile();
}

/// Une question isolée ([info] nul) ou un cas et ses questions, tels qu'ils
/// sont écrits dans l'épreuve.
class ExamUnitDoc {
  const ExamUnitDoc(this.questions, {this.info});

  final CaseInfo? info;
  final List<Question> questions;
}

/// Contenu d'une épreuve, indépendant de la base de données.
class ExamDoc {
  const ExamDoc({
    required this.guid,
    required this.title,
    this.subjectName = '',
    this.items = '',
    this.pastPaper = false,
    this.units = const [],
  });

  final String guid;
  final String title;

  /// Nom de la matière (le fichier ne porte pas d'identifiant de la base de
  /// l'expéditeur).
  final String subjectName;
  final String items;
  final bool pastPaper;
  final List<ExamUnitDoc> units;

  int get questionCount => units.fold(0, (a, u) => a + u.questions.length);

  /// Médias cités par l'épreuve (images et articles).
  Set<String> get mediaNames => {
    for (final u in units) ...[
      if (u.info != null && u.info!.articleFile.isNotEmpty) u.info!.articleFile,
      for (final q in u.questions) ...q.mediaNames,
    ],
  };

  /// Même épreuve avec les médias renommés.
  ExamDoc remapMedia(String Function(String) rename) => ExamDoc(
    guid: guid,
    title: title,
    subjectName: subjectName,
    items: items,
    pastPaper: pastPaper,
    units: [
      for (final u in units)
        ExamUnitDoc(
          [for (final q in u.questions) q.remapMedia(rename)],
          info: u.info == null || u.info!.articleFile.isEmpty
              ? u.info
              : u.info!.copyWith(articleFile: rename(u.info!.articleFile)),
        ),
    ],
  );
}

/// Contenu d'un fichier `.qcm.json`.
class ExamFile {
  const ExamFile(this.exam, this.media);

  final ExamDoc exam;

  /// Octets de chaque média, par le nom qu'il porte dans le fichier.
  final Map<String, Uint8List> media;
}

/// Écrit un fichier d'épreuve.
String encodeExamFile(
  ExamDoc exam,
  Map<String, Uint8List> media, {
  required String appVersion,
}) {
  return jsonEncode({
    'format': examFileFormat,
    'version': examFileVersion,
    'app': appVersion,
    'exam': {
      'guid': exam.guid,
      'title': exam.title,
      if (exam.subjectName.isNotEmpty) 'subject': exam.subjectName,
      if (exam.items.isNotEmpty) 'items': exam.items,
      if (exam.pastPaper) 'pastPaper': true,
      'units': [
        for (final u in exam.units)
          {
            if (u.info != null) 'case': u.info!.toJson(),
            'questions': [for (final q in u.questions) q.toJson()],
          },
      ],
    },
    'media': {for (final e in media.entries) e.key: base64Encode(e.value)},
  });
}

final _guid = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
final _mediaKey = RegExp(r'^[0-9a-f]{8,64}\.[a-z0-9]{2,5}$');

/// Lit un fichier d'épreuve ; lève [FormatException] s'il est invalide et
/// [NewerExamFile] s'il vient d'une version plus récente.
ExamFile decodeExamFile(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FormatException('JSON illisible');
  }
  if (root is! Map || root['format'] != examFileFormat) {
    throw const FormatException('ce n\'est pas une épreuve Carabin');
  }
  final version = root['version'];
  if (version is! int) throw const FormatException('version manquante');
  if (version > examFileVersion) throw const NewerExamFile();

  final e = root['exam'];
  if (e is! Map) throw const FormatException('épreuve manquante');
  final guid = e['guid'];
  if (guid is! String || !_guid.hasMatch(guid)) {
    throw const FormatException('identifiant invalide');
  }
  String s(String key, int max) {
    final v = e[key];
    if (v == null) return '';
    if (v is! String) throw FormatException('texte attendu ($key)');
    return v.length > max ? v.substring(0, max) : v;
  }

  final title = s('title', 200).trim();
  if (title.isEmpty) throw const FormatException('titre manquant');

  final rawUnits = e['units'];
  if (rawUnits is! List || rawUnits.length > maxExamUnits) {
    throw const FormatException('questions manquantes');
  }
  var total = 0;
  final units = <ExamUnitDoc>[];
  for (final u in rawUnits) {
    if (u is! Map) throw const FormatException('bloc invalide');
    final rawQuestions = u['questions'];
    if (rawQuestions is! List || rawQuestions.isEmpty) {
      throw const FormatException('cas sans question');
    }
    total += rawQuestions.length;
    if (total > maxExamQuestions) {
      throw const FormatException('trop de questions');
    }
    final info = u['case'] == null ? null : CaseInfo.fromJson(u['case']);
    if (info == null && rawQuestions.length != 1) {
      throw const FormatException('question isolée multiple');
    }
    units.add(
      ExamUnitDoc([
        for (final q in rawQuestions) Question.fromJson(q),
      ], info: info),
    );
  }

  final media = <String, Uint8List>{};
  final rawMedia = root['media'];
  if (rawMedia != null) {
    if (rawMedia is! Map) throw const FormatException('médias invalides');
    var bytes = 0;
    for (final entry in rawMedia.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !_mediaKey.hasMatch(key) || value is! String) {
        throw const FormatException('média invalide');
      }
      final Uint8List data;
      try {
        data = base64Decode(value);
      } on FormatException {
        throw const FormatException('média illisible');
      }
      bytes += data.length;
      if (bytes > maxMediaBytes) {
        throw const FormatException('médias trop gros');
      }
      media[key] = data;
    }
  }

  return ExamFile(
    ExamDoc(
      guid: guid,
      title: title,
      subjectName: s('subject', 200).trim(),
      items: s('items', 500),
      pastPaper: e['pastPaper'] == true,
      units: units,
    ),
    media,
  );
}
