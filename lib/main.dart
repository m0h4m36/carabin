import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'app_session.dart';
import 'data/workspace.dart';
import 'features/courses/pdf_pages.dart';
import 'l10n/textes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  final support = await getApplicationSupportDirectory();
  final docs = await getApplicationDocumentsDirectory();
  final locator = WorkspaceLocator(p.join(support.path, 'Carabin'));

  Session? session;
  String? message;
  final saved = locator.read();
  if (saved != null) {
    if (Workspace.looksLikeWorkspace(saved)) {
      try {
        session = Session.open(saved, pageCounter: countPdfPages);
      } on Object {
        message = Tx.setupFailed;
      }
    } else {
      message = Tx.setupNotFound;
    }
  }

  runApp(
    CarabinApp(
      session: session,
      locator: locator,
      documentsDir: docs.path,
      pageCounter: countPdfPages,
      initialMessage: message,
    ),
  );
}
