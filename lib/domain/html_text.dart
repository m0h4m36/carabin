import 'note_types.dart';

/// Convertit le HTML des champs d'autres applications (Anki, tableurs) en
/// texte de carte Carabin : gras, italique, souligné, surlignage, images,
/// sauts de ligne et listes sont conservés ; tout le reste est réduit à son
/// texte.
class HtmlConverter {
  HtmlConverter({this.image});

  /// Donne le nom de média Carabin d'une image HTML (`src`), ou null si elle
  /// est introuvable ou d'un format non pris en charge.
  final String? Function(String src)? image;

  /// Images qui n'ont pas pu être reprises.
  int droppedImages = 0;

  /// Sons et vidéos ignorés (non pris en charge).
  int droppedSounds = 0;

  String convert(String html) {
    var src = html.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    src = src.replaceAllMapped(
      RegExp(r'\[sound:[^\]]*\]', caseSensitive: false),
      (_) {
        droppedSounds++;
        return '';
      },
    );
    src = src.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    src = src.replaceAll(
      RegExp(
        r'<(script|style)\b[^>]*>.*?</\1\s*>',
        dotAll: true,
        caseSensitive: false,
      ),
      '',
    );
    final p = _Parser(this);
    p.run(src);
    return p.result();
  }

  static String _escapeText(String s) => escapeRich(s);
}

class _Style {
  const _Style({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.highlight = false,
  });
  final bool bold;
  final bool italic;
  final bool underline;
  final bool highlight;

  _Style copy({bool? bold, bool? italic, bool? underline, bool? highlight}) =>
      _Style(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        highlight: highlight ?? this.highlight,
      );

  @override
  bool operator ==(Object o) =>
      o is _Style &&
      o.bold == bold &&
      o.italic == italic &&
      o.underline == underline &&
      o.highlight == highlight;

  @override
  int get hashCode => Object.hash(bold, italic, underline, highlight);
}

class _Seg {
  _Seg(this.text, this.style, {this.raw = false});

  /// Texte déjà prêt (image, trou) : ni échappé ni mis en forme.
  final bool raw;
  String text;
  final _Style style;
}

class _Open {
  _Open(this.tag, this.before);
  final String tag;
  final _Style before;
}

