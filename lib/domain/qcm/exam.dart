/// Cas cliniques et choix de ce qu'on pose lors d'un passage.
library;

import 'dart:math';

import 'grading.dart';
import 'question.dart';

/// Genre d'un cas : plusieurs questions qui partagent un contexte.
enum CaseGenre {
  /// Dossier qui évolue : chaque question apporte la suite de l'histoire.
  /// Jamais coupé ni mélangé ; une question ne se rouvre plus quand la
  /// suivante a été vue.
  progressive,

  /// Cas court, décisions clés (« key feature problem »).
  kfp,

  /// Lecture critique d'article : un article, plusieurs questions.
  lca,
}

CaseGenre caseGenreOf(Object? name) {
  for (final g in CaseGenre.values) {
    if (g.name == name) return g;
  }
  throw FormatException('genre de cas inconnu : $name');
}

/// Un cas clinique tel qu'il est écrit.
class CaseInfo {
  const CaseInfo({
    required this.genre,
    this.title = '',
    this.context = '',
    this.articleText = '',
    this.articleFile = '',
  });

  factory CaseInfo.fromJson(Object? j) {
    if (j is! Map) throw const FormatException('cas attendu');
    String s(String key, int max) {
      final v = j[key];
      if (v == null) return '';
      if (v is! String) throw FormatException('texte attendu ($key)');
      return v.length > max ? v.substring(0, max) : v;
    }

    return CaseInfo(
      genre: caseGenreOf(j['genre']),
      title: s('title', 300),
      context: s('context', 40000),
      articleText: s('articleText', 400000),
      articleFile: s('articleFile', 80),
    );
  }

  final CaseGenre genre;

  /// Titre ; vide = nom donné par l'interface d'après le genre.
  final String title;

  /// Contexte commun à toutes les questions du cas.
  final String context;

  /// Article collé en texte (cas LCA).
  final String articleText;

  /// Article joint en PDF (nom dans le dossier de médias).
  final String articleFile;

  bool get hasArticle =>
      articleText.trim().isNotEmpty || articleFile.isNotEmpty;

  CaseInfo copyWith({
    CaseGenre? genre,
    String? title,
    String? context,
    String? articleText,
    String? articleFile,
  }) => CaseInfo(
    genre: genre ?? this.genre,
    title: title ?? this.title,
    context: context ?? this.context,
    articleText: articleText ?? this.articleText,
    articleFile: articleFile ?? this.articleFile,
  );

  Map<String, Object?> toJson() => {
    'genre': genre.name,
    if (title.isNotEmpty) 'title': title,
    'context': context,
    if (articleText.isNotEmpty) 'articleText': articleText,
    if (articleFile.isNotEmpty) 'articleFile': articleFile,
  };

  @override
  bool operator ==(Object other) =>
      other is CaseInfo &&
      other.genre == genre &&
      other.title == title &&
      other.context == context &&
      other.articleText == articleText &&
      other.articleFile == articleFile;

  @override
  int get hashCode =>
      Object.hash(genre, title, context, articleText, articleFile);
}

/// Quand la correction est montrée.
enum Correction { end, each }

/// Réglages d'un passage.
class PassageSettings {
  const PassageSettings({
    this.part = false,
    this.partCount = 10,
    this.random = false,
    this.correction = Correction.end,
    this.backAllowed = false,
    this.timerMinutes,
    this.scoring = Scoring.edn,
    this.shuffleProps = true,
  });

  factory PassageSettings.fromJson(Object? j) {
    if (j is! Map) return const PassageSettings();
    int? timer() {
      final v = j['timer'];
      return v is int && v > 0 && v <= 24 * 60 ? v : null;
    }

    final count = j['partCount'];
    return PassageSettings(
      part: j['part'] == true,
      partCount: count is int && count > 0 ? count : 10,
      random: j['random'] == true,
      correction: j['correction'] == 'each' ? Correction.each : Correction.end,
      backAllowed: j['back'] == true,
      timerMinutes: timer(),
      scoring: j['scoring'] == 'points' ? Scoring.points : Scoring.edn,
      shuffleProps: j['shuffle'] != false,
    );
  }

  /// Ne passer qu'une partie des questions.
  final bool part;
  final int partCount;

  /// Tirer au hasard (et dans le désordre) plutôt que les premières.
  final bool random;

