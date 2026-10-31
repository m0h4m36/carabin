/// Texte sans mise en forme de Carabin (gras, italique, souligné, surligné,
/// images), pour les titres et aperçus d'une ligne.
library;

import '../note_types.dart';

final _spaces = RegExp(r'\s+');

String plainOf(String text) =>
    stripRich(text, imageMark: ' ').replaceAll(_spaces, ' ').trim();

/// Début d'un texte, coupé proprement sur [max] caractères.
String snippet(String text, {int max = 90}) {
  final s = plainOf(text);
  if (s.length <= max) return s;
  return '${s.substring(0, max).trimRight()}…';
}
