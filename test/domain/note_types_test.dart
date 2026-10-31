import 'dart:math';

import 'package:carabin/domain/note_types.dart';
import 'package:flutter_test/flutter_test.dart';

NoteFields f(Map<String, Object?> m) => NoteFields(m);

void main() {
  group('trous', () {
    test('découpe un texte à trous avec indice', () {
      final parts = parseCloze(
        'Le {{c1::cœur}} pompe le {{c2::sang::liquide}}.',
      );
      expect(parts.map((p) => p.text), [
        'Le ',
        'cœur',
        ' pompe le ',
        'sang',
        '.',
      ]);
      expect(parts.where((p) => p.isCloze).map((p) => p.number), [1, 2]);
      expect(parts[3].hint, 'liquide');
    });

    test('numéros triés et sans doublon', () {
      expect(clozeNumbers('{{c2::a}} {{c1::b}} {{c2::c}}'), [1, 2]);
      expect(nextClozeNumber('{{c1::a}} {{c3::b}}'), 4);
      expect(nextClozeNumber('rien'), 1);
    });

    test('enveloppe une sélection', () {
      expect(wrapCloze('Le cœur bat', 3, 7, 1), 'Le {{c1::cœur}} bat');
    });

    test('un trou peut contenir un retour à la ligne', () {
      expect(clozeNumbers('{{c1::a\nb}}'), [1]);
    });
  });

  group('validation', () {
    test('texte à trous', () {
      expect(
        validateNote(NoteType.cloze, f({'text': ''})),
        NoteIssue.emptyFront,
      );
      expect(
        validateNote(NoteType.cloze, f({'text': 'sans trou'})),
        NoteIssue.noCloze,
      );
      expect(
        validateNote(NoteType.cloze, f({'text': '{{c1::a'})),
        NoteIssue.clozeNotClosed,
      );
      expect(validateNote(NoteType.cloze, f({'text': '{{c1::a}}'})), isNull);
    });

    test('question-réponse', () {
      expect(
        validateNote(NoteType.basic, f({'front': '', 'back': 'x'})),
        NoteIssue.emptyFront,
      );
      expect(
        validateNote(NoteType.basic, f({'front': 'q', 'back': ' '})),
        NoteIssue.emptyBack,
      );
      expect(
        validateNote(NoteType.reversed, f({'front': 'q', 'back': 'r'})),
        isNull,
      );
      expect(
        validateNote(NoteType.typed, f({'front': 'q', 'back': 'r'})),
        isNull,
      );
    });

    test('occlusion', () {
      expect(validateNote(NoteType.occlusion, f({})), NoteIssue.noImage);
      expect(
        validateNote(NoteType.occlusion, f({'image': 'a.png'})),
        NoteIssue.noMask,
      );
      expect(
        validateNote(
          NoteType.occlusion,
          f({
            'image': 'a.png',
            'masks': [
              {'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.2},
            ],
          }),
        ),
        isNull,
      );
    });
  });

  group('cartes fabriquées', () {
    test('une carte par numéro de trou', () {
      expect(
        cardOrdinals(
          NoteType.cloze,
          f({'text': '{{c1::a}} {{c3::b}} {{c1::c}}'}),
        ),
        [1, 3],
      );
    });
    test('question-réponse : 1 ; réversible : 2 ; saisie : 1', () {
      expect(cardOrdinals(NoteType.basic, f({})), [0]);
      expect(cardOrdinals(NoteType.reversed, f({})), [0, 1]);
      expect(cardOrdinals(NoteType.typed, f({})), [0]);
    });
  });

  group('affichage', () {
    test('le trou actif est masqué à la question, révélé à la réponse', () {
      final fields = f({'text': 'Le {{c1::cœur}} et le {{c2::foie}}'});
      final q = renderFace(NoteType.cloze, fields, 1);
      expect(q.question.map((s) => s.role), contains(SegmentRole.hidden));
      expect(q.question.map((s) => s.text).join(), isNot(contains('cœur')));
      expect(q.question.map((s) => s.text).join(), contains('foie'));
      expect(q.answer.map((s) => s.role), contains(SegmentRole.revealed));
      expect(q.answer.map((s) => s.text).join(), contains('cœur'));
    });

    test('texte brut sans marques', () {
      expect(
        plainText(
          NoteType.cloze,
          f({'text': 'Le {{c1::**cœur**::organe}} bat'}),
        ),
        'Le cœur bat',
      );
      expect(
        plainText(NoteType.basic, f({'front': 'Q', 'back': 'R'})),
        'Q — R',
      );
      expect(plainText(NoteType.occlusion, f({'extra': ''})), '');
      expect(
        plainText(NoteType.occlusion, f({'extra': 'Coupe du cœur'})),
        'Coupe du cœur',
      );
    });
  });

  group('réponse saisie', () {
    test('ignore casse, accents, espaces et ponctuation finale', () {
      expect(typedAnswerMatches('  Œdème  ', 'oedème'), isTrue);
      expect(typedAnswerMatches('Aorte.', 'aorte'), isTrue);
      expect(typedAnswerMatches('', ''), isFalse);
      expect(typedAnswerMatches('veine', 'artère'), isFalse);
    });
  });

  group('mise en forme', () {
    test('gras, italique, souligné', () {
      final runs = parseRich('a **b** c');
      expect(runs.map((r) => r.text).join(), 'a b c');
      expect(runs.where((r) => r.bold).map((r) => r.text), ['b']);
    });
    test('marques non fermées restent du texte', () {
      expect(stripRich('2 * 3 = 6'), '2 * 3 = 6');
      expect(stripRich('2 * 3 * 4'), '2 * 3 * 4');
      expect(stripRich('**ouvert'), '**ouvert');
    });

    test('imbrications', () {
      final both = parseRich('***x***');
      expect(both.single.text, 'x');
      expect(both.single.bold && both.single.italic, isTrue);

      final inItalic = parseRich('*a **b** c*');
      expect(inItalic.map((r) => r.text).join(), 'a b c');
      expect(inItalic.every((r) => r.italic), isTrue);
      expect(inItalic.where((r) => r.bold).map((r) => r.text), ['b']);

      final inBold = parseRich('**a *b* c**');
      expect(inBold.map((r) => r.text).join(), 'a b c');
      expect(inBold.every((r) => r.bold), isTrue);
      expect(inBold.where((r) => r.italic).map((r) => r.text), ['b']);

      final mixed = parseRich('__==x==__');
      expect(mixed.single.underline && mixed.single.highlight, isTrue);
    });
  });

  group('images dans le texte', () {
    const img = '0123456789abcdef0123.png';

    test('une image est reconnue, le texte autour reste intact', () {
      final runs = parseRich('avant [img:$img] après');
      expect(runs.map((r) => r.image), [null, img, null]);
      expect(runs.map((r) => r.text), ['avant ', '', ' après']);
    });

    test('mise en forme et image se combinent', () {
      final runs = parseRich('**gras [img:$img] suite**');
      expect(runs.where((r) => r.image != null), hasLength(1));
      expect(runs.where((r) => r.image == null).every((r) => r.bold), isTrue);
    });

    test('un nom qui ne ressemble pas à un média reste du texte', () {
      for (final bad in [
        '[img:../secret.png]',
        '[img:a b.png]',
        '[img:x.png]',
        '[img:]',
      ]) {
        expect(parseRich(bad).single.image, isNull, reason: bad);
        expect(stripRich(bad), bad);
      }
    });

    test('stripRich retire les images ou les remplace par un symbole', () {
      expect(stripRich('a [img:$img] b'), 'a  b');
      expect(stripRich('a [img:$img] b', imageMark: '#'), 'a # b');
    });

    test('les listes montrent un symbole à la place de l\'image', () {
      expect(
        plainText(
          NoteType.basic,
          f({'front': 'Coupe [img:$img]', 'back': 'Cœur'}),
        ),
        'Coupe $imageListMark — Cœur',
      );
    });

    test('médias d\'une note : champs de texte et image d\'occlusion', () {
      const other = 'fedcba9876543210fedc.jpg';
      final fields = f({
        'front': 'a [img:$img]',
        'back': 'b [img:$other] [img:$img]',
        'image': '0000000000000000aaaa.webp',
      });
      expect(noteMedia(fields), {img, other, '0000000000000000aaaa.webp'});
      expect(noteMedia(f({'front': 'rien'})), isEmpty);
    });

    test('deux images différentes ne font pas un doublon', () {
      final a = f({'front': 'Coupe [img:$img]', 'back': 'x'});
      final b = f({
        'front': 'Coupe [img:fedcba9876543210fedc.png]',
        'back': 'x',
      });
      expect(
        duplicateKey(NoteType.basic, a),
        isNot(duplicateKey(NoteType.basic, b)),
      );
      expect(
        duplicateKey(NoteType.basic, a),
        duplicateKey(
          NoteType.basic,
          f({'front': 'Coupe [img:$img]', 'back': 'x'}),
        ),
      );
    });
  });

  group('occlusion', () {
    OcclusionMask m(int id, int group) => OcclusionMask(
      left: 0.1 * id,
      top: 0.1,
      width: 0.05,
      height: 0.05,
      group: group,
      id: id,
    );

    NoteFields occ(OcclusionMode mode, List<OcclusionMask> masks) => f({
      'image': 'a.png',
      'mode': mode.name,
      'masks': [for (final x in masks) x.toJson()],
    });

    test('tout caché : une carte, toutes les zones', () {
      final n = occ(OcclusionMode.hideAll, [m(1, 1), m(2, 1), m(3, 2)]);
      expect(cardOrdinals(NoteType.occlusion, n), [0]);
      expect(activeMasks(n, 0), hasLength(3));
    });

    test(
      'un seul caché : une carte par zone, numérotée par l\'identifiant',
      () {
        final n = occ(OcclusionMode.hideOne, [m(4, 1), m(7, 1)]);
        expect(cardOrdinals(NoteType.occlusion, n), [4, 7]);
        expect(activeMasks(n, 7).single.id, 7);
        expect(activeMasks(n, 5), isEmpty);
      },
    );

    test('supprimer une zone ne renumérote pas les autres cartes', () {
      final before = occ(OcclusionMode.hideOne, [m(1, 1), m(2, 1), m(3, 1)]);
      final after = occ(OcclusionMode.hideOne, [m(1, 1), m(3, 1)]);
      expect(cardOrdinals(NoteType.occlusion, before), [1, 2, 3]);
      expect(cardOrdinals(NoteType.occlusion, after), [1, 3]);
      expect(activeMasks(after, 3).single.left, closeTo(0.3, 1e-9));
    });

    test('groupement : une carte par groupe', () {
      final n = occ(OcclusionMode.group, [m(1, 2), m(2, 1), m(3, 2)]);
      expect(cardOrdinals(NoteType.occlusion, n), [1, 2]);
      expect(activeMasks(n, 2).map((x) => x.id), [1, 3]);
      expect(activeMasks(n, 1).map((x) => x.id), [2]);
    });

    test('anciennes notes sans identifiant : le rang sert d\'identifiant', () {
      final n = f({
        'image': 'a.png',
        'mode': 'hideOne',
        'masks': [
          {'x': 0.1, 'y': 0.1, 'w': 0.1, 'h': 0.1},
          {'x': 0.5, 'y': 0.5, 'w': 0.1, 'h': 0.1},
        ],
      });
      expect(cardOrdinals(NoteType.occlusion, n), [0, 1]);
      expect(activeMasks(n, 1).single.left, 0.5);
    });

    test('une occlusion identique est un doublon, pas une autre image', () {
      final a = occ(OcclusionMode.hideAll, [m(1, 1)]);
      final b = occ(OcclusionMode.hideAll, [m(1, 1)]);
      expect(
        duplicateKey(NoteType.occlusion, a),
        duplicateKey(NoteType.occlusion, b),
      );
      final c = f({...b.toMap(), 'image': 'b.png'});
      expect(
        duplicateKey(NoteType.occlusion, a),
        isNot(duplicateKey(NoteType.occlusion, c)),
      );
    });
  });

  group('échappement', () {
    test('une barre oblique inverse rend la marque littérale', () {
      expect(stripRich(r'2 \* 3 \* 4'), '2 * 3 * 4');
      expect(parseRich(r'\*pas italique\*').single.italic, isFalse);
      expect(stripRich(r'\*pas italique\*'), '*pas italique*');
      expect(stripRich(r'a\\b'), r'a\b');
      expect(stripRich(r'\__x\__'), '__x__');
      expect(stripRich(r'\==x\=='), '==x==');
    });

    test('une marque échappée ne referme pas une mise en forme', () {
      final runs = parseRich(r'*a \* b*');
      expect(runs.single.italic, isTrue);
      expect(runs.single.text, 'a * b');
    });

    test('les autres barres obliques restent', () {
      expect(stripRich(r'C:\temp \(x\)'), r'C:\temp \(x\)');
      expect(stripRich(r'fin\'), r'fin\'); // barre finale : rien à échapper
    });

    test(
      'escapeRich puis stripRich redonnent toujours le texte d\'origine',
      () {
        final rnd = Random(42);
        const alphabet = [
          '*',
          '_',
          '=',
          r'\',
          ' ',
          'a',
          'b',
          '{',
          '}',
          ':',
          '[',
          ']',
          'é',
          '\n',
        ];
        for (var i = 0; i < 3000; i++) {
          final s = [
            for (var k = rnd.nextInt(14); k > 0; k--)
              alphabet[rnd.nextInt(alphabet.length)],
          ].join();
          expect(
            stripRich(escapeRich(s)),
            s,
            reason: 'texte : ${s.replaceAll('\n', '⏎')}',
          );
          expect(
            parseRich(escapeRich(s)).every(
              (r) => !r.bold && !r.italic && !r.underline && !r.highlight,
            ),
            isTrue,
            reason: 'texte : $s',
          );
        }
      },
    );

    test('un texte échappé peut être mis en forme par-dessus', () {
      final text = '**${escapeRich('a * b')}**';
      final runs = parseRich(text);
      expect(runs.single.bold, isTrue);
      expect(runs.single.text, 'a * b');
    });
  });
}
