import 'dart:io';

import 'package:carabin/app_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Session de test : base en mémoire et dossier temporaire supprimé à la fin.
Session openTestSession({PageCounterForTest? pageCounter}) {
  final tmp = Directory.systemTemp.createTempSync('carabin_widget_');
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  final session = Session.open(
    p.join(tmp.path, 'racine'),
    inMemoryDb: true,
    pageCounter: pageCounter,
  );
  return session;
}

typedef PageCounterForTest = Future<int?> Function(String path);
