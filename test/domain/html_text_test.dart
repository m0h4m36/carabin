import 'package:carabin/domain/html_text.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:flutter_test/flutter_test.dart';

String conv(String html, {Map<String, String> images = const {}}) =>
    HtmlConverter(image: (src) => images[src]).convert(html);

void main() {
  group('mise en forme', () {
    test('gras, italique, souligné, surlignage', () {
      expect(
        conv('un <b>gras</b> et <i>italique</i>'),
        'un **gras** et *italique*',
      );
      expect(
        conv('<strong>a</strong> <em>b</em> <u>c</u> <mark>d</mark>'),
        '**a** *b* __c__ ==d==',
      );
    });

    test('gras et italique ensemble', () {
      expect(conv('<b><i>x</i></b>'), '***x***');
      expect(conv('<b>a <i>b</i> c</b>'), '**a** ***b*** **c**');
    });

    test('les espaces de bord sortent des marques', () {
      expect(conv('<b>mot </b>suivant'), '**mot** suivant');
      expect(conv('avant<b> mot</b>'), 'avant **mot**');
      expect(conv('<b> </b>seul'), 'seul');
    });

    test('style en ligne (span) : gras, italique, souligné, surlignage', () {
      expect(conv('<span style="font-weight: bold;">x</span>'), '**x**');
      expect(conv('<span style="font-style:italic">x</span>'), '*x*');
      expect(
        conv('<span style="text-decoration: underline;">x</span>'),
        '__x__',
      );
      expect(
        conv('<span style="background-color: rgb(255, 255, 0);">x</span>'),
        '==x==',
      );
      expect(
        conv('<span style="background-color: transparent;">x</span>'),
        'x',
      );
      expect(conv('<span style="color: red;">x</span>'), 'x');
    });

    test('balises mal fermées ou en trop ne cassent rien', () {
      expect(stripRich(conv('<b>a<i>b</b>c</i>')), 'abc');
      expect(conv('texte</b> sans ouverture'), 'texte sans ouverture');
      expect(conv('<b>jamais fermé'), '**jamais fermé**');
    });

    test('ce qui sort est relu comme prévu par l\'affichage', () {
      final out = conv('<b>Le cœur</b> <i>pompe</i> le <u>sang</u>');
      final runs = parseRich(out);
      expect(runs.where((r) => r.bold).map((r) => r.text), ['Le cœur']);
      expect(runs.where((r) => r.italic).map((r) => r.text), ['pompe']);
      expect(runs.where((r) => r.underline).map((r) => r.text), ['sang']);
      expect(stripRich(out), 'Le cœur pompe le sang');
    });
  });

  group('structure', () {
    test('sauts de ligne', () {
      expect(conv('a<br>b'), 'a\nb');
      expect(conv('a<br><br>b'), 'a\n\nb');
      expect(conv('<div>a</div><div>b</div>'), 'a\nb');
      expect(conv('<p>a</p><p>b</p>'), 'a\nb');
      expect(conv('<div>\n  a\n</div>\n<div>\n  b\n</div>'), 'a\nb');
    });

    test(
      'l\'espace du HTML se replie, les retours à la ligne du source aussi',
      () {
        expect(conv('a   \n   b'), 'a b');
      },
    );

    test('listes', () {
      expect(conv('<ul><li>un</li><li>deux</li></ul>'), '• un\n• deux');
      expect(conv('<ol><li>un</li><li>deux</li></ol>'), '1. un\n2. deux');
    });

    test('tableau : cellules séparées, une ligne par rangée', () {
      expect(
        conv(
          '<table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table>',
        ),
        'A | B\nC | D',
      );
    });

    test('exposants et indices en Unicode quand c\'est possible', () {
      expect(conv('m<sup>2</sup>'), 'm²');
      expect(conv('H<sub>2</sub>O'), 'H₂O');
      expect(conv('Na<sup>+</sup>'), 'Na⁺');
      expect(conv('x<sup>abc</sup>'), 'x^(abc)');
    });

    test('scripts, styles et commentaires disparaissent', () {
      expect(
        conv('a<script>alert(1)</script>b<style>p{}</style>c<!-- note -->d'),
        'abcd',
      );
    });

    test('les liens gardent leur texte', () {
      expect(conv('<a href="http://x.fr">ici</a>'), 'ici');
    });
  });

  group('entités et caractères spéciaux', () {
    test('entités nommées et numériques', () {
      expect(
        conv('caf&eacute; &amp; th&#233; &#x3b1; &lt;3'),
        'café & thé α <3',
      );
      expect(conv('a&nbsp;b'), 'a b');
      expect(conv('&inconnue; &#0; &#xD800;'), '&inconnue; &#0; &#xD800;');
    });

    test(
      'les étoiles et soulignés littéraux sont échappés pour rester littéraux',
      () {
        final out = conv('p<0,05* et *autre note*');
        expect(out, r'p<0,05\* et \*autre note\*');
        expect(stripRich(out), 'p<0,05* et *autre note*');
        expect(parseRich(out).every((r) => !r.italic), isTrue);
        expect(stripRich(conv('Le ______ pompe')), 'Le ______ pompe');
        expect(
          parseRich(conv('Le ______ pompe')).every((r) => !r.underline),
          isTrue,
        );
        expect(stripRich(conv('a==b et c==d')), 'a==b et c==d');
      },
    );

    test('une barre oblique inverse reste elle-même', () {
      final out = conv(r'\(x_1\) et C:\temp');
      expect(stripRich(out), r'\(x_1\) et C:\temp');
    });

    test('un astérisque dans du gras reste littéral', () {
      final out = conv('<b>a * b</b>');
      expect(stripRich(out), 'a * b');
      expect(parseRich(out).single.bold, isTrue);
    });
  });

  group('trous', () {
    test('les trous traversent la conversion', () {
      final out = conv('Le {{c1::<b>cœur</b>}} pompe le {{c2::sang::liquide}}');
      expect(out, 'Le {{c1::**cœur**}} pompe le {{c2::sang::liquide}}');
      expect(clozeNumbers(out), [1, 2]);
    });
  });

  group('images et sons', () {
    const known = '0123456789abcdef0123.png';

    test('image connue : remplacée par sa marque', () {
      expect(
        conv('<img src="a.png">', images: {'a.png': known}),
        '[img:$known]',
      );
      expect(
        conv("<img class='x' src='a.png' />", images: {'a.png': known}),
        '[img:$known]',
      );
      expect(
        conv(
          'avant <img alt="a > b" src=a.png> après',
          images: {'a.png': known},
        ),
        'avant [img:$known] après',
      );
    });

    test('image inconnue ou non prise en charge : retirée et comptée', () {
      final c = HtmlConverter(image: (_) => null);
      expect(c.convert('x<img src="b.svg">y'), 'xy');
      expect(c.droppedImages, 1);
    });

    test('sons retirés et comptés', () {
      final c = HtmlConverter();
      expect(c.convert('mot [sound:mot.mp3] fin'), 'mot fin');
      expect(c.droppedSounds, 1);
    });

    test('le nom de fichier de l\'image est décodé (entités)', () {
      expect(
        conv('<img src="a&amp;b.png">', images: {'a&b.png': known}),
        '[img:$known]',
      );
    });
  });

  test('vide', () {
    expect(conv(''), '');
    expect(conv('   '), '');
    expect(conv('<br>'), '');
    expect(conv('<div><br></div>'), '');
  });
}
