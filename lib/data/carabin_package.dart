import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

import '../domain/exchange.dart';
import '../domain/note_types.dart';
import 'errors.dart';
import 'media_store.dart';

/// Extension des fichiers de paquets Carabin.
const carabinExtension = 'carabin';

const _format = 'carabin-decks';
const _version = 1;

/// Ce que contient un fichier de paquets, une fois lu.
class ParsedPackage {
  ParsedPackage({
    required this.decks,
    required this.hasProgress,
    this.mediaAdded = 0,
    this.mediaSkipped = 0,
    this.notesSkipped = 0,
    this.imagesDropped = 0,
    this.soundsDropped = 0,
    this.shapesApproximated = 0,
    this.shapesDropped = 0,
  });

  final List<IncomingDeck> decks;

  /// Le fichier porte l'avancement des cartes (progression exportée).
  final bool hasProgress;
  final int mediaAdded;
  final int mediaSkipped;

  /// Notes écartées dès la lecture (type de note inconnu, trous imbriqués…).
  final int notesSkipped;

  /// Images citées dans le texte mais introuvables ou de format non pris en
  /// charge, et sons ou vidéos ignorés (paquets d'autres applications).
  final int imagesDropped;
  final int soundsDropped;

  /// Zones d'occlusion remplacées par leur rectangle englobant, et zones
  /// impossibles à reprendre.
  final int shapesApproximated;
  final int shapesDropped;
}

/// Fabrique un fichier de paquets : `manifest.json`, `decks.json` et les
/// images dans `media/`. Les images ne sont pas recompressées.
Uint8List buildCarabinPackage({
  required List<IncomingDeck> decks,
  required bool progress,
  required MediaStore media,
  String appVersion = '',
  DateTime? now,
}) {
  final archive = Archive();
  void addText(String name, Object json) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(jsonEncode(json))));
  }

  addText('manifest.json', {
    'format': _format,
    'version': _version,
    'progress': progress,
    'created': (now ?? DateTime.now()).toUtc().toIso8601String(),
    if (appVersion.isNotEmpty) 'app': appVersion,
  });
  addText('decks.json', {
    'decks': [for (final d in decks) d.toJson()],
  });

  final names = <String>{
    for (final d in decks)
      for (final n in d.notes) ...noteMedia(n.fields),
  };
  for (final name in names.toList()..sort()) {
    final bytes = media.exists(name) ? media.read(name) : null;
    if (bytes == null) {
      continue; // image perdue : la carte l'affichera manquante
    }
    archive.addFile(
      ArchiveFile.bytes('media/$name', bytes)
        ..compression = CompressionType.none,
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Lit un fichier de paquets et range ses images dans [mediaDir]. Peut durer :
/// à lancer dans un isolat pour les gros fichiers.
ParsedPackage readCarabinPackage(String path, String mediaDir) {
  final media = MediaStore(mediaDir);
  final Archive archive;
  try {
    archive = ZipDecoder().decodeStream(InputFileStream(path));
  } on Object {
    throw const ExchangeError(ImportProblem.unreadable);
  }
  try {
    ArchiveFile? find(String name) {
      for (final f in archive.files) {
        if (f.isFile && f.name == name) return f;
      }
      return null;
    }

    final manifestFile = find('manifest.json');
    final decksFile = find('decks.json');
    if (manifestFile == null || decksFile == null) {
      throw const ExchangeError(ImportProblem.unreadable);
    }
    final manifest = jsonDecode(
      utf8.decode(manifestFile.readBytes()!),
    ) as Map<String, dynamic>;
    if (manifest['format'] != _format) {
      throw const ExchangeError(ImportProblem.unreadable);
    }
    final version = manifest['version'];
    if (version is! int || version < 1) {
      throw const ExchangeError(ImportProblem.corrupt);
    }
    if (version > _version) {
      throw const ExchangeError(ImportProblem.newerFormat);
    }

    // images d'abord : leur nom définitif dépend de leur contenu
    final renames = <String, String>{};
    var added = 0;
    var skipped = 0;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('media/')) continue;
      final name = f.name.substring('media/'.length);
      final ext = MediaStore.imageExtension(name);
      final bytes = f.readBytes();
      if (ext == null ||
          bytes == null ||
          name.contains('/') ||
          name.contains('\\')) {
        skipped++;
        continue;
      }
      final stored = media.addBytes(bytes, ext);
      if (stored != name) renames[name] = stored;
      added++;
    }

    final raw =
        jsonDecode(utf8.decode(decksFile.readBytes()!)) as Map<String, dynamic>;
    final decks = [
      for (final d in (raw['decks'] as List))
        IncomingDeck.fromJson((d as Map).cast<String, dynamic>()),
    ];
    final fixed = renames.isEmpty
        ? decks
        : [
            for (final d in decks)
              IncomingDeck(
                name: d.name,
                options: d.options,
                notes: [
                  for (final n in d.notes)
                    IncomingNote(
                      guid: n.guid,
                      type: n.type,
                      fields: remapMedia(n.fields, renames),
                      tags: n.tags,
                      createdAtMs: n.createdAtMs,
                      updatedAtMs: n.updatedAtMs,
                      cards: n.cards,
                    ),
                ],
              ),
          ];
    return ParsedPackage(
      decks: fixed,
      hasProgress: manifest['progress'] == true,
      mediaAdded: added,
      mediaSkipped: skipped,
    );
  } on ExchangeError {
    rethrow;
  } on Object {
    // JSON invalide, champ manquant ou de mauvais type, zip tronqué…
    throw const ExchangeError(ImportProblem.corrupt);
  }
}

/// Nom de fichier proposé pour un export.
String packageFileName(String base) {
  final clean = base
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${clean.isEmpty ? 'paquet' : clean}.$carabinExtension';
}
