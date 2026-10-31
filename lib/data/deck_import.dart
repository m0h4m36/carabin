import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/csv_import.dart';
import '../domain/exchange.dart';
import 'anki_package.dart';
import 'background.dart';
import 'carabin_package.dart';
import 'database.dart';
import 'deck_exchange.dart';
import 'errors.dart';

/// Sorte de fichier d'après son extension.
enum ImportKind { carabin, anki, text, unknown }

ImportKind importKindOf(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (ext == carabinExtension) return ImportKind.carabin;
  if (ankiExtensions.contains(ext)) return ImportKind.anki;
  if (textExtensions.contains(ext)) return ImportKind.text;
  return ImportKind.unknown;
}

/// Extensions de fichiers texte importables.
const textExtensions = ['csv', 'tsv', 'txt'];

/// Toutes les extensions que l'import de cartes accepte.
List<String> get importableExtensions => [
  carabinExtension,
  ...ankiExtensions,
  ...textExtensions,
];

/// Lit un paquet Carabin ou Anki hors du fil de l'interface. Les images sont
/// rangées dans [mediaDir] dès la lecture.
Future<ParsedPackage> readPackage(
  String path,
  String mediaDir, {
  required ImportKind kind,
  required String unnamedDeck,
  required int nowMs,
}) {
  switch (kind) {
    case ImportKind.carabin:
      return Background.run(() => readCarabinPackage(path, mediaDir));
    case ImportKind.anki:
      return Background.run(
        () => readAnkiPackage(
          path,
          mediaDir,
          withProgress: true,
          unnamedDeck: unnamedDeck,
          nowMs: nowMs,
        ),
      );
    case ImportKind.text:
    case ImportKind.unknown:
      throw const ExchangeError(ImportProblem.unreadable);
  }
}

/// Fichier texte lu : lignes de cellules et réglages proposés.
class TextTable {
  TextTable(this.rows, this.directives, this.mapping);

  final List<List<String>> rows;
  final CsvDirectives directives;
  final CsvMapping mapping;

  int get width => rows.fold(0, (m, r) => r.length > m ? r.length : m);
}

/// Lit un fichier texte (CSV, TSV, export texte d'Anki) et propose une
/// correspondance de colonnes.
Future<TextTable> readTextTable(String path) async {
  final String text;
  try {
    text = await Background.run(() => decodeText(File(path).readAsBytesSync()));
  } on Object {
    // fichier disparu, droits refusés, erreur renvoyée par l'isolat…
    throw const ExchangeError(ImportProblem.unreadable);
  }
  final (:directives, :body) = extractDirectives(text);
  final delimiter = directives.separator ?? detectDelimiter(body);
  final rows = parseDelimited(body, delimiter);
  if (rows.isEmpty || rows.every((r) => r.every((c) => c.trim().isEmpty))) {
    throw const ExchangeError(ImportProblem.noColumns);
  }
  return TextTable(rows, directives, suggestMapping(rows, directives));
}

/// Applique des paquets lus à la base, par tranches pour laisser l'écran
/// respirer. Tout est validé d'un coup à la fin (ou rien du tout).
///
/// - [progress] : reprendre l'avancement des cartes quand il est présent ;
/// - chaque paquet du fichier est créé ou complété sous son nom ;
/// - [onProgress] : nombre de notes traitées sur le total.
Future<ImportReport> applyPackage(
  AppDatabase db,
  DeckExchange exchange,
  ParsedPackage parsed, {
  required bool progress,
  required int nowMs,
  void Function(int done, int total)? onProgress,
  int sliceSize = 200,
}) {
  final total = parsed.decks.fold<int>(0, (s, d) => s + d.notes.length);
  return db.batch(() async {
    final report = ImportReport()
      ..mediaAdded = parsed.mediaAdded
      ..mediaSkipped = parsed.mediaSkipped
      ..notesSkipped = parsed.notesSkipped
      ..imagesDropped = parsed.imagesDropped
      ..soundsDropped = parsed.soundsDropped
      ..shapesApproximated = parsed.shapesApproximated
      ..shapesDropped = parsed.shapesDropped;
    var done = 0;
    for (final d in parsed.decks) {
      final target = exchange.ensureDeck(d.name, options: d.options);
      if (target.created) report.decksCreated++;
      if (!report.deckNames.contains(target.deck.name)) {
        report.deckNames.add(target.deck.name);
      }
      for (var i = 0; i < d.notes.length; i += sliceSize) {
        final end = i + sliceSize < d.notes.length
            ? i + sliceSize
            : d.notes.length;
        exchange.importNotes(
          target.deck,
          d.notes.sublist(i, end),
          report,
          progress: progress,
          nowMs: nowMs,
        );
        done += end - i;
        onProgress?.call(done, total);
        await Future<void>.delayed(Duration.zero);
      }
    }
    return report;
  });
}

/// Notes d'un fichier texte rangées par paquet ; les lignes sans paquet vont
/// dans [defaultDeck].
ParsedPackage packageFromText(CsvConversion c, {required String defaultDeck}) {
  final byName = <String, List<IncomingNote>>{};
  c.byDeck.forEach((key, notes) {
    (byName[key.isEmpty ? defaultDeck : key] ??= []).addAll(notes);
  });
  return ParsedPackage(
    decks: [
      for (final e in byName.entries) IncomingDeck(name: e.key, notes: e.value),
    ],
    hasProgress: false,
    notesSkipped: c.skipped,
    imagesDropped: c.droppedImages,
    soundsDropped: c.droppedSounds,
  );
}
