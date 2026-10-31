import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:libcompress/libcompress.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../domain/anki_convert.dart';
import '../domain/anki_template.dart';
import '../domain/exchange.dart';
import '../domain/html_text.dart';
import '../domain/note_types.dart';
import '../domain/scheduling.dart';
import 'carabin_package.dart';
import 'errors.dart';
import 'media_store.dart';

/// Extensions des paquets Anki.
const ankiExtensions = ['apkg', 'colpkg'];

const _fieldSeparator = '\x1f';

/// Lit un paquet Anki (`.apkg`, `.colpkg`) : les notes, leurs cartes, et
/// éventuellement l'avancement ; les images vont dans [mediaDir].
///
/// Gère les trois formats de collection (`collection.anki2`,
/// `collection.anki21`, `collection.anki21b` compressé en zstd) et les deux
/// façons de nommer les médias. Peut durer : à lancer dans un isolat pour les
/// gros paquets.
///
/// Reprise des types de notes : « Texte à trous » (y compris l'occlusion
/// d'image intégrée à Anki) ; les modèles à une carte, à carte inverse ou « à
/// saisir » ; tout autre type est repris carte par carte, en recto-verso, à
/// partir de ce que ses modèles affichent.
ParsedPackage readAnkiPackage(
  String path,
  String mediaDir, {
  required bool withProgress,
  required String unnamedDeck,
  required int nowMs,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeStream(InputFileStream(path));
  } on Object {
    throw const ExchangeError(ImportProblem.unreadable);
  }
  final entries = <String, ArchiveFile>{
    for (final f in archive.files)
      if (f.isFile) f.name: f,
  };

  final collection = _collectionBytes(entries);
  final tmp = Directory.systemTemp.createTempSync('carabin_anki_');
  try {
    final dbPath = p.join(tmp.path, 'collection.sqlite');
    File(dbPath).writeAsBytesSync(collection, flush: true);
    return _AnkiImporter(
      dbPath: dbPath,
      entries: entries,
      media: MediaStore(mediaDir),
      withProgress: withProgress,
      unnamedDeck: unnamedDeck,
      nowMs: nowMs,
    ).run();
  } on ExchangeError {
    rethrow;
  } on Object catch (e) {
    // base illisible, colonne absente, JSON invalide…
    throw ExchangeError(ImportProblem.corrupt, '$e');
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // dossier temporaire : le système le videra
    }
  }
}

// ------------------------------------------------------------- compression

bool _isZstd(Uint8List b) =>
    b.length >= 4 &&
    b[0] == 0x28 &&
    b[1] == 0xB5 &&
    b[2] == 0x2F &&
    b[3] == 0xFD;

final _zstd = ZstdCodec(maxSize: 1 << 31);

Uint8List _maybeDecompress(Uint8List b) => _isZstd(b) ? _zstd.decompress(b) : b;

const _sqliteHeader = 'SQLite format 3\u0000';

bool _isSqlite(Uint8List b) {
  if (b.length < _sqliteHeader.length) return false;
  for (var i = 0; i < _sqliteHeader.length; i++) {
    if (b[i] != _sqliteHeader.codeUnitAt(i)) return false;
  }
  return true;
}

/// La collection la plus récente du paquet, décompressée.
Uint8List _collectionBytes(Map<String, ArchiveFile> entries) {
  for (final name in [
    'collection.anki21b',
    'collection.anki21',
    'collection.anki2',
  ]) {
    final f = entries[name];
    if (f == null) continue;
    final raw = f.readBytes();
    if (raw == null) throw const ExchangeError(ImportProblem.corrupt);
    Uint8List bytes;
    try {
      bytes = _maybeDecompress(raw);
    } on Object {
      // le format récent n'a pas pu être décompressé : l'ancien format est la
      // solution
      throw ExchangeError(
        name == 'collection.anki21b'
            ? ImportProblem.ankiNeedsOlderFormat
            : ImportProblem.corrupt,
      );
    }
    if (!_isSqlite(bytes)) throw const ExchangeError(ImportProblem.corrupt);
    return bytes;
  }
  throw const ExchangeError(ImportProblem.unreadable);
}

