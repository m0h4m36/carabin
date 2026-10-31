import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_session.dart';
import '../../data/background.dart';
import '../../data/deck_import.dart';
import '../../data/errors.dart';
import '../../data/carabin_package.dart';
import '../../domain/csv_import.dart';
import '../../domain/exchange.dart';
import '../../domain/note_types.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_import.dart';
import '../../ui/busy_dialog.dart';
import '../../ui/dialogs.dart';
import '../../ui/pickers.dart';

/// Importe des cartes depuis un fichier choisi par l'utilisateur : paquet
/// Carabin, paquet Anki (`.apkg`, `.colpkg`) ou fichier texte (CSV, TSV).
Future<void> importCardsFlow(BuildContext context) async {
  final String? path;
  try {
    path = await Pickers.file(importableExtensions);
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (path == null || !context.mounted) return;
  switch (importKindOf(path)) {
    case ImportKind.unknown:
      showInfo(context, TxImport.unknownFile);
    case ImportKind.text:
      await _importText(context, path);
    case ImportKind.carabin:
    case ImportKind.anki:
      await _importPackage(context, path);
  }
}

Future<void> _importPackage(BuildContext context, String path) async {
  final session = context.read<Session>();
  final kind = importKindOf(path);
  final nowMs = session.flashcards.now().millisecondsSinceEpoch;
  final busy = BusyDialog.show(context, TxImport.importing);
  ParsedPackage parsed;
  try {
    parsed = await readPackage(
      path,
      session.workspace.mediaDir,
      kind: kind,
      unnamedDeck: TxImport.unnamedDeck,
      nowMs: nowMs,
    );
  } on Object catch (e) {
    busy.close();
    if (context.mounted) showError(context, e);
    return;
  }
  busy.close();
  if (!context.mounted) return;

  var keepProgress = false;
  if (parsed.hasProgress) {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(TxImport.keepProgressTitle),
        content: const Text(TxImport.keepProgressMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(TxImport.keepProgressNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(TxImport.keepProgressYes),
          ),
        ],
      ),
    );
    if (answer == null || !context.mounted) return;
    keepProgress = answer;
  }
  await _apply(context, parsed, progress: keepProgress);
}

/// Applique un fichier lu à la base et montre le compte rendu.
Future<void> _apply(
  BuildContext context,
  ParsedPackage parsed, {
  required bool progress,
}) async {
  final session = context.read<Session>();
  final busy = BusyDialog.show(context, TxImport.importing);
  final ImportReport report;
  try {
    report = await applyPackage(
      session.db,
      session.exchange,
      parsed,
      progress: progress,
      nowMs: session.flashcards.now().millisecondsSinceEpoch,
      onProgress: (done, total) =>
          busy.update('${TxImport.importing} $done / $total'),
    );
  } on Object catch (e) {
    busy.close();
    if (context.mounted) showError(context, e);
    return;
  }
  busy.close();
  if (context.mounted) await _showReport(context, report);
}

// ------------------------------------------------------------ fichier texte

Future<void> _importText(BuildContext context, String path) async {
  final session = context.read<Session>();
  final busy = BusyDialog.show(context, TxImport.importing);
  final TextTable table;
  try {
    table = await readTextTable(path);
  } on Object catch (e) {
    busy.close();
    if (context.mounted) showError(context, e);
    return;
  }
  busy.close();
  if (!context.mounted) return;

  final choice = await showDialog<TextImportChoice>(
    context: context,
    builder: (_) => TextImportDialog(
      table: table,
      defaultDeck: _baseName(path),
      nowMs: session.flashcards.now().millisecondsSinceEpoch,
    ),
  );
  if (choice == null || !context.mounted) return;

  final nowMs = session.flashcards.now().millisecondsSinceEpoch;
  final busy2 = BusyDialog.show(context, TxImport.importing);
  final ParsedPackage parsed;
  try {
    final rows = table.rows;
    final mapping = choice.mapping;
    final conversion = await Background.run(
      () => convertCsv(rows, mapping, nowMs: nowMs),
    );
    parsed = packageFromText(conversion, defaultDeck: choice.deck);
    if (parsed.decks.isEmpty) throw const ExchangeError(ImportProblem.empty);
  } on Object catch (e) {
    busy2.close();
    if (context.mounted) showError(context, e);
    return;
  }
  busy2.close();
  if (context.mounted) await _apply(context, parsed, progress: false);
}

