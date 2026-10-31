import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/courses_repository.dart';
import '../../l10n/textes.dart';
import '../../ui/dialogs.dart';

const importExtensions = [
  'pdf',
  'doc',
  'docx',
  'odt',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'txt',
  'md',
];

/// Ouvre le sélecteur de fichiers et importe les choix dans un thème.
Future<void> importIntoTopic(
  BuildContext context,
  CoursesRepository courses,
  int topicId,
) async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: importExtensions,
    );
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(Tx.importing),
        duration: Duration(minutes: 1),
      ),
    );
  var ok = 0;
  Object? firstError;
  for (final f in picked) {
    final path = f.path;
    if (path == null) continue;
    try {
      await courses.importFile(topicId, path);
      ok++;
    } on Object catch (e) {
      firstError ??= e;
    }
  }
  messenger.hideCurrentSnackBar();
  if (firstError != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${ok > 0 ? '${Tx.importedCount(ok)} ' : ''}${Tx.errorMessage(firstError)}',
        ),
      ),
    );
  } else if (ok > 0) {
    messenger.showSnackBar(SnackBar(content: Text(Tx.importedCount(ok))));
  }
}
