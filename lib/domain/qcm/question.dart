/// Questions d'une épreuve : modèle, validation et lecture / écriture JSON
/// (le même JSON sert à la base de données et au fichier `.qcm.json`).
library;

import 'text_match.dart';

/// Genre d'une question. Le nom (`name`) est ce qui est enregistré.
enum QuestionKind {
  /// Propositions à cocher : une seule bonne réponse (QRU) ou plusieurs (QRM).
  qcm,

  /// Propositions dont on connaît le nombre de bonnes réponses attendues.
  qrp,

  /// Réponse courte écrite.
  qroc,

  /// Test de concordance de script.
  tcs,

  /// Zone à pointer sur une image.
  qzp,
}

/// Ce qui empêche une question d'être posée.
enum QuestionIssue {
  emptyBody,
  tooFewPropositions,
  noCorrectProposition,
  qrocNothingToCompare,
  tcsHypothesis,
  tcsNewInfo,
  tcsPanel,
  qzpImage,
  qzpZone,
}

const maxPropositions = 26;
const maxImagesPerQuestion = 12;
const maxZones = 60;
const maxElements = 40;
const tcsLevels = 5;

Map<String, dynamic> _map(Object? v, String where) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  throw FormatException('objet attendu ($where)');
}

String _string(Object? v, String where, {int max = 20000}) {
  if (v == null) return '';
  if (v is! String) throw FormatException('texte attendu ($where)');
  return v.length > max ? v.substring(0, max) : v;
}

double _number(Object? v, String where, {double fallback = 0}) {
  if (v == null) return fallback;
  if (v is! num || !v.isFinite) {
    throw FormatException('nombre attendu ($where)');
  }
  return v.toDouble();
}

bool _bool(Object? v) => v == true;

List<Object?> _list(Object? v, String where, {int max = 100000}) {
  if (v == null) return const [];
  if (v is! List) throw FormatException('liste attendue ($where)');
  if (v.length > max) throw FormatException('liste trop longue ($where)');
  return v;
}

