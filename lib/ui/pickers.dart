import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Sélecteurs de fichiers du système, regroupés ici pour que les tests
/// puissent les remplacer (aucune boîte de dialogue native en test).
abstract final class Pickers {
  /// Choisit une image ; renvoie son chemin, ou null si l'utilisateur annule.
  static Future<String?> Function() image = _pickImage;

  /// Choisit un fichier parmi [extensions] (sans le point).
  static Future<String?> Function(List<String> extensions) file = _pickFile;

  /// Enregistre [bytes] sous [fileName] à l'endroit choisi ; false si annulé.
  static Future<bool> Function(String fileName, Uint8List bytes) save = _save;

  static const imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];

  static Future<String?> _pickImage() => _pickFile(imageExtensions);

  static Future<String?> _pickFile(List<String> extensions) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (picked.isEmpty) return null;
    final f = picked.first;
    final path = f.path;
    if (path != null) return path;
    // Certains systèmes ne donnent pas de chemin : on copie le contenu.
    final tmp = Directory.systemTemp.createTempSync('carabin_pick_');
    final out = File(p.join(tmp.path, p.basename(f.name)));
    out.writeAsBytesSync(await f.readAsBytes());
    return out.path;
  }

  static Future<bool> _save(String fileName, Uint8List bytes) async {
    final where = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    return where != null;
  }
}
