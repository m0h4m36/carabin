import 'database.dart';

/// Réglages enregistrés dans la base (clé / valeur).
class SettingsRepository {
  SettingsRepository(this.db);

  final AppDatabase db;

  String? get(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void set(String key, String? value) {
    db.transaction(() {
      if (value == null) {
        db.execute('DELETE FROM settings WHERE key = ?', [key]);
      } else {
        db.execute(
          'INSERT INTO settings(key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value],
        );
      }
    });
  }

  bool getBool(String key, {bool defaultValue = false}) {
    final v = get(key);
    if (v == null) return defaultValue;
    return v == '1';
  }

  void setBool(String key, bool value) => set(key, value ? '1' : '0');

  int getInt(String key, {required int defaultValue}) =>
      int.tryParse(get(key) ?? '') ?? defaultValue;

  void setInt(String key, int value) => set(key, '$value');
}

/// Clés des réglages.
abstract final class Keys {
  static const themeMode = 'apparence'; // auto | clair | sombre
}
