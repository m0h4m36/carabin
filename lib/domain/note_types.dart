import 'dart:convert';

import '../data/names.dart';

/// Types de notes (et donc de cartes) proposés.
enum NoteType { cloze, basic, reversed, typed, occlusion }

/// Un morceau d'un texte à trous : du texte simple, ou un trou.
class ClozePart {
  const ClozePart.text(this.text) : number = null, hint = null;
  const ClozePart.cloze(this.number, this.text, [this.hint]);

  /// Numéro du trou (c1, c2…), null pour du texte simple.
  final int? number;
  final String text;
  final String? hint;

  bool get isCloze => number != null;
}

final _clozePattern = RegExp(
  r'\{\{c(\d+)::((?:(?!\}\}).)*?)(?:::((?:(?!\}\}).)*?))?\}\}',
  dotAll: true,
);

/// Découpe un texte contenant des `{{c1::mot}}` ou `{{c1::mot::indice}}`.
List<ClozePart> parseCloze(String text) {
  final parts = <ClozePart>[];
  var last = 0;
  for (final m in _clozePattern.allMatches(text)) {
    if (m.start > last) parts.add(ClozePart.text(text.substring(last, m.start)));
    parts.add(ClozePart.cloze(int.parse(m.group(1)!), m.group(2)!, m.group(3)));
    last = m.end;
  }
  if (last < text.length) parts.add(ClozePart.text(text.substring(last)));
  return parts;
}

/// Numéros de trous présents, triés.
List<int> clozeNumbers(String text) => {
      for (final m in _clozePattern.allMatches(text)) int.parse(m.group(1)!),
    }.toList()
      ..sort();

/// Enveloppe [selected] dans un trou numéro [number].
String wrapCloze(String text, int start, int end, int number) {
  final inner = text.substring(start, end);
  return '${text.substring(0, start)}{{c$number::$inner}}${text.substring(end)}';
}

/// Prochain numéro de trou libre dans un texte.
int nextClozeNumber(String text) {
  final n = clozeNumbers(text);
  return n.isEmpty ? 1 : n.last + 1;
}

/// Problèmes détectés dans une note (l'éditeur affiche le message
/// correspondant ; aucune note invalide n'est enregistrée).
enum NoteIssue {
  emptyFront,
  emptyBack,
  noCloze,
  clozeNotClosed,
  noImage,
  noMask,
}

/// Zone masquée d'une image, en fractions de la taille de l'image (0 à 1).
class OcclusionMask {
  const OcclusionMask({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.group = 1,
  });

  factory OcclusionMask.fromJson(Map<String, dynamic> j) => OcclusionMask(
        left: (j['x'] as num).toDouble(),
        top: (j['y'] as num).toDouble(),
        width: (j['w'] as num).toDouble(),
        height: (j['h'] as num).toDouble(),
        group: (j['g'] as num?)?.toInt() ?? 1,
      );

  final double left;
  final double top;
  final double width;
  final double height;

  /// Numéro de groupe (mode « groupement »).
  final int group;

  Map<String, dynamic> toJson() => {
        'x': left,
        'y': top,
        'w': width,
        'h': height,
        'g': group,
      };
}

enum OcclusionMode { hideAll, hideOne, group }

/// Champs d'une note, stockés en JSON.
class NoteFields {
  NoteFields(Map<String, dynamic> data) : _data = Map.of(data);

  factory NoteFields.fromJson(String json) =>
      NoteFields((jsonDecode(json) as Map).cast<String, dynamic>());

  final Map<String, dynamic> _data;

  String text(String key) => (_data[key] as String?) ?? '';
  void setText(String key, String value) => _data[key] = value;

  Map<String, dynamic> toMap() => Map.of(_data);
  String toJson() => jsonEncode(_data);

  // Champs communs
  String get extra => text('extra');
  String get context => text('context');

  // Occlusion
  String get image => text('image');
  OcclusionMode get occlusionMode => OcclusionMode.values.firstWhere(
        (m) => m.name == _data['mode'],
        orElse: () => OcclusionMode.hideAll,
      );
  List<OcclusionMask> get masks => [
        for (final m in (_data['masks'] as List? ?? const []))
          OcclusionMask.fromJson((m as Map).cast<String, dynamic>()),
      ];
}