// ---------------------------------------------------------------- protobuf

/// Lecteur minimal de messages protobuf (les seuls champs utiles à l'import).
class _Proto {
  _Proto(this._b);

  final Uint8List _b;
  int _pos = 0;

  bool get done => _pos >= _b.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _b.length || shift > 63) {
        throw const FormatException('protobuf tronqué');
      }
      final byte = _b[_pos++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  (int, int) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || _pos + n > _b.length) {
      throw const FormatException('protobuf tronqué');
    }
    final out = Uint8List.sublistView(_b, _pos, _pos + n);
    _pos += n;
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _advance(8);
      case 2:
        bytes();
      case 5:
        _advance(4);
      default:
        throw const FormatException('type protobuf inconnu');
    }
  }

  void _advance(int n) {
    if (_pos + n > _b.length) throw const FormatException('protobuf tronqué');
    _pos += n;
  }
}

String _utf8(Uint8List b) => utf8.decode(b, allowMalformed: true);

/// Noms des médias, dans l'ordre : le n-ième est le fichier `n` de l'archive.
List<String> _parseMediaList(Uint8List data) {
  final names = <String>[];
  final r = _Proto(data);
  while (!r.done) {
    final (field, wire) = r.tag();
    if (field == 1 && wire == 2) {
      final entry = _Proto(r.bytes());
      var name = '';
      while (!entry.done) {
        final (f, w) = entry.tag();
        if (f == 1 && w == 2) {
          name = _utf8(entry.bytes());
        } else {
          entry.skip(w);
        }
      }
      names.add(name);
    } else {
      r.skip(wire);
    }
  }
  return names;
}

({String question, String answer}) _parseTemplateConfig(Uint8List data) {
  var q = '', a = '';
  final r = _Proto(data);
  while (!r.done) {
    final (field, wire) = r.tag();
    if (field == 1 && wire == 2) {
      q = _utf8(r.bytes());
    } else if (field == 2 && wire == 2) {
      a = _utf8(r.bytes());
    } else {
      r.skip(wire);
    }
  }
  return (question: q, answer: a);
}

bool _notetypeIsCloze(Uint8List data) {
  final r = _Proto(data);
  while (!r.done) {
    final (field, wire) = r.tag();
    if (field == 1 && wire == 0) return r.varint() == 1;
    r.skip(wire);
  }
  return false;
}

bool _deckIsFiltered(Uint8List kind) {
  final r = _Proto(kind);
  while (!r.done) {
    final (field, wire) = r.tag();
    if (field == 2) return true;
    r.skip(wire);
  }
  return false;
}

// ---------------------------------------------------------------- collection

class _Template {
  _Template(this.name, this.question, this.answer);
  final String name;
  final String question;
  final String answer;
}

class _Model {
  _Model(this.id, this.name, this.isCloze, this.fields, this.templates);
  final int id;
  final String name;
  final bool isCloze;
  final List<String> fields;
  final List<_Template> templates;

  int fieldIndex(String name) {
    final i = fields.indexOf(name);
    if (i >= 0) return i;
    final lower = name.toLowerCase();
    return fields.indexWhere((f) => f.toLowerCase() == lower);
  }
}

class _AnkiCard {
  _AnkiCard(Row r)
    : id = _int(r['id']),
      noteId = _int(r['nid']),
      deckId = _int(r['odid']) != 0 ? _int(r['odid']) : _int(r['did']),
      ord = _int(r['ord']),
      type = _int(r['type']),
      queue = _int(r['queue']),
      due = _int(r['odid']) != 0 && _int(r['odue']) != 0
          ? _int(r['odue'])
          : _int(r['due']),
      ivl = _int(r['ivl']),
      factor = _int(r['factor']),
      reps = _int(r['reps']),
      lapses = _int(r['lapses']),
      data = (r['data'] ?? '').toString();

