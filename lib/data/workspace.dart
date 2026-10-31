import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Dossier de travail de l'utilisateur : base SQLite, polys, paquets, QCM,
/// archives. Tout y est rangé dans des dossiers ordinaires.
class Workspace {
  Workspace(this.root);

  final String root;

  static const dbFileName = 'carabin.db';
  static const coursName = 'Cours';
  static const decksName = 'Decks';
  static const qcmName = 'QCM';
  static const archivesName = 'Archives';

  String get dbPath => p.join(root, dbFileName);
  String get coursDir => p.join(root, coursName);
  String get decksDir => p.join(root, decksName);

  /// Images (et autres médias) des cartes, nommées par empreinte du contenu.
  String get mediaDir => p.join(root, decksName, 'media');
  String get qcmDir => p.join(root, qcmName);
  String get archivesDir => p.join(root, archivesName);
  String get archivesCoursDir => p.join(archivesDir, coursName);

  /// Chemin absolu d'un chemin relatif stocké en base (séparateur « / »).
  String absolute(String relPath) => p.joinAll([root, ...relPath.split('/')]);

  /// Chemin relatif (séparateur « / ») d'un chemin absolu du dossier.
  String relative(String absolutePath) =>
      p.split(p.relative(absolutePath, from: root)).join('/');

  /// Crée l'arborescence de base si elle manque.
  void ensureStructure() {
    for (final d in [
      coursDir,
      decksDir,
      mediaDir,
      qcmDir,
      p.join(archivesDir, coursName),
      p.join(archivesDir, 'Flashcards'),
      p.join(archivesDir, 'QCM'),
    ]) {
      Directory(d).createSync(recursive: true);
    }
  }

  /// Vrai si le dossier contient déjà une base Carabin.
  static bool looksLikeWorkspace(String path) =>
      File(p.join(path, dbFileName)).existsSync();

  /// Vrai si le dossier est vide (ou n'existe pas encore).
  static bool isEmptyOrMissing(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return true;
    return dir.listSync().isEmpty;
  }

  /// Emplacement proposé par défaut, sous « Documents ».
  static String defaultRoot(String documentsDir) =>
      p.join(documentsDir, 'Carabin');
}

/// Retient où se trouve le dossier de travail, dans un petit fichier du
/// dossier de l'application (le dossier de travail peut être déplacé).
class WorkspaceLocator {
  WorkspaceLocator(this.configDir);

  final String configDir;

  File get _file => File(p.join(configDir, 'dossier.json'));

  String? read() {
    try {
      if (!_file.existsSync()) return null;
      final data = jsonDecode(_file.readAsStringSync());
      final path = (data as Map)['racine'];
      if (path is String && path.isNotEmpty) return path;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
    return null;
  }

  void write(String root) {
    Directory(configDir).createSync(recursive: true);
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode({'racine': root}));
    tmp.renameSync(_file.path);
  }
}