String _baseName(String path) {
  final file = path.split(RegExp(r'[\\/]')).last;
  final dot = file.lastIndexOf('.');
  final base = dot > 0 ? file.substring(0, dot) : file;
  return base.trim().isEmpty ? TxImport.unnamedDeck : base.trim();
}

/// Réglages choisis pour un fichier texte.
class TextImportChoice {
  const TextImportChoice(this.mapping, this.deck);
  final CsvMapping mapping;
  final String deck;
}

/// Fenêtre où l'on indique à quoi sert chaque colonne d'un fichier texte.
class TextImportDialog extends StatefulWidget {
  const TextImportDialog({
    super.key,
    required this.table,
    required this.defaultDeck,
    required this.nowMs,
  });

  final TextTable table;
  final String defaultDeck;
  final int nowMs;

  @override
  State<TextImportDialog> createState() => _TextImportDialogState();
}

class _TextImportDialogState extends State<TextImportDialog> {
  static const _sample = 300;

  late CsvMapping _mapping = widget.table.mapping;
  late final TextEditingController _deck = TextEditingController(
    text: widget.defaultDeck,
  );

  @override
  void dispose() {
    _deck.dispose();
    super.dispose();
  }

  List<List<String>> get _rows => widget.table.rows;

  CsvConversion get _preview => convertCsv(
    _rows.length > _sample ? _rows.sublist(0, _sample) : _rows,
    _mapping,
    nowMs: widget.nowMs,
  );

  String _sampleOf(int column) {
    final data = _mapping.hasHeader && _rows.length > 1
        ? _rows[1]
        : _rows.first;
    final v = column < data.length ? data[column].trim() : '';
    if (v.isEmpty) return TxImport.emptyCell;
    final flat = v.replaceAll(RegExp(r'\s+'), ' ');
    return flat.length > 28 ? '${flat.substring(0, 28)}…' : flat;
  }

  String _columnLabel(int i) {
    final title = _mapping.hasHeader && _rows.first.length > i
        ? _rows.first[i].trim()
        : '';
    final head = title.isNotEmpty ? title : TxImport.columnName(i);
    return '$head — ${_sampleOf(i)}';
  }

