import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/note_types.dart';
import 'errors.dart';

/// Dossier des médias des cartes (images).
///
/// Chaque fichier porte le nom de son empreinte (SHA-1 tronquée) suivie de
/// son extension : deux fois la même image ne prend de la place qu'une fois,
/// et deux paquets peuvent partager une image sans collision de noms.
class MediaStore {
  MediaStore(this.dir);

  final String dir;

  /// Formats d'image que l'application sait afficher.
  static const imageExtensions = {'png', 'jpg', 'gif', 'webp', 'bmp'};

  /// Documents rangés avec les images (article d'un cas de lecture critique).
  static const articleExtensions = {'pdf'};

  /// Extension normalisée d'un nom de fichier (« .JPEG » devient « jpg »), ou
  /// null si ce n'est pas une image prise en charge.
  static String? imageExtension(String fileName) {
    final raw = p.extension(fileName).toLowerCase().replaceFirst('.', '');
    final ext = raw == 'jpeg' || raw == 'jpe' ? 'jpg' : raw;
    return imageExtensions.contains(ext) ? ext : null;
  }

  /// Nom que prendrait ce contenu dans le dossier.
  static String nameFor(Uint8List bytes, String extension) {
    final digest = sha1.convert(bytes).toString().substring(0, 20);
    return '$digest.$extension';
  }

  /// Enregistre des octets et renvoie le nom du fichier.
  String addBytes(Uint8List bytes, String extension) {
    final isArticle = articleExtensions.contains(extension);
    if (!imageExtensions.contains(extension) && !isArticle) {
      throw const UnsupportedFileError();
    }
    if (isArticle && !_looksLikePdf(bytes)) {
      throw const UnsupportedFileError();
    }
    final name = nameFor(bytes, extension);
    final f = File(p.join(dir, name));
    if (!f.existsSync() || f.lengthSync() != bytes.length) {
      Directory(dir).createSync(recursive: true);
      final tmp = File('${f.path}.tmp');
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(f.path);
    }
    return name;
  }

  /// Copie une image choisie par l'utilisateur et renvoie son nom.
  String addFile(String path) {
    final ext = imageExtension(path);
    if (ext == null) throw const UnsupportedFileError();
    return addBytes(File(path).readAsBytesSync(), ext);
  }

  /// Copie un article PDF choisi par l'utilisateur et renvoie son nom.
  String addArticle(String path) {
    if (p.extension(path).toLowerCase() != '.pdf') {
      throw const UnsupportedFileError();
    }
    return addBytes(File(path).readAsBytesSync(), 'pdf');
  }

  static bool _looksLikePdf(Uint8List b) =>
      b.length > 5 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46 &&
      b[4] == 0x2D;

  /// Fichier d'un média ; le nom doit être de la forme fabriquée par
  /// l'application (aucun chemin ne peut sortir du dossier).
  File file(String name) {
    if (!mediaNamePattern.hasMatch(name)) throw const NotFoundError();
    return File(p.join(dir, name));
  }

  bool exists(String name) =>
      mediaNamePattern.hasMatch(name) && File(p.join(dir, name)).existsSync();

  Uint8List? read(String name) {
    final f = file(name);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  /// Médias présents dans le dossier mais cités nulle part.
  List<String> unused(Set<String> referenced) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return [
      for (final f in d.listSync().whereType<File>())
        if (mediaNamePattern.hasMatch(p.basename(f.path)) &&
            !referenced.contains(p.basename(f.path)))
          p.basename(f.path),
    ];
  }

  /// Supprime les médias que personne ne cite plus ; renvoie leur nombre.
  int purge(Set<String> referenced) {
    var n = 0;
    for (final name in unused(referenced)) {
      try {
        File(p.join(dir, name)).deleteSync();
        n++;
      } on FileSystemException {
        // fichier verrouillé : il sera repris au prochain nettoyage
      }
    }
    return n;
  }
}
