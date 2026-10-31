/// Comparaison de réponses écrites (QROC) : on ignore les majuscules, les
/// accents et la ponctuation, et on cherche des mots entiers.
library;

const _folds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ž': 'z',
  'ź': 'z',
  'œ': 'oe',
  'æ': 'ae',
  'ß': 'ss',
  '’': "'",
  '‘': "'",
};

final _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Texte ramené à une forme comparable : minuscules, sans accents, tout ce
/// qui n'est ni lettre ni chiffre devient une espace simple.
String foldForMatch(String input) {
  final lower = input.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_folds[ch] ?? ch);
  }
  return out.toString().replaceAll(_notWord, ' ').trim();
}

/// Vrai si [phrase] (déjà passée par [foldForMatch]) figure dans [text]
/// (idem) comme suite de mots entiers.
bool containsPhrase(String text, String phrase) {
  if (phrase.isEmpty) return false;
  return ' $text '.contains(' $phrase ');
}

/// Un élément attendu d'un QROC : plusieurs conditions séparées par « ; »
/// (il faut toutes les trouver), chacune avec des synonymes séparés par « | »
/// (un seul suffit). Chaque terme est déjà passé par [foldForMatch].
List<List<String>> parseExpected(String pattern) {
  final groups = <List<String>>[];
  for (final part in pattern.split(';')) {
    final alternatives = [
      for (final a in part.split('|'))
        if (foldForMatch(a).isNotEmpty) foldForMatch(a),
    ];
    if (alternatives.isNotEmpty) groups.add(alternatives);
  }
  return groups;
}

/// Vrai si la réponse de l'étudiant contient l'élément attendu.
bool elementMatches(String pattern, String answer) {
  final groups = parseExpected(pattern);
  if (groups.isEmpty) return false;
  final text = foldForMatch(answer);
  return groups.every((alternatives) {
    return alternatives.any((a) => containsPhrase(text, a));
  });
}
