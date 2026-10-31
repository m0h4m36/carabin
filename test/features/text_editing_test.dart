import 'package:carabin/features/flashcards/text_editing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue v(String text, int a, int b) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: a, extentOffset: b),
    );

String sel(TextEditingValue t) => t.selection.textInside(t.text);

void main() {
  group('mise en forme', () {
    test('met en gras la sélection puis l\'enlève', () {
      final on = toggleFormat(v('le cœur bat', 3, 7), Format.bold);
      expect(on.text, 'le **cœur** bat');
      expect(sel(on), 'cœur');
      final off = toggleFormat(on, Format.bold);
      expect(off.text, 'le cœur bat');
      expect(sel(off), 'cœur');
    });

    test('sans sélection : paire de marques, curseur au milieu', () {
      final r = toggleFormat(v('ab', 1, 1), Format.underline);
      expect(r.text, 'a____b');
      expect(r.selection.baseOffset, 3);
      expect(r.selection.isCollapsed, isTrue);
    });

    test('les espaces de bordure restent dehors', () {
      final r = toggleFormat(v('a  mot  b', 1, 8), Format.highlight);
      expect(r.text, 'a  ==mot==  b');
      expect(sel(r), 'mot');
    });

    test('rien que des espaces : inchangé', () {
      final r = toggleFormat(v('a   b', 1, 4), Format.bold);
      expect(r.text, 'a   b');
    });

    test('gras puis italique puis retrait de chacun', () {
      var t = v('x', 0, 1);
      t = toggleFormat(t, Format.bold);
      expect(t.text, '**x**');
      t = toggleFormat(t, Format.italic);
      expect(t.text, '***x***');
      expect(sel(t), 'x');
      t = toggleFormat(t, Format.bold);
      expect(t.text, '*x*');
      t = toggleFormat(t, Format.italic);
      expect(t.text, 'x');
    });

    test('italique puis gras', () {
      var t = v('x', 0, 1);
      t = toggleFormat(t, Format.italic);
      expect(t.text, '*x*');
      t = toggleFormat(t, Format.bold);
      expect(t.text, '***x***');
      t = toggleFormat(t, Format.italic);
      expect(t.text, '**x**');
    });
  });

  group('trous', () {
    test('enveloppe la sélection', () {
      final r = insertCloze(v('Le cœur bat', 3, 7), 2)!;
      expect(r.text, 'Le {{c2::cœur}} bat');
      expect(sel(r), 'cœur');
    });

    test('rien de sélectionné : null', () {
      expect(insertCloze(v('abc', 1, 1), 1), isNull);
      expect(insertCloze(v('a  b', 1, 3), 1), isNull);
    });

    test('espaces de bordure à l\'extérieur', () {
      final r = insertCloze(v('Le  cœur  bat', 2, 9), 1)!;
      expect(r.text, 'Le  {{c1::cœur}}  bat');
    });
  });
}