  final int id,
      noteId,
      deckId,
      ord,
      type,
      queue,
      due,
      ivl,
      factor,
      reps,
      lapses;
  final String data;
}

int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Ce que donne la conversion d'une note Anki : une ou plusieurs notes
/// Carabin, avec la correspondance entre numéros de cartes.
class _Converted {
  _Converted(this.type, this.fields, this.ordMap, [this.suffix = '']);
  final NoteType type;
  final NoteFields fields;

  /// Numéro de carte Anki → numéro de carte Carabin.
  final Map<int, int> ordMap;
  final String suffix;
}

final _imgSrc = RegExp(
  r'''<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  caseSensitive: false,
);

class _AnkiImporter {
  _AnkiImporter({
    required this.dbPath,
    required this.entries,
    required this.media,
    required this.withProgress,
    required this.unnamedDeck,
    required this.nowMs,
  });

  final String dbPath;
  final Map<String, ArchiveFile> entries;
  final MediaStore media;
  final bool withProgress;
  final String unnamedDeck;
  final int nowMs;

  late final HtmlConverter _html = HtmlConverter(image: _resolveImage);
  final Map<int, _Model> _models = {};
  final Map<int, String> _decks = {};
  final Set<int> _filteredDecks = {};
  int _created = 0;

  // médias
  late final Map<String, String> _mediaFiles = _loadMediaIndex();
  final Map<String, String?> _imageCache = {};
  final Set<String> _storedImages = {};
  int _mediaSkipped = 0;

  // décomptes
  int _notesSkipped = 0;
  int _shapesApproximated = 0;
  int _shapesDropped = 0;

  ParsedPackage run() {
    final db = sqlite3.open(dbPath);
    try {
      // les collections récentes déclarent des colonnes `COLLATE unicase`
      db.createCollation(
        name: 'unicase',
        function: (a, b) =>
            (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase()),
      );
      _loadModelsAndDecks(db);
      _rejectPlaceholder(db);

      final cards = <int, List<_AnkiCard>>{};
      for (final r in db.select(
        'SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses, '
        'odue, odid, data FROM cards',
      )) {
        final c = _AnkiCard(r);
        (cards[c.noteId] ??= []).add(c);
      }
      for (final l in cards.values) {
        l.sort((a, b) => a.ord.compareTo(b.ord));
      }
      final reviews = withProgress
          ? _loadReviews(db)
          : const <int, List<AnkiReview>>{};

      final byDeck = <String, List<IncomingNote>>{};
      final stmt = db.prepare(
        'SELECT id, guid, mid, mod, tags, flds FROM notes ORDER BY id',
      );
      try {
        final cursor = stmt.selectCursor();
        while (cursor.moveNext()) {
          _importNote(cursor.current, cards, reviews, byDeck);
        }
      } finally {
        stmt.close();
      }

      if (byDeck.isEmpty) throw const ExchangeError(ImportProblem.empty);
      return ParsedPackage(
        decks: [
          for (final e in byDeck.entries)
            IncomingDeck(name: e.key, notes: e.value),
        ],
        hasProgress:
            withProgress &&
            byDeck.values.any((l) => l.any((n) => n.cards.isNotEmpty)),
        mediaAdded: _storedImages.length,
        mediaSkipped: _mediaSkipped,
        notesSkipped: _notesSkipped,
        imagesDropped: _html.droppedImages,
        soundsDropped: _html.droppedSounds,
        shapesApproximated: _shapesApproximated,
        shapesDropped: _shapesDropped,
      );
    } finally {
      db.close();
    }
  }

  // ------------------------------------------------------- types et paquets

  bool _hasTable(Database db, String name) => db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  ).isNotEmpty;

  void _loadModelsAndDecks(Database db) {
    final col = db.select('SELECT crt, models, decks FROM col LIMIT 1');
    if (col.isEmpty) throw const ExchangeError(ImportProblem.corrupt);
    _created = _int(col.first['crt']);

    if (_hasTable(db, 'notetypes')) {
      final fields = <int, List<String>>{};
      for (final r in db.select(
        'SELECT ntid, ord, name FROM fields ORDER BY ntid, ord',
      )) {
        (fields[_int(r['ntid'])] ??= []).add(r['name'].toString());
      }
      final templates = <int, List<_Template>>{};
      for (final r in db.select(
        'SELECT ntid, ord, name, config FROM templates ORDER BY ntid, ord',
      )) {
        final cfg = _parseTemplateConfig(r['config'] as Uint8List);
        (templates[_int(r['ntid'])] ??= []).add(
          _Template(r['name'].toString(), cfg.question, cfg.answer),
        );
      }
      for (final r in db.select('SELECT id, name, config FROM notetypes')) {
        final id = _int(r['id']);
        _models[id] = _Model(
          id,
          r['name'].toString(),
          _notetypeIsCloze(r['config'] as Uint8List),
          fields[id] ?? const [],
          templates[id] ?? const [],
        );
      }
      for (final r in db.select('SELECT id, name, kind FROM decks')) {
        final id = _int(r['id']);
        _decks[id] = r['name'].toString();
        if (_deckIsFiltered(r['kind'] as Uint8List)) _filteredDecks.add(id);
      }
      return;
    }

    // ancien format : tout est en JSON dans la table `col`
    final models =
        jsonDecode(col.first['models'].toString()) as Map<String, dynamic>;
    for (final e in models.entries) {
      final m = e.value as Map<String, dynamic>;
      List<Map<String, dynamic>> sorted(Object? l) => [
        for (final x in (l as List? ?? const []))
          (x as Map).cast<String, dynamic>(),
      ]..sort((a, b) => _int(a['ord']).compareTo(_int(b['ord'])));
      final id = int.tryParse(e.key) ?? _int(m['id']);
      _models[id] = _Model(
        id,
        (m['name'] ?? '').toString(),
        _int(m['type']) == 1,
        [for (final f in sorted(m['flds'])) (f['name'] ?? '').toString()],
        [
          for (final t in sorted(m['tmpls']))
            _Template(
              (t['name'] ?? '').toString(),
              (t['qfmt'] ?? '').toString(),
              (t['afmt'] ?? '').toString(),
            ),
        ],
      );
    }
    final decks =
        jsonDecode(col.first['decks'].toString()) as Map<String, dynamic>;
    for (final e in decks.entries) {
      final d = e.value as Map<String, dynamic>;
      final id = int.tryParse(e.key) ?? _int(d['id']);
      _decks[id] = (d['name'] ?? '').toString();
      if (_int(d['dyn']) == 1) _filteredDecks.add(id);
    }
  }

  /// Les paquets exportés « sans compatibilité » contiennent, dans l'ancien
  /// fichier, une seule note qui demande de mettre Anki à jour.
  void _rejectPlaceholder(Database db) {
    final n = db.select('SELECT COUNT(*) AS n FROM notes').first['n'] as int;
    if (n != 1) return;
    final flds = db
        .select('SELECT flds FROM notes LIMIT 1')
        .first['flds']
        .toString();
    if (flds.contains('update to the latest Anki version')) {
      throw const ExchangeError(ImportProblem.ankiNeedsOlderFormat);
    }
  }

  Map<int, List<AnkiReview>> _loadReviews(Database db) {
    if (!_hasTable(db, 'revlog')) return const {};
    final out = <int, List<AnkiReview>>{};
    final stmt = db.prepare(
      'SELECT id, cid, ease, ivl, time, type FROM revlog',
    );
    try {
      final cursor = stmt.selectCursor();
      while (cursor.moveNext()) {
        final r = cursor.current;
        (out[_int(r['cid'])] ??= []).add(
          AnkiReview(
            id: _int(r['id']),
            ease: _int(r['ease']),
            ivl: _int(r['ivl']),
            time: _int(r['time']),
            type: _int(r['type']),
          ),
        );
      }
    } finally {
      stmt.close();
    }
    return out;
  }

  // ------------------------------------------------------------------ médias

  Map<String, String> _loadMediaIndex() {
    final f = entries['media'];
    final raw = f?.readBytes();
    if (raw == null || raw.isEmpty) return const {};
    try {
      final data = _maybeDecompress(raw);
      var i = 0;
      while (i < data.length &&
          (data[i] == 0x20 || data[i] == 0x0A || data[i] == 0x0D)) {
        i++;
      }
      if (i < data.length && data[i] == 0x7B) {
        // JSON : { "0": "image.jpg", … }
        final j = jsonDecode(utf8.decode(data, allowMalformed: true));
        return {
          if (j is Map)
            for (final e in j.entries) e.value.toString(): e.key.toString(),
        };
      }
      final names = _parseMediaList(data);
      return {
        for (var k = 0; k < names.length; k++)
          if (names[k].isNotEmpty) names[k]: '$k',
      };
    } on Object {
      return const {};
    }
  }

  Uint8List? _mediaBytes(String zipName) {
    final f = entries[zipName];
    final raw = f?.readBytes();
    if (raw == null) return null;
    try {
      return _maybeDecompress(raw);
    } on Object {
      return null;
    }
  }

  /// Nom Carabin de l'image citée par un `src` HTML, ou null.
  String? _resolveImage(String src) {
    if (_imageCache.containsKey(src)) return _imageCache[src];
    final stored = _storeImage(src);
    _imageCache[src] = stored;
    return stored;
  }

  String? _storeImage(String src) {
    final lower = src.toLowerCase();
    if (lower.startsWith('data:')) return _storeDataUri(src);
    if (lower.startsWith('http:') ||
        lower.startsWith('https:') ||
        lower.startsWith('file:')) {
      _mediaSkipped++;
      return null;
    }
    final candidates = <String>[src];
    try {
      candidates.add(Uri.decodeComponent(src));
    } on Object {
      // pourcentage invalide (ArgumentError, FormatException) : le nom brut
      // suffit
    }
    for (final c in candidates) {
      final zipName = _mediaFiles[c];
      if (zipName == null) continue;
      final ext = MediaStore.imageExtension(c);
      final bytes = ext == null ? null : _mediaBytes(zipName);
      if (ext == null || bytes == null || bytes.isEmpty) {
        _mediaSkipped++;
        return null;
      }
      final name = media.addBytes(bytes, ext);
      _storedImages.add(name);
      return name;
    }
    _mediaSkipped++;
    return null;
  }

  String? _storeDataUri(String src) {
    final m = RegExp(
      r'^data:image/(png|jpeg|jpg|gif|webp|bmp);base64,(.*)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(src);
    if (m == null) {
      _mediaSkipped++;
      return null;
    }
    try {
      final bytes = base64Decode(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      final ext = MediaStore.imageExtension('x.${m.group(1)!.toLowerCase()}');
      if (ext == null || bytes.isEmpty) {
        _mediaSkipped++;
        return null;
      }
      final name = media.addBytes(Uint8List.fromList(bytes), ext);
      _storedImages.add(name);
      return name;
    } on FormatException {
      _mediaSkipped++;
      return null;
    }
  }

  // ------------------------------------------------------------------- notes

  String _text(String html) => _html.convert(html).trim();

  void _importNote(
    Row row,
    Map<int, List<_AnkiCard>> cardsByNote,
    Map<int, List<AnkiReview>> reviews,
    Map<String, List<IncomingNote>> byDeck,
  ) {
    final noteId = _int(row['id']);
    final model = _models[_int(row['mid'])];
    final cards = cardsByNote[noteId];
    if (model == null || cards == null || cards.isEmpty) {
      _notesSkipped++;
      return;
    }
    final values = row['flds'].toString().split(_fieldSeparator);
    final fields = <String, String>{
      for (var i = 0; i < model.fields.length; i++)
        model.fields[i]: i < values.length ? values[i] : '',
    };
    final deckId = cards.first.deckId;
    final rawDeck = _decks[deckId] ?? '';
    final deckName = deckNameFromAnki(rawDeck).isEmpty
        ? unnamedDeck
        : deckNameFromAnki(rawDeck);
    final tags = [
      for (final t in row['tags'].toString().split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];

    final List<_Converted> converted;
    try {
      converted = model.isCloze
          ? _fromCloze(model, fields, cards)
          : _fromStandard(model, fields, cards, tags, deckName);
    } on _SkipNote {
      _notesSkipped++;
      return;
    }
    if (converted.isEmpty) {
      _notesSkipped++;
      return;
    }

    final guid = row['guid'].toString();
    final id = noteId;
    final mod = _int(row['mod']) * 1000;
    final createdAt = id > 946684800000 && id <= nowMs + 86400000
        ? id
        : (mod > 0 ? mod : nowMs);
    final updatedAt = mod > 0 ? mod : createdAt;

    for (final c in converted) {
      final incoming = <IncomingCard>[];
      if (withProgress) {
        for (final card in cards) {
          final ord = c.ordMap[card.ord];
          if (ord == null) continue;
          final p = _progress(card, ord, reviews[card.id] ?? const []);
          if (p != null) incoming.add(p);
        }
      }
      (byDeck[deckName] ??= []).add(
        IncomingNote(
          guid: 'anki-$guid${c.suffix}',
          type: c.type,
          fields: c.fields,
          tags: tags,
          createdAtMs: createdAt,
          updatedAtMs: updatedAt,
          cards: incoming,
        ),
      );
    }
  }

  IncomingCard? _progress(_AnkiCard c, int ord, List<AnkiReview> reviews) {
    final logs = logsFromAnki(reviews);
    final schedule = scheduleFromAnki(
      type: c.type,
      due: c.due,
      ivl: c.ivl,
      factor: c.factor,
      reps: c.reps,
      lapses: c.lapses,
      collectionCreatedSec: _created,
      dataJson: c.data,
      lastReviewMs: logs.isEmpty ? null : logs.last.atMs,
    );
    final suspended = c.queue == -1;
    if (schedule == null && !suspended && logs.isEmpty) return null;
    return IncomingCard(
      ord: ord,
      schedule: schedule ?? Schedule.fresh(nowMs),
      suspended: suspended,
      logs: logs,
    );
  }

  // ------------------------------------------------------------ texte à trous

  List<_Converted> _fromCloze(
    _Model model,
    Map<String, String> fields,
    List<_AnkiCard> cards,
  ) {
    // occlusion d'image intégrée à Anki
    final occIdx = model.fieldIndex('Occlusion');
    final imgIdx = model.fieldIndex('Image');
    if (occIdx >= 0 &&
        imgIdx >= 0 &&
        fields[model.fields[occIdx]]!.contains('image-occlusion:')) {
      return _fromOcclusion(model, fields, occIdx, imgIdx);
    }

    String? clozeField;
    for (final t in model.templates) {
      clozeField = ankiClozeField(t.question);
      if (clozeField != null) break;
    }
    final idx = clozeField == null ? -1 : model.fieldIndex(clozeField);
    final main = model.fields[idx >= 0 ? idx : 0];
    final text = _text(fields[main] ?? '');
    if (hasNestedCloze(text)) throw const _SkipNote();

    // champs que les modèles montrent au verso : complément
    final shown = <String>{
      for (final t in model.templates) ...ankiTemplateFields(t.answer),
    };
    final extra = [
      for (final f in model.fields)
        if (f != main &&
            shown.contains(f) &&
            !isAnkiFieldEmpty(fields[f] ?? ''))
          _text(fields[f]!),
    ].where((s) => s.isNotEmpty).join('\n');

    return [
      _Converted(
        NoteType.cloze,
        NoteFields({'text': text, if (extra.isNotEmpty) 'extra': extra}),
        // trou n° k = carte d'ordre k-1 dans Anki
        {for (final c in cards) c.ord: c.ord + 1},
      ),
    ];
  }

  List<_Converted> _fromOcclusion(
    _Model model,
    Map<String, String> fields,
    int occIdx,
    int imgIdx,
  ) {
    final shapes = parseAnkiOcclusion(fields[model.fields[occIdx]]!);
    _shapesApproximated += shapes.approximated;
    _shapesDropped += shapes.dropped;
    final img = _imgSrc.firstMatch(fields[model.fields[imgIdx]] ?? '');
    final src = img == null
        ? null
        : (img.group(1) ?? img.group(2) ?? img.group(3))!.replaceAll(
            '&amp;',
            '&',
          );
    final image = src == null ? null : _resolveImage(src);
    if (image == null || shapes.masks.isEmpty) throw const _SkipNote();

    String field(String name) {
      final i = model.fieldIndex(name);
      return i < 0 ? '' : _text(fields[model.fields[i]] ?? '');
    }

    final extra = [
      field('Back Extra'),
      field('Comments'),
    ].where((s) => s.isNotEmpty).join('\n');
    final header = field('Header');
    final groups = {for (final m in shapes.masks) m.group};
    return [
      _Converted(
        NoteType.occlusion,
        NoteFields({
          'image': image,
          'mode': OcclusionMode.group.name,
          'masks': [for (final m in shapes.masks) m.toJson()],
          if (header.isNotEmpty) 'context': header,
          if (extra.isNotEmpty) 'extra': extra,
        }),
        {for (final g in groups) g - 1: g},
      ),
    ];
  }

  // ------------------------------------------------------- types classiques

  List<_Converted> _fromStandard(
    _Model model,
    Map<String, String> fields,
    List<_AnkiCard> cards,
    List<String> tags,
    String deckName,
  ) {
    final special = {
      'Tags': tags.join(' '),
      'Deck': deckName,
      'Subdeck': deckName.split(' › ').last,
      'Type': model.name,
    };
    final faces = <int, ({String front, String back, bool typed})>{};
    for (final c in cards) {
      if (c.ord < 0 ||
          c.ord >= model.templates.length ||
          faces.containsKey(c.ord)) {
        continue;
      }
      final t = model.templates[c.ord];
      final s = {...special, 'Card': t.name};
      final q = renderAnkiTemplate(t.question, fields, special: s);
      final a = renderAnkiTemplate(
        t.answer,
        fields,
        frontSide: q,
        answer: true,
        special: s,
      );
      faces[c.ord] = (
        front: _text(q),
        back: _text(ankiAnswerOnly(a, q)),
        typed: RegExp(
          r'\{\{[^{}]*\btype:',
          caseSensitive: false,
        ).hasMatch(t.question),
      );
    }
    if (faces.isEmpty) return const [];

    // carte et carte inverse : une seule note « avec réciproque »
    final f0 = faces[0], f1 = faces[1];
    if (faces.length == 2 &&
        f0 != null &&
        f1 != null &&
        !f0.typed &&
        !f1.typed &&
        f0.front.isNotEmpty &&
        f0.back.isNotEmpty &&
        f0.front == f1.back &&
        f0.back == f1.front) {
      return [
        _Converted(
          NoteType.reversed,
          NoteFields({'front': f0.front, 'back': f0.back}),
          {0: 0, 1: 1},
        ),
      ];
    }

    final many = faces.length > 1;
    return [
      for (final e in faces.entries)
        _Converted(
          e.value.typed ? NoteType.typed : NoteType.basic,
          NoteFields({'front': e.value.front, 'back': e.value.back}),
          {e.key: 0},
          many ? '-${e.key}' : '',
        ),
    ];
  }
}

/// Note impossible à reprendre : comptée, sans interrompre l'import.
class _SkipNote implements Exception {
  const _SkipNote();
}
