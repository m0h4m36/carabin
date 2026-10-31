import 'package:flutter/widgets.dart';

import '../../domain/note_types.dart';

/// Mises en forme proposées par la barre d'outils de l'éditeur.
enum Format {
  bold('**'),
  italic('*'),
  underline('__'),
  highlight('==');

  const Format(this.marker);
  final String marker;
}

int _trailing(String s, String ch) {
  var n = 0;
  while (n < s.length && s[s.length - 1 - n] == ch) {
    n++;
  }
  return n;
}

int _leading(String s, String ch) {
  var n = 0;
  while (n < s.length && s[n] == ch) {
    n++;
  }
  return n;
}

bool _wrappedBy(Format f, String before, String after) {
  final m = f.marker;
  switch (f) {
    case Format.bold:
      return _trailing(before, '*') >= 2 && _leading(after, '*') >= 2;
    case Format.italic:
      return _trailing(before, '*').isOdd && _leading(after, '*').isOdd;
    case Format.underline:
    case Format.highlight:
      return before.endsWith(m) && after.startsWith(m);
  }
}

/// Applique ou retire une mise en forme sur la sélection.
///
/// Sans sélection, insère la paire de marques et place le curseur entre elles.
/// Les espaces en bordure de sélection restent en dehors des marques (une
/// marque collée à une espace ne s'applique pas).
TextEditingValue toggleFormat(TextEditingValue v, Format f) {
  final sel = v.selection;
  if (!sel.isValid) return v;
  final text = v.text;
  final start = sel.start;
  final end = sel.end;
  final m = f.marker;

  if (start == end) {
    final out = '${text.substring(0, start)}$m$m${text.substring(end)}';
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: start + m.length),
    );
  }

  final before = text.substring(0, start);
  final after = text.substring(end);
  if (_wrappedBy(f, before, after)) {
    final out = '${before.substring(0, before.length - m.length)}'
        '${text.substring(start, end)}${after.substring(m.length)}';
    return TextEditingValue(
      text: out,
      selection: TextSelection(
        baseOffset: start - m.length,
        extentOffset: end - m.length,
      ),
    );
  }

  var selected = text.substring(start, end);
  final lead = selected.length - selected.trimLeft().length;
  final trail = selected.length - selected.trimRight().length;
  if (lead + trail >= selected.length) return v; // que des espaces
  final core = selected.substring(lead, selected.length - trail);
  final out = '${text.substring(0, start + lead)}$m$core$m'
      '${text.substring(end - trail)}';
  return TextEditingValue(
    text: out,
    selection: TextSelection(
      baseOffset: start + lead + m.length,
      extentOffset: start + lead + m.length + core.length,
    ),
  );
}

/// Enveloppe la sélection dans un trou numéro [number]. Renvoie null s'il n'y
/// a rien de sélectionné.
TextEditingValue? insertCloze(TextEditingValue v, int number) {
  final sel = v.selection;
  if (!sel.isValid || sel.isCollapsed) return null;
  var start = sel.start;
  var end = sel.end;
  final text = v.text;
  // les espaces de bordure restent à l'extérieur du trou
  while (start < end && text[start].trim().isEmpty) {
    start++;
  }
  while (end > start && text[end - 1].trim().isEmpty) {
    end--;
  }
  if (start == end) return null;
  final out = wrapCloze(text, start, end, number);
  final inner = start + '{{c$number::'.length;
  return TextEditingValue(
    text: out,
    selection: TextSelection(baseOffset: inner, extentOffset: inner + (end - start)),
  );
}
