import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'exchange.dart';
import 'html_text.dart';
import 'note_types.dart';

// ------------------------------------------------------------------ texte

/// Décode un fichier texte : UTF-8 (avec ou sans repère BOM), UTF-16 (export
/// « Unicode » d'Excel) ou, à défaut, Windows-1252 (ancien Excel français).
String decodeText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, 2, littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, 2, littleEndian: false);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _windows1252(bytes);
  }
}

String _utf16(Uint8List b, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    units.add(littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

const _cp1252 = <int, int>{
  0x80: 0x20AC,
  0x82: 0x201A,
  0x83: 0x0192,
  0x84: 0x201E,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02C6,
  0x89: 0x2030,
  0x8A: 0x0160,
  0x8B: 0x2039,
  0x8C: 0x0152,
  0x8E: 0x017D,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201C,
  0x94: 0x201D,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02DC,
  0x99: 0x2122,
  0x9A: 0x0161,
  0x9B: 0x203A,
  0x9C: 0x0153,
  0x9E: 0x017E,
  0x9F: 0x0178,
};

String _windows1252(Uint8List b) =>
    String.fromCharCodes([for (final x in b) _cp1252[x] ?? x]);

// ------------------------------------------------------- découpage en cellules

/// Découpe un texte en lignes de cellules. Les cellules entre guillemets
/// peuvent contenir le séparateur et des retours à la ligne ; un guillemet
/// double (`""`) y représente un guillemet.
List<List<String>> parseDelimited(String text, String delimiter) {
  assert(delimiter.length == 1);
  final d = delimiter.codeUnitAt(0);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var wasQuoted = false;
  var i = 0;
  final n = text.length;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
    wasQuoted = false;
  }

  void endRow() {
    final quoted = wasQuoted;
    endCell();
    // une ligne vide (une seule cellule vide, sans guillemets) n'est pas une
    // ligne de données ; `""` seul en est une
    if (!(row.length == 1 && row[0].isEmpty && !quoted)) rows.add(row);
    row = <String>[];
  }

  while (i < n) {
    final c = text.codeUnitAt(i);
    if (inQuotes) {
      if (c == 0x22) {
        if (i + 1 < n && text.codeUnitAt(i + 1) == 0x22) {
          cell.writeCharCode(0x22);
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      cell.writeCharCode(c);
      i++;
      continue;
    }
    if (c == 0x22 && cell.isEmpty && !wasQuoted) {
      inQuotes = true;
      wasQuoted = true;
      i++;
      continue;
    }
    if (c == d) {
      endCell();
      i++;
      continue;
    }
    if (c == 0x0A || c == 0x0D) {
      if (c == 0x0D && i + 1 < n && text.codeUnitAt(i + 1) == 0x0A) i++;
      endRow();
      i++;
      continue;
    }
    cell.writeCharCode(c);
    i++;
  }
  if (cell.isNotEmpty || row.isNotEmpty || wasQuoted) {
    // dernière ligne sans retour à la ligne final
    endRow();
  }
  return rows;
}

/// Séparateur le plus vraisemblable d'un texte : celui qui apparaît le même
/// nombre de fois (au moins une) sur le plus de lignes. En cas d'égalité,
/// tabulation, point-virgule, virgule, barre verticale, dans cet ordre.
String detectDelimiter(String text) {
  const candidates = ['\t', ';', ',', '|'];
  final lines = text
      .split(RegExp(r'\r\n|\n|\r'))
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .take(30)
      .toList();
  var best = candidates.first;
  var bestScore = -1;
  for (final c in candidates) {
    final counts = <int>[];
    for (final l in lines) {
      // on ignore ce qui est entre guillemets
      var depth = false;
      var n = 0;
      for (var i = 0; i < l.length; i++) {
        if (l[i] == '"') depth = !depth;
        if (!depth && l[i] == c) n++;
      }
      counts.add(n);
    }
    if (counts.isEmpty) continue;
    final nonZero = counts.where((x) => x > 0).toList();
    if (nonZero.isEmpty) continue;
    final freq = <int, int>{};
    for (final x in nonZero) {
      freq[x] = (freq[x] ?? 0) + 1;
    }
    final mostCommon = freq.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    // les lignes qui ont le bon nombre de séparateurs comptent double
    final score = mostCommon.value * 2 + (nonZero.length - mostCommon.value);
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return best;
}

// ------------------------------------------------ en-têtes d'export d'Anki

/// Lignes d'en-tête `#clé:valeur` des exports texte d'Anki.
class CsvDirectives {
  const CsvDirectives({
    this.separator,
    this.html = false,
    this.tagsColumn,
    this.deckColumn,
    this.guidColumn,
  });

  final String? separator;
  final bool html;

  /// Numéros de colonne (à partir de 0).
  final int? tagsColumn;
  final int? deckColumn;
  final int? guidColumn;
}

/// Sépare les lignes `#…:…` du début du fichier du reste.
({CsvDirectives directives, String body}) extractDirectives(String text) {
  final lines = text.split(RegExp(r'\r\n|\n|\r'));
  var i = 0;
  String? sep;
  var html = false;
  int? tags, deck, guid;
  int? col(String v) {
    final n = int.tryParse(v.trim());
    return n == null || n < 1 ? null : n - 1;
  }

  while (i < lines.length && lines[i].startsWith('#')) {
    final m = RegExp(r'^#([^:]+):(.*)$').firstMatch(lines[i]);
    if (m != null) {
      final key = m.group(1)!.trim().toLowerCase();
      final value = m.group(2)!.trim();
      switch (key) {
        case 'separator':
          sep = switch (value.toLowerCase()) {
            'tab' => '\t',
            'comma' => ',',
            'semicolon' => ';',
            'pipe' => '|',
            'space' => ' ',
            _ => value.length == 1 ? value : null,
          };
        case 'html':
          html = value.toLowerCase() == 'true';
        case 'tags column':
          tags = col(value);
        case 'deck column':
          deck = col(value);
        case 'guid column':
          guid = col(value);
      }
    }
    i++;
  }
  return (
    directives: CsvDirectives(
      separator: sep,
      html: html,
      tagsColumn: tags,
      deckColumn: deck,
      guidColumn: guid,
    ),
    body: lines.sublist(i).join('\n'),
  );
}

// --------------------------------------------------------------- conversion

/// Choix de l'utilisateur pour transformer des lignes en notes.
class CsvMapping {
  const CsvMapping({
    this.type = NoteType.basic,
    this.front = 0,
    this.back = 1,
    this.extra,
    this.tags,
    this.deck,
    this.guid,
    this.hasHeader = false,
    this.html = false,
  });

  final NoteType type;

  /// Colonne du texte (ou du recto). Pour un texte à trous, c'est le texte.
  final int? front;
  final int? back;
  final int? extra;
  final int? tags;

  /// Colonne qui donne le paquet de chaque ligne ; null = paquet choisi.
  final int? deck;
  final int? guid;
  final bool hasHeader;
  final bool html;

  CsvMapping copyWith({
    NoteType? type,
    Object? front = _keep,
    Object? back = _keep,
    Object? extra = _keep,
    Object? tags = _keep,
    Object? deck = _keep,
    Object? guid = _keep,
    bool? hasHeader,
    bool? html,
  }) => CsvMapping(
    type: type ?? this.type,
    front: identical(front, _keep) ? this.front : front as int?,
    back: identical(back, _keep) ? this.back : back as int?,
    extra: identical(extra, _keep) ? this.extra : extra as int?,
    tags: identical(tags, _keep) ? this.tags : tags as int?,
    deck: identical(deck, _keep) ? this.deck : deck as int?,
    guid: identical(guid, _keep) ? this.guid : guid as int?,
    hasHeader: hasHeader ?? this.hasHeader,
    html: html ?? this.html,
  );

  static const _keep = Object();
}

/// Réglage proposé d'après le contenu du fichier.
CsvMapping suggestMapping(List<List<String>> rows, CsvDirectives d) {
  final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  if (width == 0) return CsvMapping(html: d.html);

  // en-tête : première ligne faite de mots, et reconnaissable
  int? find(List<String> header, RegExp re) {
    for (var i = 0; i < header.length; i++) {
      if (re.hasMatch(header[i].toLowerCase())) return i;
    }
    return null;
  }

  final first = rows.first;
  final front = find(
    first,
    RegExp(r'^(question|recto|front|avant|texte|text|énoncé|enonce)'),
  );
  final back = find(
    first,
    RegExp(r'^(réponse|reponse|verso|back|answer|arrière|arriere)'),
  );
  if (front != null && (back != null || width == 1)) {
    return CsvMapping(
      type: back == null ? NoteType.cloze : NoteType.basic,
      front: front,
      back: back,
      extra: find(
        first,
        RegExp(
          r'^(extra|complément|complement|commentaire|note|mnémo|mnemo|source)',
        ),
      ),
      tags:
          d.tagsColumn ??
          find(first, RegExp(r'^(tag|étiquette|etiquette|mots)')),
      deck: d.deckColumn ?? find(first, RegExp(r'^(deck|paquet)')),
      guid: d.guidColumn,
      hasHeader: true,
      html: d.html,
    );
  }

  final hasCloze = rows
      .take(20)
      .any((r) => r.any((c) => RegExp(r'\{\{c\d+::').hasMatch(c)));
  if (hasCloze || width == 1) {
    return CsvMapping(
      type: NoteType.cloze,
      front: 0,
      back: null,
      tags: d.tagsColumn,
      deck: d.deckColumn,
      guid: d.guidColumn,
      html: d.html,
    );
  }
  return CsvMapping(
    front: 0,
    back: 1,
    tags: d.tagsColumn,
    deck: d.deckColumn,
    guid: d.guidColumn,
    html: d.html,
  );
}

/// Notes tirées d'un fichier, rangées par paquet ('' = le paquet choisi).
class CsvConversion {
  final Map<String, List<IncomingNote>> byDeck = {};
  int skipped = 0;
  int droppedImages = 0;
  int droppedSounds = 0;

  int get total => byDeck.values.fold(0, (s, l) => s + l.length);
}

/// Transforme les lignes en notes. Une ligne qui ne donnerait pas une note
/// valide (cellule vide, texte sans trou…) est comptée dans `skipped`.
CsvConversion convertCsv(
  List<List<String>> rows,
  CsvMapping m, {
  required int nowMs,
}) {
  final out = CsvConversion();
  final html = HtmlConverter();
  final data = m.hasHeader && rows.isNotEmpty ? rows.sublist(1) : rows;

  String cell(List<String> r, int? c) =>
      c == null || c < 0 || c >= r.length ? '' : r[c];
  String text(List<String> r, int? c) {
    final raw = cell(r, c);
    return (m.html
            ? html.convert(raw)
            : raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
        .trim();
  }

  for (final r in data) {
    final front = text(r, m.front);
    final back = m.type == NoteType.cloze ? '' : text(r, m.back);
    final extra = text(r, m.extra);
    final fields = <String, dynamic>{
      if (m.type == NoteType.cloze) ...{
        'text': front,
      } else ...{
        'front': front,
        'back': back,
      },
      if (extra.isNotEmpty) 'extra': extra,
    };
    final f = NoteFields(fields);
    if (validateNote(m.type, f) != null) {
      out.skipped++;
      continue;
    }
    final guid = cell(r, m.guid).trim().isNotEmpty
        ? 'anki-${cell(r, m.guid).trim()}'
        : 'csv-${sha1.convert(utf8.encode('${m.type.name}\u0001$front\u0001$back\u0001$extra')).toString().substring(0, 24)}';
    final tags = [
      for (final t in cell(r, m.tags).split(RegExp(r'[\s,;]+')))
        if (t.isNotEmpty) t,
    ];
    final deck = m.deck == null
        ? ''
        : cell(r, m.deck).trim().replaceAll('::', ' › ');
    (out.byDeck[deck] ??= []).add(
      IncomingNote(
        guid: guid,
        type: m.type,
        fields: f,
        tags: tags,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      ),
    );
  }
  out.droppedImages = html.droppedImages;
  out.droppedSounds = html.droppedSounds;
  return out;
}
