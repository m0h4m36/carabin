import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// Base SQLite de l'application.
///
/// Toutes les écritures passent par [transaction] : à la fin de la
/// transaction la plus extérieure, les écrans à l'écoute sont prévenus et se
/// redessinent. Les lectures sont synchrones, ce qui rend les écrans simples.
class AppDatabase extends ChangeNotifier {
  AppDatabase._(this.raw);

  final Database raw;
  int _depth = 0;
  bool _disposed = false;

  /// Ouvre (ou crée) la base du fichier [path].
  static AppDatabase open(String path) {
    final db = AppDatabase._(sqlite3.open(path));
    db._init(wal: true);
    return db;
  }

  /// Base en mémoire, pour les tests.
  static AppDatabase inMemory() {
    final db = AppDatabase._(sqlite3.openInMemory());
    db._init(wal: false);
    return db;
  }

  void _init({required bool wal}) {
    raw.execute('PRAGMA foreign_keys = ON');
    if (wal) raw.execute('PRAGMA journal_mode = WAL');
    _migrate();
  }

  void _migrate() {
    final current = raw.select('PRAGMA user_version').first.values.first as int;
    if (current > migrations.length) {
      throw StateError(
        'La base a été créée par une version plus récente de Carabin.',
      );
    }
    for (var i = current; i < migrations.length; i++) {
      raw.execute('BEGIN');
      try {
        raw.execute(migrations[i]);
        raw.execute('PRAGMA user_version = ${i + 1}');
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  /// Version du schéma actuellement appliquée.
  int get schemaVersion =>
      raw.select('PRAGMA user_version').first.values.first as int;

  ResultSet select(String sql, [List<Object?> params = const []]) =>
      raw.select(sql, params);

  void execute(String sql, [List<Object?> params = const []]) =>
      raw.execute(sql, params);

  int get lastInsertId => raw.lastInsertRowId;

  /// Nombre de lignes touchées par la dernière écriture.
  int get changes => raw.updatedRows;

  /// Exécute [body] dans une transaction (annulée si une exception sort).
  T transaction<T>(T Function() body) {
    if (_depth > 0) {
      // Transaction imbriquée : on rejoint la transaction extérieure.
      _depth++;
      try {
        return body();
      } finally {
        _depth--;
      }
    }
    raw.execute('BEGIN IMMEDIATE');
    _depth = 1;
    try {
      final result = body();
      raw.execute('COMMIT');
      _depth = 0;
      _notify();
      return result;
    } catch (_) {
      _depth = 0;
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Copie cohérente de la base dans [path] (sûre même en mode WAL).
  void backupTo(String path) {
    final escaped = path.replaceAll("'", "''");
    raw.execute("VACUUM INTO '$escaped'");
  }

  @override
  void dispose() {
    _disposed = true;
    raw.close();
    super.dispose();
  }
}