/// Valide une note ; renvoie null si elle est correcte.
NoteIssue? validateNote(NoteType type, NoteFields f) {
  bool empty(String k) => f.text(k).trim().isEmpty;
  switch (type) {
    case NoteType.cloze:
      final t = f.text('text');
      if (t.trim().isEmpty) return NoteIssue.emptyFront;
      if ('{{'.allMatches(t).length != '}}'.allMatches(t).length) {
        return NoteIssue.clozeNotClosed;
      }
      if (clozeNumbers(t).isEmpty) return NoteIssue.noCloze;
      return null;
    case NoteType.basic:
    case NoteType.reversed:
    case NoteType.typed:
      if (empty('front')) return NoteIssue.emptyFront;
      if (empty('back')) return NoteIssue.emptyBack;
      return null;
    case NoteType.occlusion:
      if (f.image.isEmpty) return NoteIssue.noImage;
      if (f.masks.isEmpty) return NoteIssue.noMask;
      return null;
  }
}

/// Numéros (ord) des cartes fabriquées par une note.
List<int> cardOrdinals(NoteType type, NoteFields f) {
  switch (type) {
    case NoteType.cloze:
      return clozeNumbers(f.text('text'));
    case NoteType.basic:
    case NoteType.typed:
      return const [0];
    case NoteType.reversed:
      return const [0, 1];
    case NoteType.occlusion:
      final masks = f.masks;
      switch (f.occlusionMode) {
        case OcclusionMode.hideAll:
          return const [0];
        case OcclusionMode.hideOne:
          return [for (var i = 0; i < masks.length; i++) i];
        case OcclusionMode.group:
          return ({for (final m in masks) m.group}.toList()..sort());
      }
  }
}

/// Rôle d'un morceau de texte sur une face de carte.
enum SegmentRole { normal, hidden, revealed }

class FaceSegment {
  const FaceSegment(this.text, [this.role = SegmentRole.normal]);
  final String text;
  final SegmentRole role;
}

/// Ce qu'on voit d'une carte : question, réponse, compléments.
class CardFace {
  const CardFace({
    required this.question,
    required this.answer,
    this.extra = '',
    this.context = '',
    this.typed = false,
    this.expected = '',
  });

  final List<FaceSegment> question;
  final List<FaceSegment> answer;
  final String extra;
  final String context;

  /// Carte « saisie » : l'utilisateur tape la réponse.
  final bool typed;

  /// Réponse attendue pour une carte « saisie ».
  final String expected;
}

/// Faces d'une carte texte (les cartes d'occlusion se dessinent à part).
CardFace renderFace(NoteType type, NoteFields f, int ord) {
  switch (type) {
    case NoteType.cloze:
      final q = <FaceSegment>[];
      final a = <FaceSegment>[];
      for (final part in parseCloze(f.text('text'))) {
        if (!part.isCloze) {
          q.add(FaceSegment(part.text));
          a.add(FaceSegment(part.text));
        } else if (part.number == ord) {
          q.add(FaceSegment(
            part.hint == null || part.hint!.isEmpty ? '[…]' : '[${part.hint}]',
            SegmentRole.hidden,
          ));
          a.add(FaceSegment(part.text, SegmentRole.revealed));
        } else {
          q.add(FaceSegment(part.text));
          a.add(FaceSegment(part.text));
        }
      }
      return CardFace(
        question: q,
        answer: a,
        extra: f.extra,
        context: f.context,
      );
    case NoteType.basic:
      return CardFace(
        question: [FaceSegment(f.text('front'))],
        answer: [FaceSegment(f.text('back'), SegmentRole.revealed)],
        extra: f.extra,
        context: f.context,
      );
    case NoteType.reversed:
      final front = f.text('front');
      final back = f.text('back');
      return CardFace(
        question: [FaceSegment(ord == 0 ? front : back)],
        answer: [FaceSegment(ord == 0 ? back : front, SegmentRole.revealed)],
        extra: f.extra,
        context: f.context,
      );
    case NoteType.typed:
      return CardFace(
        question: [FaceSegment(f.text('front'))],
        answer: [FaceSegment(f.text('back'), SegmentRole.revealed)],
        extra: f.extra,
        context: f.context,
        typed: true,
        expected: f.text('back'),
      );
    case NoteType.occlusion:
      return CardFace(
        question: const [],
        answer: const [],
        extra: f.extra,
        context: f.context,
      );
  }
}

