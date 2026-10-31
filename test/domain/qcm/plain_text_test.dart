import 'package:carabin/domain/qcm/plain_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retire les marques de mise en forme', () {
    expect(
      plainOf('**gras** et *italique* et __souligné__ et ==surligné=='),
      'gras et italique et souligné et surligné',
    );
  });

  test('retire les images et les blancs en trop', () {
    expect(
      plainOf('Avant [img:abcdef0123456789.png]\n\n  après  '),
      'Avant après',
    );
  });

  test('un astérisque échappé ou une multiplication restent du texte', () {
    expect(plainOf('2 * 3 * 4'), '2 * 3 * 4');
    expect(plainOf(r'a \* b'), 'a * b');
  });

  test('texte vide', () {
    expect(plainOf(''), '');
    expect(plainOf('   \n '), '');
    expect(snippet(''), '');
  });

  test('snippet coupe et ajoute des points de suspension', () {
    expect(snippet('abc', max: 5), 'abc');
    expect(snippet('abcdefghij', max: 5), 'abcde…');
    expect(snippet('abcd efghij', max: 5), 'abcd…');
  });
}
