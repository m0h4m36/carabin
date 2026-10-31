import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_session.dart';
import '../../data/background.dart';
import '../../data/carabin_package.dart';
import '../../data/flashcard_models.dart';
import '../../data/media_store.dart';
import '../../l10n/textes_import.dart';
import '../../ui/busy_dialog.dart';
import '../../ui/dialogs.dart';
import '../../ui/pickers.dart';

/// Exporte un deck en fichier `.carabin`, avec ou sans l'avancement des
/// cartes (sans : pour le partager ; avec : pour le passer à un autre
/// appareil).
Future<void> exportDeckFlow(
  BuildContext context,
  Deck deck, {
  required bool progress,
}) => _export(context, [deck], progress: progress, baseName: deck.name);

/// Exporte tous les decks avec leur progression (sauvegarde ou changement
/// d'appareil).
Future<void> exportAllFlow(BuildContext context) {
  final session = context.read<Session>();
  final decks = session.flashcards.decks();
  if (decks.isEmpty) {
    showInfo(context, TxImport.exportNothing);
    return Future.value();
  }
  return _export(
    context,
    decks,
    progress: true,
    baseName: TxImport.exportAllName,
  );
}

Future<void> _export(
  BuildContext context,
  List<Deck> decks, {
  required bool progress,
  required String baseName,
}) async {
  final session = context.read<Session>();
  final busy = BusyDialog.show(context, TxImport.exporting);
  final List<int> bytes;
  try {
    final incoming = [
      for (final d in decks)
        session.exchange.exportDeck(d.id, progress: progress),
    ];
    final mediaDir = session.workspace.mediaDir;
    bytes = await Background.run(
      () => buildCarabinPackage(
        decks: incoming,
        progress: progress,
        media: MediaStore(mediaDir),
      ),
    );
  } on Object catch (e) {
    busy.close();
    if (context.mounted) showError(context, e);
    return;
  }
  busy.close();
  if (!context.mounted) return;
  final fileName = packageFileName(baseName);
  final bool saved;
  try {
    saved = await Pickers.save(fileName, Uint8List.fromList(bytes));
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (saved && context.mounted) {
    showInfo(context, TxImport.exportDone(fileName));
  }
}
