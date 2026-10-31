import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_session.dart';
import 'data/courses_repository.dart';
import 'data/database.dart';
import 'data/flashcards_repository.dart';
import 'data/media_store.dart';
import 'data/settings_repository.dart';
import 'data/workspace.dart';
import 'l10n/textes.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';
import 'ui/workspace_setup_page.dart';

/// Racine de l'application Carabin.
///
/// Sans [session], elle affiche le choix du dossier de travail ; avec une
/// session ouverte, elle affiche l'application.
class CarabinApp extends StatefulWidget {
  const CarabinApp({
    super.key,
    this.session,
    this.locator,
    this.documentsDir,
    this.pageCounter,
    this.initialMessage,
  });

  final Session? session;
  final WorkspaceLocator? locator;
  final String? documentsDir;
  final PageCounter? pageCounter;
  final String? initialMessage;

  @override
  State<CarabinApp> createState() => _CarabinAppState();
}

class _CarabinAppState extends State<CarabinApp> {
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _open(String root) async {
    final session = Session.open(root, pageCounter: widget.pageCounter);
    try {
      widget.locator?.write(root);
    } on FileSystemException {
      session.dispose();
      rethrow;
    }
    final old = _session;
    setState(() => _session = session);
    old?.dispose();
  }

  ThemeMode _mode(String? setting) => switch (setting) {
    'clair' => ThemeMode.light,
    'sombre' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return _materialApp(
        ThemeMode.system,
        WorkspaceSetupPage(
          documentsDir: widget.documentsDir ?? Directory.systemTemp.path,
          onChosen: _open,
          message: widget.initialMessage,
        ),
      );
    }
    return MultiProvider(
      providers: [
        Provider<Session>.value(value: session),
        Provider<Workspace>.value(value: session.workspace),
        ChangeNotifierProvider<AppDatabase>.value(value: session.db),
        Provider<CoursesRepository>.value(value: session.courses),
        Provider<FlashcardsRepository>.value(value: session.flashcards),
        Provider<MediaStore>.value(value: session.media),
        Provider<SettingsRepository>.value(value: session.settings),
      ],
      child: ListenableBuilder(
        listenable: session.themeMode,
        builder: (context, _) =>
            _materialApp(_mode(session.themeMode.value), const AppShell()),
      ),
    );
  }

  Widget _materialApp(ThemeMode mode, Widget home) => MaterialApp(
    title: Tx.appName,
    debugShowCheckedModeBanner: false,
    theme: CarabinTheme.light(),
    darkTheme: CarabinTheme.dark(),
    themeMode: mode,
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );
}