/// Zone rectangulaire d'une image, en fractions de sa largeur / hauteur.
class Zone {
  const Zone({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory Zone.fromJson(Object? j) {
    final m = _map(j, 'zone');
    final z = Zone(
      left: _number(m['x'], 'x'),
      top: _number(m['y'], 'y'),
      width: _number(m['w'], 'w'),
      height: _number(m['h'], 'h'),
    );
    if (z.left < -0.001 ||
        z.top < -0.001 ||
        z.width <= 0 ||
        z.height <= 0 ||
        z.left + z.width > 1.001 ||
        z.top + z.height > 1.001) {
      throw const FormatException('zone hors de l\'image');
    }
    return z;
  }

  final double left;
  final double top;
  final double width;
  final double height;

  bool contains(double x, double y) =>
      x >= left && x <= left + width && y >= top && y <= top + height;

  Map<String, Object?> toJson() => {
    'x': left,
    'y': top,
    'w': width,
    'h': height,
  };

  @override
  bool operator ==(Object other) =>
      other is Zone &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// Une proposition d'un QCM ou d'un QRP.
///
/// [critical] : pour une bonne réponse, elle est indispensable (l'oublier
/// annule la question) ; pour une mauvaise, elle est inacceptable (la cocher
/// annule la question). Règle du barème EDN.
class Proposition {
  const Proposition({
    this.text = '',
    this.correct = false,
    this.critical = false,
  });

  factory Proposition.fromJson(Object? j) {
    final m = _map(j, 'proposition');
    return Proposition(
      text: _string(m['text'], 'text', max: 4000),
      correct: _bool(m['correct']),
      critical: _bool(m['critical']),
    );
  }

  final String text;
  final bool correct;
  final bool critical;

  bool get isBlank => text.trim().isEmpty;

  Proposition copyWith({String? text, bool? correct, bool? critical}) =>
      Proposition(
        text: text ?? this.text,
        correct: correct ?? this.correct,
        critical: critical ?? this.critical,
      );

  Map<String, Object?> toJson() => {
    'text': text,
    'correct': correct,
    if (critical) 'critical': true,
  };

  @override
  bool operator ==(Object other) =>
      other is Proposition &&
      other.text == text &&
      other.correct == correct &&
      other.critical == critical;

  @override
  int get hashCode => Object.hash(text, correct, critical);
}

/// Un élément attendu dans la réponse écrite d'un QROC.
class ExpectedElement {
  const ExpectedElement({this.pattern = '', this.points = 1});

  factory ExpectedElement.fromJson(Object? j) {
    final m = _map(j, 'élément');
    return ExpectedElement(
      pattern: _string(m['pattern'], 'pattern', max: 2000),
      points: _number(m['points'], 'points', fallback: 1),
    );
  }

  /// Texte avec « ; » (tout trouver) et « | » (synonymes).
  final String pattern;
  final double points;

  /// Un élément vide ou sans point est ignoré.
  bool get isUsable => points > 0 && parseExpected(pattern).isNotEmpty;

  ExpectedElement copyWith({String? pattern, double? points}) =>
      ExpectedElement(
        pattern: pattern ?? this.pattern,
        points: points ?? this.points,
      );

  Map<String, Object?> toJson() => {'pattern': pattern, 'points': points};

  @override
  bool operator ==(Object other) =>
      other is ExpectedElement &&
      other.pattern == pattern &&
      other.points == points;

  @override
  int get hashCode => Object.hash(pattern, points);
}

/// Une question, quel que soit son genre.
sealed class Question {
  const Question({
    this.body = '',
    this.images = const [],
    this.explanation = '',
    this.points = 1,
  });

  /// Énoncé (texte mis en forme avec les marques de Carabin).
  final String body;

  /// Noms de fichiers des images jointes (dossier de médias).
  final List<String> images;

  /// Explication lue à la correction.
  final String explanation;

  /// Valeur de la question dans le barème.
  final double points;

  QuestionKind get kind;

  /// Raisons pour lesquelles la question n'est pas encore posable.
  List<QuestionIssue> get issues;

  bool get isReady => issues.isEmpty;

  /// Tous les médias cités (images, image à pointer).
  Set<String> get mediaNames => {...images};

  Map<String, Object?> toJson();

  /// Même question avec les médias renommés par [rename].
  Question remapMedia(String Function(String name) rename);

  Question withCommon({
    String? body,
    List<String>? images,
    String? explanation,
    double? points,
  });

  /// Question vide d'un genre donné.
  factory Question.empty(QuestionKind kind) => switch (kind) {
    QuestionKind.qcm => const ChoiceQuestion(
      propositions: [Proposition(), Proposition()],
    ),
    QuestionKind.qrp => const ChoiceQuestion(
      pointed: true,
      propositions: [Proposition(), Proposition()],
    ),
    QuestionKind.qroc => const QrocQuestion(),
    QuestionKind.tcs => const TcsQuestion(),
    QuestionKind.qzp => const QzpQuestion(),
  };

  /// Change le genre en gardant ce qui est commun (énoncé, images,
  /// explication, points) et, entre QCM et QRP, les propositions.
  Question convertTo(QuestionKind target) {
    if (target == kind) return this;
    final base = Question.empty(target).withCommon(
      body: body,
      images: images,
      explanation: explanation,
      points: points,
    );
    if (this is ChoiceQuestion && base is ChoiceQuestion) {
      return base.copyWith(propositions: (this as ChoiceQuestion).propositions);
    }
    return base;
  }

  factory Question.fromJson(Object? j) {
    final m = _map(j, 'question');
    final name = m['kind'];
    final kind = QuestionKind.values.where((k) => k.name == name);
    if (kind.isEmpty) throw FormatException('genre inconnu : $name');
    final body = _string(m['body'], 'body');
    final images = [
      for (final i in _list(m['images'], 'images', max: maxImagesPerQuestion))
        _mediaName(i),
    ];
    final explanation = _string(m['explanation'], 'explanation');
    final points = _number(m['points'], 'points', fallback: 1);
    if (points <= 0 || points > 1000) {
      throw const FormatException('points invalides');
    }
    switch (kind.first) {
      case QuestionKind.qcm:
      case QuestionKind.qrp:
        return ChoiceQuestion(
          body: body,
          images: images,
          explanation: explanation,
          points: points,
          pointed: kind.first == QuestionKind.qrp,
          propositions: [
            for (final p in _list(
              m['propositions'],
              'propositions',
              max: maxPropositions,
            ))
              Proposition.fromJson(p),
          ],
        );
      case QuestionKind.qroc:
        final lines = m['maxLines'];
        return QrocQuestion(
          body: body,
          images: images,
          explanation: explanation,
          points: points,
          nature: _string(m['nature'], 'nature', max: 200),
          maxLines: lines is int && lines > 0 && lines <= 50 ? lines : null,
          model: _string(m['model'], 'model'),
          elements: [
            for (final e in _list(m['elements'], 'elements', max: maxElements))
              ExpectedElement.fromJson(e),
          ],
        );
      case QuestionKind.tcs:
        final panel = [
          for (final c in _list(m['panel'], 'panel', max: tcsLevels)) _count(c),
        ];
        while (panel.length < tcsLevels) {
          panel.add(0);
        }
        return TcsQuestion(
          body: body,
          images: images,
          explanation: explanation,
          points: points,
          hypothesis: _string(m['hypothesis'], 'hypothesis'),
          newInfo: _string(m['newInfo'], 'newInfo'),
          lowLabel: _string(m['lowLabel'], 'lowLabel', max: 200),
          highLabel: _string(m['highLabel'], 'highLabel', max: 200),
          panel: panel,
        );
      case QuestionKind.qzp:
        final image = m['image'];
        return QzpQuestion(
          body: body,
          images: images,
          explanation: explanation,
          points: points,
          image: image == null ? '' : _mediaName(image),
          zones: [
            for (final z in _list(m['zones'], 'zones', max: maxZones))
              Zone.fromJson(z),
          ],
        );
    }
  }
}

final _mediaFile = RegExp(r'^[0-9a-f]{8,64}\.[a-z0-9]{2,5}$');

String _mediaName(Object? v) {
  if (v is! String || !_mediaFile.hasMatch(v)) {
    throw const FormatException('nom de média invalide');
  }
  return v;
}

int _count(Object? v) {
  if (v is! int || v < 0 || v > 100000) {
    throw const FormatException('effectif invalide');
  }
  return v;
}

/// Forme d'une question à propositions.
enum ChoiceShape {
  /// Une seule bonne réponse.
  qru,

  /// Plusieurs bonnes réponses.
  qrm,

  /// Nombre de bonnes réponses attendues connu.
  qrp,
}

class ChoiceQuestion extends Question {
  const ChoiceQuestion({
    super.body,
    super.images,
    super.explanation,
    super.points,
    this.propositions = const [],
    this.pointed = false,
  });

  final List<Proposition> propositions;

  /// Vrai pour un QRP.
  final bool pointed;

  @override
  QuestionKind get kind => pointed ? QuestionKind.qrp : QuestionKind.qcm;

  /// Propositions réellement écrites (les lignes vides sont ignorées).
  List<Proposition> get written => [
    for (final p in propositions)
      if (!p.isBlank) p,
  ];

  int get correctCount => written.where((p) => p.correct).length;

  ChoiceShape get shape {
    if (pointed) return ChoiceShape.qrp;
    return correctCount > 1 ? ChoiceShape.qrm : ChoiceShape.qru;
  }

  /// Même question sans les propositions vides : c'est celle qu'on pose et
  /// qu'on garde dans une copie.
  ChoiceQuestion cleaned() => copyWith(propositions: written);

  @override
  List<QuestionIssue> get issues => [
    if (body.trim().isEmpty) QuestionIssue.emptyBody,
    if (written.length < 2) QuestionIssue.tooFewPropositions,
    if (correctCount == 0) QuestionIssue.noCorrectProposition,
  ];

  ChoiceQuestion copyWith({List<Proposition>? propositions, bool? pointed}) =>
      ChoiceQuestion(
        body: body,
        images: images,
        explanation: explanation,
        points: points,
        propositions: propositions ?? this.propositions,
        pointed: pointed ?? this.pointed,
      );

  @override
  ChoiceQuestion withCommon({
    String? body,
    List<String>? images,
    String? explanation,
    double? points,
  }) => ChoiceQuestion(
    body: body ?? this.body,
    images: images ?? this.images,
    explanation: explanation ?? this.explanation,
    points: points ?? this.points,
    propositions: propositions,
    pointed: pointed,
  );

  @override
  ChoiceQuestion remapMedia(String Function(String name) rename) =>
      withCommon(images: [for (final i in images) rename(i)]);

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'body': body,
    if (images.isNotEmpty) 'images': images,
    'explanation': explanation,
    'points': points,
    'propositions': [for (final p in propositions) p.toJson()],
  };
}

class QrocQuestion extends Question {
  const QrocQuestion({
    super.body,
    super.images,
    super.explanation,
    super.points,
    this.nature = '',
    this.maxLines,
    this.model = '',
    this.elements = const [],
  });

  /// Nature de la réponse attendue (« Un diagnostic »…) ; vide = texte libre.
  final String nature;

  /// Longueur maximale en lignes, ou null.
  final int? maxLines;

  /// Réponse modèle montrée à la correction.
  final String model;
  final List<ExpectedElement> elements;

  List<ExpectedElement> get usableElements => [
    for (final e in elements)
      if (e.isUsable) e,
  ];

  /// Vrai si la réponse est corrigée par l'appli ; sinon l'étudiant
  /// s'évalue lui-même face à la réponse modèle.
  bool get autoGraded => usableElements.isNotEmpty;

  @override
  QuestionKind get kind => QuestionKind.qroc;

  @override
  List<QuestionIssue> get issues => [
    if (body.trim().isEmpty) QuestionIssue.emptyBody,
    if (!autoGraded && model.trim().isEmpty) QuestionIssue.qrocNothingToCompare,
  ];

  QrocQuestion copyWith({
    String? nature,
    Object? maxLines = _keep,
    String? model,
    List<ExpectedElement>? elements,
  }) => QrocQuestion(
    body: body,
    images: images,
    explanation: explanation,
    points: points,
    nature: nature ?? this.nature,
    maxLines: identical(maxLines, _keep) ? this.maxLines : maxLines as int?,
    model: model ?? this.model,
    elements: elements ?? this.elements,
  );

  @override
  QrocQuestion withCommon({
    String? body,
    List<String>? images,
    String? explanation,
    double? points,
  }) => QrocQuestion(
    body: body ?? this.body,
    images: images ?? this.images,
    explanation: explanation ?? this.explanation,
    points: points ?? this.points,
    nature: nature,
    maxLines: maxLines,
    model: model,
    elements: elements,
  );

  @override
  QrocQuestion remapMedia(String Function(String name) rename) =>
      withCommon(images: [for (final i in images) rename(i)]);

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'body': body,
    if (images.isNotEmpty) 'images': images,
    'explanation': explanation,
    'points': points,
    if (nature.isNotEmpty) 'nature': nature,
    if (maxLines != null) 'maxLines': maxLines,
    'model': model,
    'elements': [for (final e in elements) e.toJson()],
  };
}

const Object _keep = Object();

class TcsQuestion extends Question {
  const TcsQuestion({
    super.body,
    super.images,
    super.explanation,
    super.points,
    this.hypothesis = '',
    this.newInfo = '',
    this.lowLabel = '',
    this.highLabel = '',
    this.panel = const [0, 0, 0, 0, 0],
  });

