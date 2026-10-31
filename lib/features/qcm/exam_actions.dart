import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_session.dart';
import '../../data/background.dart';
import '../../data/courses_repository.dart';
import '../../data/exam_exchange.dart';
import '../../data/qcm_models.dart';
import '../../data/qcm_repository.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import '../../ui/pickers.dart';
import '../flashcards/deck_actions.dart' show pickCourse;

/// Plus gros fichier d'épreuve qu'on accepte d'ouvrir.
const maxExamFileBytes = 300 * 1024 * 1024;

/// Demande le nom d'une nouvelle série et la crée ; renvoie son identifiant.
Future<int?> createSeriesFlow(
  BuildContext context, {
  int? subjectId,
  bool pastPaper = false,
}) async {
  final repo = context.read<QcmRepository>();
  final title = await promptText(
    context,
    title: TxQcm.newSeriesTitle,
    label: TxQcm.newSeriesLabel,
  );
  if (title == null || !context.mounted) return null;
  int? id;
  await guarded(context, () {
    id = repo.createExam(title, subjectId: subjectId, pastPaper: pastPaper).id;
  });
  return id;
}

/// Renomme une série.
Future<void> renameExamFlow(BuildContext context, ExamRow exam) async {
  final repo = context.read<QcmRepository>();
  final title = await promptText(
    context,
    title: TxQcm.rename,
    label: TxQcm.renameLabel,
    initial: exam.title,
  );
  if (title == null || !context.mounted) return;
  await guarded(context, () => repo.renameExam(exam.id, title));
}

/// Range des séries dans une matière (ou dans « Sans matière »).
Future<void> chooseSubjectForExams(
  BuildContext context,
  List<int> examIds,
) async {
  final courses = context.read<CoursesRepository>();
  final repo = context.read<QcmRepository>();
  final subjects = courses.allSubjects();
  final r = await pickFromList<int>(
    context,
    title: TxQcm.pickSubject,
    choices: [
      const Choice(-1, TxQcm.noSubject),
      for (final (s, sem, y) in subjects)
        Choice(
          s.id,
          s.name,
          subtitle: '${y.name} · ${sem.name}',
          color: colorOf(s.color),
        ),
    ],
  );
  if (r == null || !context.mounted) return;
  await guarded(
    context,
    () => repo.setExamSubject(examIds, r == -1 ? null : r),
  );
}

/// Rattache une série à un poly (recherche par titre).
Future<void> chooseCourseForExam(BuildContext context, int examId) async {
  final repo = context.read<QcmRepository>();
  final id = await pickCourse(context);
  if (id == null || !context.mounted) return;
  await guarded(context, () => repo.setExamDocument(examId, id));
}

Future<void> detachCourseFromExam(BuildContext context, int examId) {
  final repo = context.read<QcmRepository>();
  return guarded(context, () => repo.setExamDocument(examId, null));
}

/// Saisie des numéros d'items des EDN.
Future<void> editItemsFlow(BuildContext context, ExamRow exam) async {
  final repo = context.read<QcmRepository>();
  final text = await promptText(
    context,
    title: TxQcm.itemsTitle,
    label: TxQcm.itemsHint,
    initial: exam.items,
  );
  if (text == null || !context.mounted) return;
  await guarded(context, () => repo.setExamItems(exam.id, text.trim()));
}

/// Supprime des séries après confirmation ; renvoie vrai si c'est fait.
Future<bool> deleteExamsFlow(BuildContext context, List<ExamRow> exams) async {
  if (exams.isEmpty) return false;
  final repo = context.read<QcmRepository>();
  final ok = await confirm(
    context,
    title: TxQcm.confirmDeleteTitle,
    message: TxQcm.confirmDeleteExams(
      exams.length,
      exams.length == 1 ? exams.first.title : null,
    ),
    confirmLabel: TxQcm.menuDelete,
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  return guarded(
    context,
    () => repo.deleteExams([for (final e in exams) e.id]),
  );
}

/// Fait une copie de la série.
Future<int?> duplicateExamFlow(BuildContext context, ExamRow exam) async {
  final repo = context.read<QcmRepository>();
  int? id;
  final ok = await guarded(context, () {
    id = repo
        .duplicateExam(exam.id, title: '${exam.title}${TxQcm.duplicateSuffix}')
        .id;
  });
  if (ok && context.mounted) showInfo(context, TxQcm.seriesDuplicated);
  return id;
}

/// Écrit le fichier `.qcm.json` d'une série à l'endroit choisi.
Future<void> shareExamFlow(BuildContext context, int examId) async {
  final session = context.read<Session>();
  final ({String fileName, Uint8List bytes, int missingMedia}) file;
  try {
    file = session.examExchange.exportExam(examId);
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  final bool saved;
  try {
    saved = await Pickers.save(file.fileName, file.bytes);
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!saved || !context.mounted) return;
  showInfo(
    context,
    file.missingMedia == 0
        ? TxQcm.shared(file.fileName)
        : '${TxQcm.shared(file.fileName)} ${TxQcm.sharedMissing(file.missingMedia)}',
  );
}

/// Contenu du fichier, ou null s'il dépasse [maxExamFileBytes].
Uint8List? _readExamFile(String path) {
  final file = File(path);
  if (file.lengthSync() > maxExamFileBytes) return null;
  return file.readAsBytesSync();
}

/// Ouvre une épreuve reçue : choix du fichier, remplacement éventuel,
/// compte rendu. Renvoie l'identifiant de l'épreuve ajoutée.
Future<int?> importExamFlow(BuildContext context) async {
  final session = context.read<Session>();
  final String? path;
  try {
    path = await Pickers.file(const ['json']);
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (path == null || !context.mounted) return null;
  final chosen = path;
  final Uint8List? bytes;
  try {
    bytes = await Background.run(() => _readExamFile(chosen));
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (!context.mounted) return null;
  if (bytes == null) {
    showInfo(context, TxQcm.importTooBig);
    return null;
  }
  final data = bytes;
  final parsed = session.examExchange;
  try {
    final doc = await Background.run(() => ExamExchange.parseBytes(data));
    if (!context.mounted) return null;
    var replace = false;
    final existing = parsed.existingId(doc);
    if (existing != null) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(TxQcm.importReplaceTitle),
          content: Text(TxQcm.importReplaceMessage(doc.exam.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(Tx.cancel),
            ),
            OutlinedButton(
              key: const ValueKey('import-keep-both'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(TxQcm.importKeepBoth),
            ),
            FilledButton(
              key: const ValueKey('import-replace'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(TxQcm.importReplace),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return null;
      replace = choice;
    }
    final report = parsed.apply(doc, replace: replace);
    if (!context.mounted) return report.examId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(TxQcm.importReportTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TxQcm.importReportLine(
                report.title,
                report.questions,
                report.replaced,
              ),
            ),
            const SizedBox(height: 8),
            Text(TxQcm.importSubject(report.subjectLinked)),
            if (report.mediaAdded > 0)
              Text(TxQcm.importMedia(report.mediaAdded)),
            if (report.mediaMissing > 0)
              Text(TxQcm.importMediaMissing(report.mediaMissing)),
            if (report.mediaRejected > 0)
              Text(TxQcm.importMediaRejected(report.mediaRejected)),
          ],
        ),
        actions: [
          FilledButton(
            key: const ValueKey('import-ok'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(TxQcm.done),
          ),
        ],
      ),
    );
    return report.examId;
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}