  Widget _picker({
    required String keyName,
    required String label,
    required int? value,
    required bool optional,
    required ValueChanged<int?> onChanged,
    String? helper,
  }) {
    final width = widget.table.width;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$keyName-${value ?? 'none'}-${_mapping.hasHeader}'),
        initialValue: value != null && value < width
            ? value
            : (optional ? -1 : null),
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        items: [
          if (optional)
            const DropdownMenuItem<int>(value: -1, child: Text(TxImport.none)),
          for (var i = 0; i < width; i++)
            DropdownMenuItem(
              value: i,
              child: Text(_columnLabel(i), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => onChanged(v == null || v < 0 ? null : v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloze = _mapping.type == NoteType.cloze;
    final preview = _preview;
    final first = preview.byDeck.values.expand((l) => l).take(3).toList();
    final partial = _rows.length > _sample;
    final canImport =
        _mapping.front != null &&
        preview.total > 0 &&
        _deck.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text(TxImport.textTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(TxImport.textHelp, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<NoteType>(
                key: ValueKey('type-${_mapping.type.name}'),
                initialValue: _mapping.type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: TxImport.cardType,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in TxImport.textTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(TxImport.typeName(t)),
                    ),
                ],
                onChanged: (t) {
                  if (t == null) return;
                  setState(() {
                    _mapping = _mapping.copyWith(
                      type: t,
                      back: t == NoteType.cloze
                          ? null
                          : (_mapping.back ?? _firstFree()),
                    );
                  });
                },
              ),
              SwitchListTile(
                key: const ValueKey('header-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text(TxImport.firstRowIsHeader),
                value: _mapping.hasHeader,
                onChanged: (v) => setState(() {
                  _mapping = _mapping.copyWith(hasHeader: v);
                }),
              ),
              SwitchListTile(
                key: const ValueKey('html-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text(TxImport.containsHtml),
                value: _mapping.html,
                onChanged: (v) => setState(() {
                  _mapping = _mapping.copyWith(html: v);
                }),
              ),
              _picker(
                keyName: 'col-front',
                label: cloze ? TxImport.columnText : TxImport.columnFront,
                value: _mapping.front,
                optional: false,
                onChanged: (v) =>
                    setState(() => _mapping = _mapping.copyWith(front: v)),
              ),
              if (!cloze)
                _picker(
                  keyName: 'col-back',
                  label: TxImport.columnBack,
                  value: _mapping.back,
                  optional: false,
                  onChanged: (v) =>
                      setState(() => _mapping = _mapping.copyWith(back: v)),
                ),
              _picker(
                keyName: 'col-extra',
                label: TxImport.columnExtra,
                value: _mapping.extra,
                optional: true,
                onChanged: (v) =>
                    setState(() => _mapping = _mapping.copyWith(extra: v)),
              ),
              _picker(
                keyName: 'col-tags',
                label: TxImport.columnTags,
                value: _mapping.tags,
                optional: true,
                onChanged: (v) =>
                    setState(() => _mapping = _mapping.copyWith(tags: v)),
              ),
              _picker(
                keyName: 'col-deck',
                label: TxImport.columnDeck,
                value: _mapping.deck,
                optional: true,
                onChanged: (v) =>
                    setState(() => _mapping = _mapping.copyWith(deck: v)),
              ),
              _picker(
                keyName: 'col-guid',
                label: TxImport.columnId,
                helper: TxImport.columnIdHelp,
                value: _mapping.guid,
                optional: true,
                onChanged: (v) =>
                    setState(() => _mapping = _mapping.copyWith(guid: v)),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('target-deck'),
                controller: _deck,
                decoration: InputDecoration(
                  labelText: TxImport.targetDeck,
                  helperText: _mapping.deck == null
                      ? TxImport.targetDeckHint
                      : TxImport.targetDeckByColumn,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(TxImport.preview, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                TxImport.rowsSummary(preview.total, preview.skipped) +
                    (partial ? TxImport.sampleNote(_sample) : ''),
                key: const ValueKey('rows-summary'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final n in first)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PreviewTile(n),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(Tx.cancel),
        ),
        FilledButton(
          key: const ValueKey('text-import-confirm'),
          onPressed: canImport
              ? () => Navigator.pop(
                  context,
                  TextImportChoice(_mapping, _deck.text.trim()),
                )
              : null,
          child: const Text(TxImport.importButton),
        ),
      ],
    );
  }

  /// Première colonne pas encore utilisée (pour le verso quand on quitte le
  /// texte à trous).
  int? _firstFree() {
    final used = {
      _mapping.front,
      _mapping.extra,
      _mapping.tags,
      _mapping.deck,
      _mapping.guid,
    };
    for (var i = 0; i < widget.table.width; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile(this.note);
  final IncomingNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloze = note.type == NoteType.cloze;
    final front = stripRich(note.fields.text(cloze ? 'text' : 'front'));
    final back = cloze ? '' : stripRich(note.fields.text('back'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(front, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (back.isNotEmpty)
            Text(
              back,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ compte rendu

Future<void> _showReport(BuildContext context, ImportReport r) {
  final lines = <String>[];
  if (!r.changedAnything && r.notesPresent > 0) {
    lines.add(TxImport.reportNothing);
  } else {
    if (r.notesAdded > 0) lines.add(TxImport.reportAdded(r.notesAdded));
    if (r.notesUpdated > 0) lines.add(TxImport.reportUpdated(r.notesUpdated));
    if (r.notesPresent > 0) lines.add(TxImport.reportPresent(r.notesPresent));
    if (r.decksCreated > 0) lines.add(TxImport.reportCreated(r.decksCreated));
    if (r.cardsProgressed > 0 || r.logsAdded > 0) {
      lines.add(TxImport.reportProgress(r.cardsProgressed, r.logsAdded));
    }
    if (r.mediaAdded > 0) lines.add(TxImport.reportImages(r.mediaAdded));
  }
  if (r.notesSkipped > 0) lines.add(TxImport.reportSkipped(r.notesSkipped));
  if (r.imagesDropped > 0) {
    lines.add(TxImport.reportImagesDropped(r.imagesDropped));
  }
  if (r.soundsDropped > 0) lines.add(TxImport.reportSounds(r.soundsDropped));
  if (r.shapesApproximated > 0) {
    lines.add(TxImport.reportShapes(r.shapesApproximated));
  }
  if (r.shapesDropped > 0) {
    lines.add(TxImport.reportShapesDropped(r.shapesDropped));
  }
  if (r.deckNames.isNotEmpty) lines.add(TxImport.reportDecks(r.deckNames));
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(TxImport.reportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('import-report-close'),
          onPressed: () => Navigator.pop(ctx),
          child: const Text(TxImport.close),
        ),
      ],
    ),
  );
}
