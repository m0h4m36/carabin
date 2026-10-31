import 'package:carabin/domain/qcm/text_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('foldForMatch', () {
    test('minuscules, accents et ponctuation', () {
      expect(
        foldForMatch('  Œdème   Pulmonaire, aigu !'),
        'oedeme pulmonaire aigu',
      );
      expect(foldForMatch('Ça va À l\'hôpital'), 'ca va a l hopital');
      expect(foldForMatch('β-bloquant'), 'β bloquant');
      expect(foldForMatch(''), '');
      expect(foldForMatch('...'), '');
    });
  });

  group('containsPhrase', () {
    test('mots entiers seulement', () {
      expect(containsPhrase('un ic severe', 'ic'), isTrue);
      expect(containsPhrase('ici', 'ic'), isFalse);
      expect(
        containsPhrase('syndrome coronarien aigu', 'coronarien aigu'),
        isTrue,
      );
      expect(containsPhrase('abc', ''), isFalse);
    });
  });

  group('elementMatches', () {
    test('synonymes avec |', () {
      expect(elementMatches('infarctus|IDM', 'Un IDM antérieur'), isTrue);
      expect(elementMatches('infarctus|IDM', 'Un infarctus'), isTrue);
      expect(elementMatches('infarctus|IDM', 'angor'), isFalse);
    });

    test('conditions multiples avec ;', () {
      const p = 'troponine;ECG';
      expect(elementMatches(p, 'ECG et troponine'), isTrue);
      expect(elementMatches(p, 'ECG seul'), isFalse);
      expect(elementMatches('a|b;c|d', 'b d'), isTrue);
      expect(elementMatches('a|b;c|d', 'b'), isFalse);
    });

    test('accents et casse ignorés', () {
      expect(
        elementMatches('œdème pulmonaire', 'OEDEME pulmonaire aigu'),
        isTrue,
      );
    });

    test('motif vide ne correspond jamais', () {
      expect(elementMatches('', 'texte'), isFalse);
      expect(elementMatches(' ; | ', 'texte'), isFalse);
      expect(parseExpected(' ; | '), isEmpty);
    });
  });
}
