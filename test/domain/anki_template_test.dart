import 'package:carabin/domain/anki_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  helpers();
  final fields = {
    'Front': 'Aorte',
    'Back': 'Naît du VG',
    'Empty': '',
    'Br': '<br> <div></div>',
  };

  String r(
    String t, {
    String front = '',
    bool answer = false,
    Map<String, String> special = const {},
  }) => renderAnkiTemplate(
    t,
    fields,
    frontSide: front,
    answer: answer,
    special: special,
  );

  group('isAnkiFieldEmpty', () {
    test('vide, espaces, br et div vides', () {
      expect(isAnkiFieldEmpty(''), isTrue);
      expect(isAnkiFieldEmpty('  \n'), isTrue);
      expect(isAnkiFieldEmpty('<br>'), isTrue);
      expect(isAnkiFieldEmpty('<br/> <div></div> &nbsp;'), isTrue);
    });
    test('du contenu, même une image', () {
      expect(isAnkiFieldEmpty('a'), isFalse);
      expect(isAnkiFieldEmpty('<img src="x.png">'), isFalse);
      expect(isAnkiFieldEmpty('<b></b>'), isFalse);
    });
  });

  group('champs', () {
    test('simple', () {
      expect(r('{{Front}} → {{Back}}'), 'Aorte → Naît du VG');
    });
    test('espaces dans la balise, champ inconnu = vide', () {
      expect(r('{{ Front }}|{{Nope}}|'), 'Aorte||');
    });
    test('casse différente acceptée', () {
      expect(r('{{front}}'), 'Aorte');
    });
    test('FrontSide : seulement au verso', () {
      expect(r('{{FrontSide}}|{{Back}}', front: 'Q'), '|Naît du VG');
      expect(
        r('{{FrontSide}}|{{Back}}', front: 'Q', answer: true),
        'Q|Naît du VG',
      );
    });
    test('champs spéciaux', () {
      expect(
        r(
          '{{Tags}}/{{Deck}}/{{Card}}',
          special: {'Tags': 'a b', 'Deck': 'D', 'Card': 'Carte 1'},
        ),
        'a b/D/Carte 1',
      );
      expect(r('{{Tags}}'), '');
    });
    test('commentaire ignoré', () {
      expect(r('a{{! note }}b'), 'ab');
    });
    test('balise vide ou accolades simples', () {
      expect(r('{{}}x{y}'), 'x{y}');
    });
  });

  group('sections', () {
    test('conditionnelle', () {
      expect(r('{{#Front}}[{{Front}}]{{/Front}}'), '[Aorte]');
      expect(r('{{#Empty}}[x]{{/Empty}}'), '');
      expect(r('{{#Br}}[x]{{/Br}}'), '');
      expect(r('{{#Nope}}[x]{{/Nope}}'), '');
    });
    test('inversée', () {
      expect(r('{{^Empty}}vide{{/Empty}}'), 'vide');
      expect(r('{{^Front}}vide{{/Front}}'), '');
    });
    test('imbriquées', () {
      expect(
        r('{{#Front}}A{{#Empty}}B{{/Empty}}{{^Empty}}C{{/Empty}}{{/Front}}'),
        'AC',
      );
      expect(r('{{#Empty}}A{{#Front}}B{{/Front}}{{/Empty}}Z'), 'Z');
    });
    test('fermeture orpheline ignorée, section non fermée jusqu\'à la fin', () {
      expect(r('a{{/Front}}b'), 'ab');
      expect(r('{{#Front}}x'), 'x');
    });
    test(
      'section fermée en refermant les sections intérieures restées ouvertes',
      () {
        expect(r('{{#Front}}{{#Back}}y{{/Front}}z'), 'yz');
      },
    );
  });

  group('filtres', () {
    final f = {'Rich': '<b>gras</b><br>suite', 'Back': 'rép'};
    String rr(String t, {bool answer = false}) =>
        renderAnkiTemplate(t, f, answer: answer);

    test('text retire le HTML', () {
      expect(rr('{{text:Rich}}'), 'gras\nsuite');
    });
    test('type : seulement au verso', () {
      expect(rr('{{type:Back}}'), '');
      expect(rr('{{type:Back}}', answer: true), 'rép');
    });
    test('hint : seulement au verso', () {
      expect(rr('a{{hint:Back}}b'), 'ab');
      expect(rr('a{{hint:Back}}b', answer: true), 'arépb');
    });
    test('tts : rien', () {
      expect(rr('a{{tts en_US:Back}}b', answer: true), 'ab');
    });
    test('filtres enchaînés, de droite à gauche', () {
      expect(rr('{{type:text:Rich}}', answer: true), 'gras\nsuite');
      expect(rr('{{type:text:Rich}}'), '');
    });
    test('filtre inconnu : valeur inchangée', () {
      expect(rr('{{furigana:Back}}'), 'rép');
    });
  });

  test('modèle « Basique » complet', () {
    const q = '{{Front}}';
    const a = '{{FrontSide}}\n\n<hr id=answer>\n\n{{Back}}';
    final front = r(q);
    expect(front, 'Aorte');
    expect(
      r(a, front: front, answer: true),
      'Aorte\n\n<hr id=answer>\n\nNaît du VG',
    );
  });
}

void helpers() {
  group('ankiTemplateFields', () {
    test('champs, sections et filtres', () {
      expect(
        ankiTemplateFields(
          '{{Front}} {{#Extra}}{{text:Back}}{{/Extra}} {{^Z}}{{/Z}} {{! x}} {{FrontSide}}',
        ),
        {'Front', 'Extra', 'Back', 'Z', 'FrontSide'},
      );
    });
  });

  group('ankiClozeField', () {
    test('trouve le champ à trous', () {
      expect(ankiClozeField('{{cloze:Texte}}'), 'Texte');
      expect(ankiClozeField('{{Titre}}<br>{{cloze:Corps}}'), 'Corps');
      expect(ankiClozeField('{{type:cloze:Texte}}'), 'Texte');
    });
    test('aucun', () {
      expect(ankiClozeField('{{Front}}'), isNull);
      expect(ankiClozeField(''), isNull);
    });
  });

  group('ankiAnswerOnly', () {
    test('après la ligne de réponse', () {
      expect(ankiAnswerOnly('Q<hr id=answer>R', 'Q'), 'R');
      expect(ankiAnswerOnly('Q<HR ID="answer" />R', 'Q'), 'R');
      expect(ankiAnswerOnly("Q<hr id='answer'>R", 'Q'), 'R');
    });
    test('sans ligne : on retire la question reprise au début', () {
      expect(ankiAnswerOnly('QR', 'Q'), 'R');
    });
    test('ni l\'un ni l\'autre : tout le verso', () {
      expect(ankiAnswerOnly('R', 'Q'), 'R');
      expect(ankiAnswerOnly('R', ''), 'R');
    });
    test('une autre ligne n\'est pas la ligne de réponse', () {
      expect(ankiAnswerOnly('Q<hr>R', 'Q'), '<hr>R');
      expect(ankiAnswerOnly('A<hr id=autre>B', 'X'), 'A<hr id=autre>B');
    });
  });
}