  /// « Si vous pensez à… ».
  final String hypothesis;

  /// « …et que vous trouvez… ».
  final String newInfo;

  /// Libellé du bas de l'échelle (−2) et du haut (+2) ; vide = valeur par
  /// défaut de l'interface.
  final String lowLabel;
  final String highLabel;

  /// Nombre d'experts du panel pour chaque niveau, de −2 à +2.
  final List<int> panel;

  int get panelTotal => panel.fold(0, (a, b) => a + b);

  /// Plus grand effectif du panel.
  int get panelMax => panel.fold(0, (a, b) => a > b ? a : b);

  @override
  QuestionKind get kind => QuestionKind.tcs;

  @override
  List<QuestionIssue> get issues => [
    if (hypothesis.trim().isEmpty) QuestionIssue.tcsHypothesis,
    if (newInfo.trim().isEmpty) QuestionIssue.tcsNewInfo,
    if (panelTotal == 0) QuestionIssue.tcsPanel,
  ];

  TcsQuestion copyWith({
    String? hypothesis,
    String? newInfo,
    String? lowLabel,
    String? highLabel,
    List<int>? panel,
  }) => TcsQuestion(
    body: body,
    images: images,
    explanation: explanation,
    points: points,
    hypothesis: hypothesis ?? this.hypothesis,
    newInfo: newInfo ?? this.newInfo,
    lowLabel: lowLabel ?? this.lowLabel,
    highLabel: highLabel ?? this.highLabel,
    panel: panel ?? this.panel,
  );