  final Correction correction;

  /// Rouvrir une question déjà validée.
  final bool backAllowed;

  /// Durée totale en minutes, ou null (pas de limite).
  final int? timerMinutes;

  final Scoring scoring;

  /// Nouvel ordre des propositions à chaque passage.
  final bool shuffleProps;

  PassageSettings copyWith({
    bool? part,
    int? partCount,
    bool? random,
    Correction? correction,
    bool? backAllowed,
    Object? timerMinutes = _keep,
    Scoring? scoring,
    bool? shuffleProps,
  }) => PassageSettings(
    part: part ?? this.part,
    partCount: partCount ?? this.partCount,
    random: random ?? this.random,
    correction: correction ?? this.correction,
    backAllowed: backAllowed ?? this.backAllowed,
    timerMinutes: identical(timerMinutes, _keep)
        ? this.timerMinutes
        : timerMinutes as int?,
    scoring: scoring ?? this.scoring,
    shuffleProps: shuffleProps ?? this.shuffleProps,
  );

  Map<String, Object?> toJson() => {
    'part': part,
    'partCount': partCount,
    'random': random,
    'correction': correction.name,
    'back': backAllowed,
    if (timerMinutes != null) 'timer': timerMinutes,
    'scoring': scoring.name,
    'shuffle': shuffleProps,
  };
}

const Object _keep = Object();

/// Une question prise dans une épreuve, avec d'où elle vient.
class SourceQuestion {
  const SourceQuestion({
    required this.question,
    this.examId,
    this.questionId,
    this.subjectId,
    this.topicId,
  });

  final Question question;
  final int? examId;
  final int? questionId;
  final int? subjectId;
  final int? topicId;
}

/// Une question isolée ([info] nul) ou un cas avec ses questions.
class SourceUnit {
  const SourceUnit(this.questions, {this.info});

  final CaseInfo? info;
  final List<SourceQuestion> questions;
}

/// Une question prête à être posée.
class PlannedQuestion {
  const PlannedQuestion({
    required this.question,
    this.info,
    this.caseGroup = -1,
    this.examId,
    this.questionId,
    this.subjectId,
    this.topicId,
    this.order = const [],
  });

  /// Question sans propositions vides.
  final Question question;
  final CaseInfo? info;

  /// Numéro du cas dans ce passage (−1 : question isolée) : deux questions
  /// du même cas ont le même.
  final int caseGroup;
  final int? examId;
  final int? questionId;
  final int? subjectId;
  final int? topicId;

  /// Ordre d'affichage des propositions (positions dans
  /// `question.propositions`) ; vide pour les autres genres.
  final List<int> order;
}

/// Choisit et ordonne les questions d'un passage.
///
/// Seules les questions prêtes sont posées. Un cas n'est jamais coupé : en
/// mode « une partie », on ajoute des cas entiers jusqu'à atteindre le nombre
/// demandé (qui peut donc être un peu dépassé).
List<PlannedQuestion> planSession(
  List<SourceUnit> units,
  PassageSettings settings,
  Random random,
) {
  var pool = <SourceUnit>[];
  for (final u in units) {
    final ready = [
      for (final q in u.questions)
        if (q.question.isReady) q,
    ];
    if (ready.isNotEmpty) pool.add(SourceUnit(ready, info: u.info));
  }
  if (settings.part) {
    if (settings.random) pool = [...pool]..shuffle(random);
    final chosen = <SourceUnit>[];
    var n = 0;
    for (final u in pool) {
      if (n >= settings.partCount) break;
      chosen.add(u);
      n += u.questions.length;
    }
    pool = chosen;
  }
  final out = <PlannedQuestion>[];
  var group = 0;
  for (final u in pool) {
    final g = u.info == null ? -1 : group++;
    for (final s in u.questions) {
      var q = s.question;
      var order = const <int>[];
      if (q is ChoiceQuestion) {
        q = q.cleaned();
        final n = q.propositions.length;
        order = List<int>.generate(n, (i) => i);
        if (settings.shuffleProps) order.shuffle(random);
      }
      out.add(
        PlannedQuestion(
          question: q,
          info: u.info,
          caseGroup: g,
          examId: s.examId,
          questionId: s.questionId,
          subjectId: s.subjectId,
          topicId: s.topicId,
          order: order,
        ),
      );
    }
  }
  return out;
}
