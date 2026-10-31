import 'package:carabin/app_session.dart';
import 'package:carabin/data/courses_repository.dart';
import 'package:carabin/data/database.dart';
import 'package:carabin/data/flashcards_repository.dart';
import 'package:carabin/data/media_store.dart';
import 'package:carabin/data/qcm_repository.dart';
import 'package:carabin/data/settings_repository.dart';
import 'package:carabin/data/workspace.dart';
import 'package:carabin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Montre une page seule, avec les mêmes fournisseurs que l'application.
Future<void> pumpPage(
  WidgetTester tester,
  Session session,
  Widget page, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<Session>.value(value: session),
        Provider<Workspace>.value(value: session.workspace),
        ChangeNotifierProvider<AppDatabase>.value(value: session.db),
        Provider<CoursesRepository>.value(value: session.courses),
        Provider<FlashcardsRepository>.value(value: session.flashcards),
        Provider<MediaStore>.value(value: session.media),
        Provider<QcmRepository>.value(value: session.qcm),
        Provider<SettingsRepository>.value(value: session.settings),
      ],
      child: MaterialApp(
        theme: CarabinTheme.light(),
        darkTheme: CarabinTheme.dark(),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