/// Texte brut d'une note (pour la recherche et les listes) : sans les
/// marques de trous ni de mise en forme.
String plainText(NoteType type, NoteFields f) {
  String clean(String s) => stripRich(
        s.replaceAllMapped(_clozePattern, (m) => m.group(2)!),
      );
  switch (type) {
    case NoteType.cloze:
      return clean(f.text('text'));
    case NoteType.basic:
    case NoteType.reversed:
    case NoteType.typed:
      return '${clean(f.text('front'))} — ${clean(f.text('back'))}';
    case NoteType.occlusion:
      return clean(f.extra);
  }
}

/// Compare la réponse tapée à la réponse attendue (sans tenir compte des
/// majuscules, des accents ni des espaces en trop).
bool typedAnswerMatches(String typed, String expected) {
  String n(String s) => normalize(stripRich(s))
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[.,;:!?]+$'), '')
      .trim();
  final a = n(typed);
  return a.isNotEmpty && a == n(expected);
}

// ------------------------------------------------------------ mise en forme

/// Un morceau de texte avec sa mise en forme.
class RichRun {
  const RichRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.highlight = false,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool highlight;

  RichRun _with({bool? bold, bool? italic, bool? underline, bool? highlight}) =>
      RichRun(
        text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        highlight: highlight ?? this.highlight,
      );
}

/// Marques de mise en forme : `**gras**`, `*italique*`, `__souligné__`,
/// `==surligné==`. Une marque sans sa fermeture reste du texte simple.
const _markers = <String, String>{
  '***': 'bold-italic',
  '**': 'bold',
  '__': 'underline',
  '==': 'highlight',
  '*': 'italic',
};

List<RichRun> parseRich(String text) {
  final out = <RichRun>[];
  _parseInto(text, const RichRun(''), out);
  return out;
}

void _parseInto(String text, RichRun style, List<RichRun> out) {
  var i = 0;
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(style._with()._copyText(buf.toString()));
      buf.clear();
    }
  }

  while (i < text.length) {
    String? found;
    for (final m in _markers.keys) {
      if (text.startsWith(m, i)) {
        found = m;
        break;
      }
    }
    if (found != null) {
      final close = _closingMarker(text, found, i + found.length);
      if (close != -1) {
        flush();
        final inner = text.substring(i + found.length, close);
        final kind = _markers[found];
        _parseInto(
          inner,
          style._with(
            bold: kind == 'bold' || kind == 'bold-italic' ? true : null,
            italic: kind == 'italic' || kind == 'bold-italic' ? true : null,
            underline: kind == 'underline' ? true : null,
            highlight: kind == 'highlight' ? true : null,
          ),
          out,
        );
        i = close + found.length;
        continue;
      }
    }
    buf.write(text[i]);
    i++;
  }
  flush();
}

/// Position de la marque fermante : le texte entre les marques ne doit ni
/// commencer ni finir par une espace (« 2 * 3 * 4 » reste du texte simple).
int _closingMarker(String text, String marker, int from) {
  if (from >= text.length || _isSpace(text[from])) return -1;
  var c = text.indexOf(marker, from + 1);
  while (c != -1) {
    // une étoile simple ne referme pas à l'intérieur d'une suite d'étoiles
    final inStars = marker == '*' &&
        (text[c - 1] == '*' || (c + 1 < text.length && text[c + 1] == '*'));
    if (!inStars && !_isSpace(text[c - 1])) return c;
    c = text.indexOf(marker, c + 1);
  }
  return -1;
}

bool _isSpace(String ch) => ch.trim().isEmpty;

extension on RichRun {
  RichRun _copyText(String t) => RichRun(
        t,
        bold: bold,
        italic: italic,
        underline: underline,
        highlight: highlight,
      );
}

/// Texte sans les marques de mise en forme.
String stripRich(String text) => parseRich(text).map((r) => r.text).join();
