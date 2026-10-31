import 'dart:convert';
import 'dart:typed_data';

import 'package:carabin/domain/csv_import.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List b(List<int> x) => Uint8List.fromList(x);

void main() {
  group('decodeText', () {
    test('UTF-8 avec et sans repère BOM', () {
      expect(decodeText(b(utf8.encode('é à'))), 'é à');
      expect(decodeText(b([0xEF, 0xBB, 0xBF, ...utf8.encode('é à')])), 'é à');
    });

    test('UTF-16 des deux sens', () {
      final le = [0xFF, 0xFE, 0xE9, 0x00, 0x61, 0x00];
      final be = [0xFE, 0xFF, 0x00, 0xE9, 0x00, 0x61];
      expect(decodeText(b(le)), 'éa');
      expect(decodeText(b(be)), 'éa');
    });

    test('Windows-1252 quand ce n\'est pas de l\'UTF-8', () {
      // « été € » en cp1252
      expect(decodeText(b([0xE9, 0x74, 0xE9, 0x20, 0x80])), 'été €');
      // guillemets typographiques
      expect(decodeText(b([0x93, 0x61, 0x94])), '“a”');
    });

    test('fichier vide', () {
      expect(decodeText(b([])), '');
    });
  });

  group('parseDelimited', () {
    test('lignes simples, fins de ligne mêlées', () {
      expect(parseDelimited('a;b\r\nc;d\ne;f\rg;h', ';'), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
        ['g', 'h'],
      ]);
    });

    test('guillemets : séparateur, retour à la ligne et guillemet doublé', () {
      final rows = parseDelimited(
        '"a;b";"ligne 1\nligne 2";"dit ""oui"""\nx;y;z',
        ';',
      );
      expect(rows, [
        ['a;b', 'ligne 1\nligne 2', 'dit "oui"'],
        ['x', 'y', 'z'],
      ]);
    });

    test('lignes vides ignorées, cellules vides gardées', () {
      expect(parseDelimited('a;;c\n\n;;\n', ';'), [
        ['a', '', 'c'],
        ['', '', ''],
      ]);
    });

    test('dernière ligne sans retour à la ligne', () {
      expect(parseDelimited('a;b\nc;d', ';'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('cellule entre guillemets vide en fin de fichier', () {
      expect(parseDelimited('a;""', ';'), [
        ['a', ''],
      ]);
    });

    test('une cellule vide entre guillemets est une ligne', () {
      expect(parseDelimited('""\nx', ';'), [
        [''],
        ['x'],
      ]);
    });

    test('guillemet au milieu d\'une cellule : gardé tel quel', () {
      expect(parseDelimited('5" de long;x', ';'), [
        ['5" de long', 'x'],
      ]);
    });

    test('tabulation', () {
      expect(parseDelimited('a\tb c\td', '\t'), [
        ['a', 'b c', 'd'],
      ]);
    });
  });

  group('detectDelimiter', () {
    test('reconnaît chacun des séparateurs', () {
      expect(detectDelimiter('a\tb\nc\td'), '\t');
      expect(detectDelimiter('a;b\nc;d'), ';');
      expect(detectDelimiter('a,b\nc,d'), ',');
      expect(detectDelimiter('a|b\nc|d'), '|');
    });

    test('virgules dans un texte, point-virgule comme séparateur', () {
      expect(
        detectDelimiter('"Tri, quadri, penta";réponse\n"un, deux";autre'),
        ';',
      );
    });

    test('ignore les lignes d\'en-tête #', () {
      expect(detectDelimiter('#separator:tab\n#html:true\na\tb\nc\td'), '\t');
    });

    test('rien de reconnaissable : tabulation par défaut', () {
      expect(detectDelimiter('un seul mot'), '\t');
      expect(detectDelimiter(''), '\t');
    });
  });

  group('extractDirectives', () {
    test('en-têtes d\'un export texte d\'Anki', () {
      final r = extractDirectives(
        '#separator:tab\n#html:true\n#guid column:1\n#tags column:5\n#deck column:4\nx\ty',
      );
      expect(r.directives.separator, '\t');
      expect(r.directives.html, isTrue);
      expect(r.directives.guidColumn, 0);
      expect(r.directives.tagsColumn, 4);
      expect(r.directives.deckColumn, 3);
      expect(r.body, 'x\ty');
    });

    test('sans en-tête', () {
      final r = extractDirectives('a;b');
      expect(r.directives.separator, isNull);
      expect(r.directives.html, isFalse);
      expect(r.body, 'a;b');
    });

    test('séparateurs nommés et valeurs incohérentes', () {
      expect(
        extractDirectives('#separator:Semicolon\na').directives.separator,
        ';',
      );
      expect(
        extractDirectives('#separator:Comma\na').directives.separator,
        ',',
      );
      expect(extractDirectives('#separator:Pipe\na').directives.separator, '|');
      expect(
        extractDirectives('#separator:Space\na').directives.separator,
        ' ',
      );
      expect(
        extractDirectives('#separator:??\na').directives.separator,
        isNull,
      );
      expect(
        extractDirectives('#tags column:0\na').directives.tagsColumn,
        isNull,
      );
      expect(
        extractDirectives('#tags column:abc\na').directives.tagsColumn,
        isNull,
      );
    });
  });

  group('suggestMapping', () {
    const none = CsvDirectives();

    test('en-tête reconnu', () {
      final m = suggestMapping([
        ['Question', 'Réponse', 'Tags', 'Complément'],
        ['a', 'b', 'c', 'd'],
      ], none);
      expect(m.hasHeader, isTrue);
      expect(m.type, NoteType.basic);
      expect(m.front, 0);
      expect(m.back, 1);
      expect(m.tags, 2);
      expect(m.extra, 3);
    });

    test('colonnes dans un autre ordre', () {
      final m = suggestMapping([
        ['verso', 'recto'],
        ['b', 'a'],
      ], none);
      expect(m.front, 1);
      expect(m.back, 0);
      expect(m.hasHeader, isTrue);
    });

    test('texte à trous détecté', () {
      final m = suggestMapping([
        ['Le {{c1::cœur}} bat'],
        ['L\'{{c1::aorte}} part du VG'],
      ], none);
      expect(m.type, NoteType.cloze);
      expect(m.hasHeader, isFalse);
    });

    test('deux colonnes sans en-tête : recto-verso', () {
      final m = suggestMapping([
        ['a', 'b'],
        ['c', 'd'],
      ], none);
      expect(m.type, NoteType.basic);
      expect(m.hasHeader, isFalse);
      expect(m.front, 0);
      expect(m.back, 1);
    });

    test('directives d\'Anki reprises', () {
      final m = suggestMapping([
        ['a', 'b', 'tag1', 'Deck'],
      ], const CsvDirectives(html: true, tagsColumn: 2, deckColumn: 3));
      expect(m.html, isTrue);
      expect(m.tags, 2);
      expect(m.deck, 3);
    });

    test('fichier vide', () {
      final m = suggestMapping(const [], none);
      expect(m.type, NoteType.basic);
    });
  });

  group('convertCsv', () {
    test('recto-verso simple avec étiquettes', () {
      final r = convertCsv(
        [
          ['Aorte', 'Naît du VG', 'anat cœur'],
          ['Veine cave', 'Rejoint l\'OD', ''],
        ],
        const CsvMapping(tags: 2),
        nowMs: 1000,
      );
      expect(r.total, 2);
      expect(r.skipped, 0);
      final notes = r.byDeck['']!;
      expect(notes[0].fields.text('front'), 'Aorte');
      expect(notes[0].fields.text('back'), 'Naît du VG');
      expect(notes[0].tags, ['anat', 'cœur']);
      expect(notes[1].tags, isEmpty);
      expect(notes[0].createdAtMs, 1000);
    });

    test('en-tête sauté', () {
      final r = convertCsv(
        [
          ['Question', 'Réponse'],
          ['a', 'b'],
        ],
        const CsvMapping(hasHeader: true),
        nowMs: 0,
      );
      expect(r.total, 1);
    });

    test('lignes invalides comptées', () {
      final r = convertCsv(
        [
          ['a', ''],
          ['', 'b'],
          ['c', 'd'],
        ],
        const CsvMapping(),
        nowMs: 0,
      );
      expect(r.total, 1);
      expect(r.skipped, 2);
    });

    test('texte à trous : lignes sans trou refusées', () {
      final r = convertCsv(
        [
          ['Le {{c1::cœur}} bat'],
          ['Pas de trou'],
          ['Mal {{c1::fermé'],
        ],
        const CsvMapping(type: NoteType.cloze, back: null),
        nowMs: 0,
      );
      expect(r.total, 1);
      expect(r.skipped, 2);
      expect(r.byDeck['']!.single.type, NoteType.cloze);
    });

    test('identifiant : stable, et différent selon le contenu et le type', () {
      List<String> guids(CsvMapping m, List<List<String>> rows) => [
        for (final n in convertCsv(rows, m, nowMs: 0).byDeck['']!) n.guid,
      ];
      final rows = [
        ['a', 'b'],
        ['a', 'c'],
      ];
      final g1 = guids(const CsvMapping(), rows);
      final g2 = guids(const CsvMapping(), rows);
      expect(g1, g2);
      expect(g1[0], isNot(g1[1]));
      final g3 = guids(const CsvMapping(type: NoteType.reversed), rows);
      expect(g3[0], isNot(g1[0]));
    });

    test('identifiant fourni par le fichier', () {
      final r = convertCsv(
        [
          ['a', 'b', 'XyZ12'],
        ],
        const CsvMapping(guid: 2),
        nowMs: 0,
      );
      expect(r.byDeck['']!.single.guid, 'anki-XyZ12');
    });

    test('paquets par colonne, avec :: remplacé', () {
      final r = convertCsv(
        [
          ['a', 'b', 'Cardio::Cœur'],
          ['c', 'd', 'Cardio::Cœur'],
          ['e', 'f', 'Pneumo'],
        ],
        const CsvMapping(deck: 2),
        nowMs: 0,
      );
      expect(r.byDeck.keys.toSet(), {'Cardio › Cœur', 'Pneumo'});
      expect(r.byDeck['Cardio › Cœur']!.length, 2);
    });

    test('HTML converti et images comptées', () {
      final r = convertCsv(
        [
          ['<b>gras</b>&nbsp;ici', 'x<img src="a.png"><br>y'],
        ],
        const CsvMapping(html: true),
        nowMs: 0,
      );
      final n = r.byDeck['']!.single;
      expect(stripRich(n.fields.text('front')), 'gras ici');
      expect(r.droppedImages, 1);
    });

    test('sans HTML, le texte reste tel quel', () {
      final r = convertCsv(
        [
          ['<b>x</b>', 'y'],
        ],
        const CsvMapping(),
        nowMs: 0,
      );
      expect(r.byDeck['']!.single.fields.text('front'), '<b>x</b>');
    });

    test('colonnes absentes de la ligne', () {
      final r = convertCsv(
        [
          ['a', 'b'],
        ],
        const CsvMapping(extra: 5, tags: 7),
        nowMs: 0,
      );
      expect(r.total, 1);
      expect(r.byDeck['']!.single.tags, isEmpty);
    });

    test('complément gardé', () {
      final r = convertCsv(
        [
          ['a', 'b', 'mnémo'],
        ],
        const CsvMapping(extra: 2),
        nowMs: 0,
      );
      expect(r.byDeck['']!.single.fields.extra, 'mnémo');
    });

    test('copyWith peut vider une colonne', () {
      const m = CsvMapping(tags: 2, deck: 3);
      final c = m.copyWith(tags: null);
      expect(c.tags, isNull);
      expect(c.deck, 3);
      expect(m.copyWith(type: NoteType.cloze).tags, 2);
    });
  });
}