final _tagPattern = RegExp(
  r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)((?:[^>"\x27]|"[^"]*"|\x27[^\x27]*\x27)*)>',
);

const _blockTags = {
  'div',
  'p',
  'li',
  'ul',
  'ol',
  'tr',
  'table',
  'blockquote',
  'pre',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'dd',
  'dt',
  'dl',
  'section',
};

class _Parser {
  _Parser(this.conv);

  final HtmlConverter conv;
  final List<_Seg> _segs = [];
  final List<_Open> _stack = [];
  final List<({bool ordered, int n})> _lists = [];
  _Style _style = const _Style();

  void run(String src) {
    var pos = 0;
    for (final m in _tagPattern.allMatches(src)) {
      if (m.start > pos) _text(src.substring(pos, m.start));
      _tag(
        closing: m.group(1) == '/',
        name: m.group(2)!.toLowerCase(),
        attrs: m.group(3) ?? '',
      );
      pos = m.end;
    }
    if (pos < src.length) _text(src.substring(pos));
  }

  void _add(String text, {bool raw = false}) {
    if (text.isEmpty) return;
    _segs.add(_Seg(text, _style, raw: raw));
  }

  void _text(String s) {
    // l'espace du HTML se replie ; &nbsp; reste une vraie espace
    var collapsed = s.replaceAll(RegExp(r'\s+'), ' ');
    if (_atLineStart) collapsed = collapsed.trimLeft();
    _add(_decodeEntities(collapsed));
  }

  bool get _atLineStart {
    for (var i = _segs.length - 1; i >= 0; i--) {
      final t = _segs[i].text;
      if (t.isEmpty) continue;
      return t.endsWith('\n');
    }
    return true;
  }

  void _newline({bool force = false}) {
    if (force || !_atLineStart) _add('\n', raw: true);
  }

  void _tag({
    required bool closing,
    required String name,
    required String attrs,
  }) {
    if (name == 'br') {
      if (!closing) _add('\n', raw: true);
      return;
    }
    if (name == 'img') {
      if (closing) return;
      final srcMatch = RegExp(
        r'''src\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
        caseSensitive: false,
      ).firstMatch(attrs);
      final src = srcMatch == null
          ? null
          : (srcMatch.group(1) ?? srcMatch.group(2) ?? srcMatch.group(3));
      final name = src == null ? null : conv.image?.call(_decodeEntities(src));
      if (name == null) {
        conv.droppedImages++;
      } else {
        _add(imageMarker(name), raw: true);
      }
      return;
    }
    if (name == 'audio' || name == 'video' || name == 'source') {
      if (!closing && name != 'source') conv.droppedSounds++;
      return;
    }
    if (_blockTags.contains(name)) {
      _block(closing, name);
      return;
    }
    if (name == 'td' || name == 'th') {
      if (closing) return;
      if (!_atLineStart) _add(' | ', raw: true);
      return;
    }
    if (name == 'sup' || name == 'sub') {
      _scripts(closing, name);
      return;
    }
    if (closing) {
      _close(name);
    } else {
      _open(name, attrs);
    }
  }

  void _block(bool closing, String name) {
    if (name == 'ul' || name == 'ol') {
      if (closing) {
        if (_lists.isNotEmpty) _lists.removeLast();
      } else {
        _lists.add((ordered: name == 'ol', n: 0));
      }
      _newline();
      return;
    }
    if (name == 'li') {
      if (closing) {
        _newline();
        return;
      }
      _newline();
      if (_lists.isNotEmpty && _lists.last.ordered) {
        final n = _lists.last.n + 1;
        _lists[_lists.length - 1] = (ordered: true, n: n);
        _add('$n. ', raw: true);
      } else {
        _add('• ', raw: true);
      }
      return;
    }
    if (name == 'hr') {
      if (!closing) _newline();
      return;
    }
    _newline();
  }

  // exposants et indices : en caractères Unicode quand c'est possible
  static const _sup = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '+': '⁺',
    '-': '⁻',
    '−': '⁻',
    '=': '⁼',
    '(': '⁽',
    ')': '⁾',
    'n': 'ⁿ',
    'i': 'ⁱ',
  };
  static const _sub = {
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
    '+': '₊',
    '-': '₋',
    '−': '₋',
    '=': '₌',
    '(': '₍',
    ')': '₎',
  };
  int? _scriptFrom;
  String _scriptKind = '';

  void _scripts(bool closing, String name) {
    if (!closing) {
      _scriptFrom = _segs.length;
      _scriptKind = name;
      return;
    }
    final from = _scriptFrom;
    if (from == null || _scriptKind != name) return;
    _scriptFrom = null;
    final inner = _segs.sublist(from).map((s) => s.text).join();
    _segs.removeRange(from, _segs.length);
    final map = name == 'sup' ? _sup : _sub;
    final mapped = StringBuffer();
    var ok = inner.isNotEmpty;
    for (final r in inner.runes) {
      final ch = String.fromCharCode(r);
      final m = map[ch];
      if (m == null) {
        ok = false;
        break;
      }
      mapped.write(m);
    }
    _add(ok ? mapped.toString() : (name == 'sup' ? '^($inner)' : '_($inner)'));
  }

  void _open(String name, String attrs) {
    final before = _style;
    var s = _style;
    switch (name) {
      case 'b' || 'strong':
        s = s.copy(bold: true);
      case 'i' || 'em' || 'cite' || 'dfn':
        s = s.copy(italic: true);
      case 'u' || 'ins':
        s = s.copy(underline: true);
      case 'mark':
        s = s.copy(highlight: true);
      case 'span' || 'font':
        final style = RegExp(
          r'style\s*=\s*"([^"]*)"|style\s*=\s*\x27([^\x27]*)\x27',
          caseSensitive: false,
        ).firstMatch(attrs);
        final css = (style?.group(1) ?? style?.group(2) ?? '').toLowerCase();
        if (RegExp(r'font-weight\s*:\s*(bold|[6-9]00)').hasMatch(css)) {
          s = s.copy(bold: true);
        }
        if (RegExp(r'font-style\s*:\s*italic').hasMatch(css)) {
          s = s.copy(italic: true);
        }
        if (RegExp(r'text-decoration[^;]*underline').hasMatch(css)) {
          s = s.copy(underline: true);
        }
        final bg = RegExp(r'background(?:-color)?\s*:\s*([^;]+)')
            .firstMatch(css)
            ?.group(1)
            ?.trim();
        if (bg != null &&
            !_noBackground.contains(bg) &&
            !bg.startsWith('rgba(0, 0, 0, 0') &&
            !bg.startsWith('var(')) {
          s = s.copy(highlight: true);
        }
    }
    _stack.add(_Open(name, before));
    _style = s;
  }

  static const _noBackground = {
    'transparent',
    'none',
    'inherit',
    'initial',
    'white',
    '#fff',
    '#ffffff',
    'rgb(255, 255, 255)',
    'rgba(255, 255, 255, 1)',
    'unset',
  };

  void _close(String name) {
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].tag == name) {
        _style = _stack[i].before;
        _stack.removeRange(i, _stack.length);
        return;
      }
    }
  }

  // ------------------------------------------------------------- sortie

  String result() {
    // fusionne les morceaux voisins de même style
    final merged = <_Seg>[];
    for (final s in _segs) {
      if (merged.isNotEmpty &&
          !s.raw &&
          !merged.last.raw &&
          merged.last.style == s.style) {
        merged.last.text += s.text;
      } else {
        merged.add(_Seg(s.text, s.style, raw: s.raw));
      }
    }
    final out = StringBuffer();
    for (final s in merged) {
      if (s.raw) {
        out.write(s.text);
        continue;
      }
      final text = s.text;
      final style = s.style;
      final plain =
          !style.bold && !style.italic && !style.underline && !style.highlight;
      if (plain) {
        out.write(HtmlConverter._escapeText(text));
        continue;
      }
      // les espaces de bord restent hors des marques (« **gras **» ne marcherait pas)
      final lead = text.length - text.trimLeft().length;
      final trail = text.length - text.trimRight().length;
      if (lead + trail >= text.length) {
        out.write(text);
        continue;
      }
      final core = HtmlConverter._escapeText(
        text.substring(lead, text.length - trail),
      );
      var wrapped = core;
      final stars = style.bold && style.italic
          ? '***'
          : style.bold
          ? '**'
          : style.italic
          ? '*'
          : '';
      if (stars.isNotEmpty) wrapped = '$stars$wrapped$stars';
      if (style.underline) wrapped = '__${wrapped}__';
      if (style.highlight) wrapped = '==$wrapped==';
      out.write(text.substring(0, lead));
      out.write(wrapped);
      out.write(text.substring(text.length - trail));
    }
    return _tidy(out.toString());
  }

  static String _tidy(String s) {
    final lines = s
        .split('\n')
        .map(
          (l) => l
              .replaceAll(RegExp(r'[ \t]+$'), '')
              .replaceAll(RegExp(r'^[ \t]+'), ''),
        )
        .toList();
    var t = lines.join('\n');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  // ------------------------------------------------------------- entités

  static String _decodeEntities(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);'),
      (m) {
        final e = m.group(1)!;
        if (e.startsWith('#x') || e.startsWith('#X')) {
          final v = int.tryParse(e.substring(2), radix: 16);
          return _codePoint(v) ?? m.group(0)!;
        }
        if (e.startsWith('#')) {
          final v = int.tryParse(e.substring(1));
          return _codePoint(v) ?? m.group(0)!;
        }
        return _named[e] ?? m.group(0)!;
      },
    );
  }

  static String? _codePoint(int? v) {
    if (v == null || v <= 0 || v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) {
      return null;
    }
    if (v == 0xA0) return ' ';
    return String.fromCharCode(v);
  }

  static const _named = <String, String>{
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'eacute': 'é',
    'egrave': 'è',
    'ecirc': 'ê',
    'euml': 'ë',
    'agrave': 'à',
    'acirc': 'â',
    'auml': 'ä',
    'aring': 'å',
    'ccedil': 'ç',
    'icirc': 'î',
    'iuml': 'ï',
    'igrave': 'ì',
    'iacute': 'í',
    'oacute': 'ó',
    'ocirc': 'ô',
    'ouml': 'ö',
    'ugrave': 'ù',
    'ucirc': 'û',
    'uuml': 'ü',
    'uacute': 'ú',
    'aacute': 'á',
    'ntilde': 'ñ',
    'yuml': 'ÿ',
    'oelig': 'œ',
    'OElig': 'Œ',
    'aelig': 'æ',
    'AElig': 'Æ',
    'Eacute': 'É',
    'Egrave': 'È',
    'Ecirc': 'Ê',
    'Agrave': 'À',
    'Acirc': 'Â',
    'Ccedil': 'Ç',
    'Icirc': 'Î',
    'Ocirc': 'Ô',
    'Ucirc': 'Û',
    'Ugrave': 'Ù',
    'Euml': 'Ë',
    'Iuml': 'Ï',
    'Uuml': 'Ü',
    'laquo': '«',
    'raquo': '»',
    'hellip': '…',
    'ndash': '–',
    'mdash': '—',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'bull': '•',
    'middot': '·',
    'deg': '°',
    'plusmn': '±',
    'micro': 'µ',
    'times': '×',
    'divide': '÷',
    'frac12': '½',
    'frac14': '¼',
    'frac34': '¾',
    'sup2': '²',
    'sup3': '³',
    'euro': '€',
    'pound': '£',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'sect': '§',
    'para': '¶',
    'larr': '←',
    'rarr': '→',
    'uarr': '↑',
    'darr': '↓',
    'harr': '↔',
    'rArr': '⇒',
    'lArr': '⇐',
    'hArr': '⇔',
    'ne': '≠',
    'le': '≤',
    'ge': '≥',
    'asymp': '≈',
    'minus': '−',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'epsilon': 'ε',
    'kappa': 'κ',
    'lambda': 'λ',
    'mu': 'μ',
    'pi': 'π',
    'sigma': 'σ',
    'tau': 'τ',
    'omega': 'ω',
    'Delta': 'Δ',
    'Sigma': 'Σ',
    'Omega': 'Ω',
    'infin': '∞',
    'sum': '∑',
    'radic': '√',
    'prime': '′',
    'Prime': '″',
    'thinsp': ' ',
    'ensp': ' ',
    'emsp': ' ',
    'shy': '',
    'zwnj': '',
    'zwj': '',
  };
}
