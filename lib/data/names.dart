/// Outils pour transformer un nom saisi par l'utilisateur en nom de dossier
/// ou de fichier valide sur Windows, macOS, Android et iOS.
library;

const _reserved = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

final _forbidden = RegExp(r'[<>:"/\\|?*\u0000-\u001F]');

/// Nom sûr pour le système de fichiers (jamais vide, jamais réservé).
String safeFileName(String input, {int maxLength = 100}) {
  var s = input.replaceAll(_forbidden, '_').trim();
  // Windows refuse les points et espaces en fin de nom.
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  if (s.length > maxLength) {
    s = s.substring(0, maxLength).replaceAll(RegExp(r'[. ]+$'), '');
  }
  if (s.isEmpty) s = '_';
  final stem = s.contains('.') ? s.substring(0, s.indexOf('.')) : s;
  if (_reserved.contains(stem.toLowerCase())) s = '_$s';
  return s;
}

/// Forme comparable d'un nom : minuscules, sans accents (pour la recherche
/// et pour détecter deux noms qui donneraient le même dossier).
String normalize(String input) {
  final lower = input.toLowerCase();
  final b = StringBuffer();
  for (final r in lower.runes) {
    final c = String.fromCharCode(r);
    b.write(_accents[c] ?? c);
  }
  return b.toString();
}

const Map<String, String> _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};
