/// Rendu des modèles de cartes d'Anki (`{{Champ}}`, `{{#Champ}}…{{/Champ}}`,
/// `{{^Champ}}…{{/Champ}}`, filtres `text:`, `type:`, `hint:`…).
///
/// Sert à retrouver, pour un type de note personnalisé, ce qui s'affiche au
/// recto et au verso de chaque carte. Le résultat est du HTML, à convertir
/// ensuite avec `HtmlConverter`.
library;

/// Un champ est vide s'il ne contient que des espaces, des `<br>` ou des
/// `<div>` (même règle qu'Anki : une image compte comme du contenu).
bool isAnkiFieldEmpty(String value) => _emptyField.hasMatch(value);

final _emptyField = RegExp(
  r'^(?:\s|&nbsp;|</?(?:br|div)\s*/?>)*$',
  caseSensitive: false,
);

/// Champs spéciaux que le modèle peut utiliser sans qu'ils fassent partie de
/// la note.
const ankiSpecialFields = {'Tags', 'Deck', 'Subdeck', 'Card', 'Type'};

/// Retire les balises HTML (pour le filtre `text:`).
String stripHtmlTags(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '');

/// Rend [template] avec les valeurs des champs.
///
/// [frontSide] remplace `{{FrontSide}}` (face de réponse seulement) ;
/// [answer] indique si l'on rend le verso, ce qui change `{{type:…}}` et
/// `{{hint:…}}` (affichés seulement au verso) ; [special] donne les champs
/// spéciaux (`Tags`, `Deck`, `Subdeck`, `Card`, `Type`).
String renderAnkiTemplate(
  String template,
  Map<String, String> fields, {
  String frontSide = '',
  bool answer = false,
  Map<String, String> special = const {},
}) {
  final lower = {for (final e in fields.entries) e.key.toLowerCase(): e.value};
  String? lookup(String name) => fields[name] ?? lower[name.toLowerCase()];

  final root = _parse(template);
  final out = StringBuffer();

  void render(List<_Node> nodes) {
    for (final n in nodes) {
      switch (n) {
        case _Text(:final text):
          out.write(text);
        case _Field(:final filters, :final name):
          out.write(
            _fieldValue(
              filters,
              name,
              lookup(name),
              frontSide: frontSide,
              answer: answer,
              special: special,
            ),
          );
        case _Section(:final name, :final inverted, :final children):
          final value = lookup(name);
          final present = value != null && !isAnkiFieldEmpty(value);
          if (present != inverted) render(children);
      }
    }
  }

  render(root);
  return out.toString();
}

String _fieldValue(
  List<String> filters,
  String name,
  String? value, {
  required String frontSide,
  required bool answer,
  required Map<String, String> special,
}) {
  if (name == 'FrontSide' && filters.isEmpty) return answer ? frontSide : '';
  var v = value ?? special[name] ?? '';
  // les filtres s'appliquent de droite à gauche
  for (final f in filters.reversed) {
    final key = f.trim().toLowerCase();
    if (key == 'text') {
      v = stripHtmlTags(v);
    } else if (key == 'type' || key == 'hint') {
      if (!answer) return '';
    } else if (key.startsWith('tts')) {
      return '';
    }
    // autres filtres (cloze, furigana…) : la valeur passe telle quelle
  }
  return v;
}

// ------------------------------------------------------------------- arbre

sealed class _Node {}

class _Text extends _Node {
  _Text(this.text);
  final String text;
}

class _Field extends _Node {
  _Field(this.filters, this.name);
  final List<String> filters;
  final String name;
}

class _Section extends _Node {
  _Section(this.name, this.inverted);
  final String name;
  final bool inverted;
  final List<_Node> children = [];
}

final _tag = RegExp(r'\{\{([^{}]*)\}\}');

List<_Node> _parse(String template) {
  final root = <_Node>[];
  // pile des sections ouvertes ; la liste courante est celle du sommet
  final stack = <_Section>[];
  List<_Node> current() => stack.isEmpty ? root : stack.last.children;

  var pos = 0;
  for (final m in _tag.allMatches(template)) {
    if (m.start > pos) current().add(_Text(template.substring(pos, m.start)));
    pos = m.end;
    final body = m.group(1)!.trim();
    if (body.isEmpty) continue;
    final head = body[0];
    if (head == '!') continue; // commentaire
    if (head == '#' || head == '^') {
      final s = _Section(body.substring(1).trim(), head == '^');
      current().add(s);
      stack.add(s);
    } else if (head == '/') {
      final name = body.substring(1).trim();
      final i = stack.lastIndexWhere((s) => s.name == name);
      // fermeture sans ouverture : ignorée ; sinon on referme aussi les
      // sections restées ouvertes à l'intérieur
      if (i >= 0) stack.removeRange(i, stack.length);
    } else {
      final parts = body.split(':');
      final name = parts.last.trim();
      current().add(
        _Field([for (final p in parts.take(parts.length - 1)) p], name),
      );
    }
  }
  if (pos < template.length) current().add(_Text(template.substring(pos)));
  return root;
}

/// Noms des champs utilisés par un modèle (champs simples, sections et
/// filtres), champs spéciaux compris.
Set<String> ankiTemplateFields(String template) {
  final names = <String>{};
  for (final m in _tag.allMatches(template)) {
    var body = m.group(1)!.trim();
    if (body.isEmpty || body[0] == '!' || body[0] == '/') continue;
    if (body[0] == '#' || body[0] == '^') body = body.substring(1).trim();
    final name = body.split(':').last.trim();
    if (name.isNotEmpty) names.add(name);
  }
  return names;
}

/// Champ visé par un filtre `{{cloze:Champ}}`, ou null s'il n'y en a pas.
String? ankiClozeField(String template) {
  for (final m in _tag.allMatches(template)) {
    final parts = m.group(1)!.trim().split(':');
    if (parts.length < 2) continue;
    final filters = parts
        .take(parts.length - 1)
        .map((f) => f.trim().toLowerCase());
    if (filters.contains('cloze') || filters.contains('cloze-only')) {
      return parts.last.trim();
    }
  }
  return null;
}

/// Ce que la réponse ajoute à la question : le HTML qui suit la ligne
/// `<hr id=answer>` quand elle existe, sinon la réponse privée de la question
/// qu'elle reprend au début.
String ankiAnswerOnly(String answerHtml, String questionHtml) {
  final hr = RegExp(
    r'''<hr[^>]*\bid\s*=\s*["']?answer["']?[^>]*>''',
    caseSensitive: false,
  ).firstMatch(answerHtml);
  if (hr != null) return answerHtml.substring(hr.end);
  if (questionHtml.isNotEmpty && answerHtml.startsWith(questionHtml)) {
    return answerHtml.substring(questionHtml.length);
  }
  return answerHtml;
}
