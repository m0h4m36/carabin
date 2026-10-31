import 'dart:io';

import 'package:carabin/data/database.dart';
import 'package:carabin/data/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('la migration 3 donne un identifiant unique aux notes existantes', () {
    final tmp = Directory.systemTemp.createTempSync('carabin_schema_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = p.join(tmp.path, 'ancienne.db');

    // Une base telle que la version précédente de Carabin l'avait laissée.
    final old = sqlite3.open(path);
    old.execute('PRAGMA foreign_keys = ON');
    old.execute(migrations[0]);
    old.execute(migrations[1]);
    old.execute('PRAGMA user_version = 2');
    old.execute(
      "INSERT INTO decks(name, position, created_at) VALUES ('Anatomie', 0, 1)",
    );
    for (var i = 0; i < 50; i++) {
      old.execute(
        "INSERT INTO notes(deck_id, type, fields_json, created_at, updated_at) "
        "VALUES (1, 'basic', '{}', 1, 1)",
      );
    }
    old.close();

    final db = AppDatabase.open(path);
    addTearDown(db.dispose);
    expect(db.schemaVersion, migrations.length);
    final guids = [
      for (final r in db.select('SELECT guid FROM notes')) r['guid'] as String?,
    ];
    expect(guids, hasLength(50));
    expect(guids.every((g) => g != null && g.length == 32), isTrue);
    expect(guids.toSet(), hasLength(50));

    // Deux notes ne peuvent pas partager un identifiant.
    expect(
      () => db.execute(
        "UPDATE notes SET guid = (SELECT guid FROM notes WHERE id = 1) WHERE id = 2",
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