  @override
  TcsQuestion withCommon({
    String? body,
    List<String>? images,
    String? explanation,
    double? points,
  }) => TcsQuestion(
    body: body ?? this.body,
    images: images ?? this.images,
    explanation: explanation ?? this.explanation,
    points: points ?? this.points,
    hypothesis: hypothesis,
    newInfo: newInfo,
    lowLabel: lowLabel,
    highLabel: highLabel,
    panel: panel,
  );

  @override
  TcsQuestion remapMedia(String Function(String name) rename) =>
      withCommon(images: [for (final i in images) rename(i)]);

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'body': body,
    if (images.isNotEmpty) 'images': images,
    'explanation': explanation,
    'points': points,
    'hypothesis': hypothesis,
    'newInfo': newInfo,
    if (lowLabel.isNotEmpty) 'lowLabel': lowLabel,
    if (highLabel.isNotEmpty) 'highLabel': highLabel,
    'panel': panel,
  };
}

class QzpQuestion extends Question {
  const QzpQuestion({
    super.body,
    super.images,
    super.explanation,
    super.points,
    this.image = '',
    this.zones = const [],
  });

  /// Image sur laquelle on pointe (nom de fichier), vide tant qu'on n'en a
  /// pas choisi.
  final String image;
  final List<Zone> zones;

