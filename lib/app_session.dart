import 'package:flutter/foundation.dart';

import 'data/courses_repository.dart';
import 'data/database.dart';
import 'data/flashcards_repository.dart';
import 'data/media_store.dart';
import 'data/settings_repository.dart';
import 'data/workspace.dart';

/// Tout ce qui dépend du dossier de travail ouvert : base, dépôts de données.
class Session {
  Session._(this.workspace, this.db, {PageCounter? pageCounter})
    : settings = SettingsRepository(db),
      media = MediaStore(workspace.mediaDir),
      courses = CoursesRepository(db, workspace, pageCounter: pageCounter) {
    flashcards = FlashcardsRepository(db, settings);
    themeMode = ValueNotifier(settings.get(Keys.themeMode));
  }

  final Workspace workspace;
  final AppDatabase db;
  final SettingsRepository settings;
  final CoursesRepository courses;

  /// Images des cartes.
  final MediaStore media;
  late final FlashcardsRepository flashcards;

  /// Apparence choisie : null/« auto », « clair » ou « sombre ».
  late final ValueNotifier<String?> themeMode;

  void setThemeMode(String? mode) {
    settings.set(Keys.themeMode, mode);
    themeMode.value = mode;
  }

  /// Ouvre (ou crée) le dossier de travail [root].
  static Session open(
    String root, {
    PageCounter? pageCounter,
    bool inMemoryDb = false,
  }) {
    final ws = Workspace(root)..ensureStructure();
    final db = inMemoryDb
        ? AppDatabase.inMemory()
        : AppDatabase.open(ws.dbPath);
    return Session._(ws, db, pageCounter: pageCounter);
  }

  void dispose() {
    themeMode.dispose();
    db.dispose();
  }
}