  @override
  QuestionKind get kind => QuestionKind.qzp;

  @override
  Set<String> get mediaNames => {...images, if (image.isNotEmpty) image};

  @override
  List<QuestionIssue> get issues => [
    if (body.trim().isEmpty) QuestionIssue.emptyBody,
    if (image.isEmpty) QuestionIssue.qzpImage,
    if (zones.isEmpty) QuestionIssue.qzpZone,
  ];

  QzpQuestion copyWith({String? image, List<Zone>? zones}) => QzpQuestion(
    body: body,
    images: images,
    explanation: explanation,
    points: points,
    image: image ?? this.image,
    zones: zones ?? this.zones,
  );

  @override
  QzpQuestion withCommon({
    String? body,
    List<String>? images,
    String? explanation,
    double? points,
  }) => QzpQuestion(
    body: body ?? this.body,
    images: images ?? this.images,
    explanation: explanation ?? this.explanation,
    points: points ?? this.points,
    image: image,
    zones: zones,
  );

  @override
  QzpQuestion remapMedia(String Function(String name) rename) => QzpQuestion(
    body: body,
    images: [for (final i in images) rename(i)],
    explanation: explanation,
    points: points,
    image: image.isEmpty ? '' : rename(image),
    zones: zones,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'body': body,
    if (images.isNotEmpty) 'images': images,
    'explanation': explanation,
    'points': points,
    if (image.isNotEmpty) 'image': image,
    'zones': [for (final z in zones) z.toJson()],
  };
}
