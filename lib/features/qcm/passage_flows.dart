import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/qcm_models.dart';
import '../../data/qcm_repository.dart';
import '../../domain/qcm/exam.dart';
import '../../domain/qcm/grading.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import 'passage_page.dart';
import 'passage_setup.dart';

/// Générateur de hasard des passages ; les tests peuvent le remplacer pour
/// des tirages prévisibles.
Random Function() passageRandom = Random.new;

/// Réglages puis passage d'une épreuve. Renvoie vrai si un passage a eu lieu
/// (faux si l'étudiant a annulé les réglages).
Future<bool> startExamPassage(
  BuildContext context,
  ExamSummary summary, {
  bool practiceMode = false,
}) => _launch(
  context,
  title: summary.exam.title,
  available: summary.ready,
  units: (repo) => repo.sourceUnits([summary.exam.id]),
  examId: summary.exam.id,
  examTotal: summary.ready,
  practiceMode: practiceMode,
  handwritten: !summary.exam.imported,
);

/// « Prochaine épreuve » : la première jamais passée, sinon la plus ancienne.
/// [except] écarte l'épreuve qu'on vient de passer (« Une autre épreuve »).
Future<bool> startNextExam(BuildContext context, {int? except}) async {
  final repo = context.read<QcmRepository>();
  final next = repo.nextExam(except: except);
  if (next == null) {
    showInfo(
      context,
      except == null ? TxQcm.nothingToPass : TxQcm.copyNoAnother,
    );
    return false;
  }
  return startExamPassage(context, next);
}

/// Entraînement : des questions tirées dans [chosen] (une ou plusieurs
/// épreuves). Renvoie vrai si un passage a eu lieu.
Future<bool> startPractice(
  BuildContext context,
  List<ExamSummary> chosen,
) async {
  final ready = [
    for (final s in chosen)
      if (s.ready > 0) s,
  ];
  if (ready.isEmpty) {
    showInfo(context, TxQcm.nothingToCompose);
    return false;
  }
  if (ready.length == 1) {
    return startExamPassage(context, ready.first, practiceMode: true);
  }
  return _launch(
    context,
    title: TxQcm.practiceTitle(ready.length),
    available: ready.fold<int>(0, (a, s) => a + s.ready),
    units: (repo) => repo.sourceUnits([for (final s in ready) s.exam.id]),
    practiceMode: true,
    handwritten: ready.every((s) => !s.exam.imported),
  );
}

/// Repasse les questions d'une copie : toutes, ou seulement celles à
/// reprendre (un cas n'est jamais coupé : il revient en entier).
Future<bool> replayAttempt(
  BuildContext context,
  AttemptDetail detail, {
  required bool onlyMissed,
}) async {
  final units = unitsOfAttempt(detail.answers, onlyMissed: onlyMissed);
  final count = units.fold<int>(0, (a, u) => a + u.questions.length);
  if (count == 0) {
    showInfo(context, TxQcm.copyNothingToRedo);
    return false;
  }
  final a = detail.attempt;
  return _launch(
    context,
    title: a.title,
    available: count,
    units: (_) => units,
    examId: a.examId,
    examTotal: a.examTotal,
    practiceMode: a.practice || onlyMissed,
    handwritten: a.handwritten,
  );
}

/// Questions d'une copie, regroupées en cas comme au passage.
List<SourceUnit> unitsOfAttempt(
  List<AnswerRow> answers, {
  required bool onlyMissed,
}) {
  bool missed(AnswerRow a) => a.verdict != Verdict.right;
  SourceQuestion source(AnswerRow a) => SourceQuestion(
    question: a.question,
    examId: a.examId,
    subjectId: a.subjectId,
    topicId: a.topicId,
  );

  final out = <SourceUnit>[];
  var i = 0;
  while (i < answers.length) {
    final a = answers[i];
    final info = a.info;
    if (info == null || a.caseGroup < 0) {
      if (!onlyMissed || missed(a)) out.add(SourceUnit([source(a)]));
      i++;
      continue;
    }
    // Un cas : toutes les questions consécutives du même groupe.
    var j = i;
    final group = <AnswerRow>[];
    while (j < answers.length &&
        answers[j].caseGroup == a.caseGroup &&
        answers[j].info != null) {
      group.add(answers[j]);
      j++;
    }
    if (!onlyMissed || group.any(missed)) {
      out.add(SourceUnit([for (final g in group) source(g)], info: info));
    }
    i = j;
  }
  return out;
}

Future<bool> _launch(
  BuildContext context, {
  required String title,
  required int available,
  required List<SourceUnit> Function(QcmRepository repo) units,
  required bool handwritten,
  int? examId,
  int? examTotal,
  bool practiceMode = false,
}) async {
  final repo = context.read<QcmRepository>();
  final navigator = Navigator.of(context);
  final settings = await showPassageSetup(
    context,
    title: title,
    available: available,
    initial: repo.passageSettings(),
  );
  if (settings == null || !context.mounted) return false;
  try {
    repo.setPassageSettings(settings);
  } on Object catch (e) {
    showError(context, e);
    return false;
  }
  final plan = planSession(units(repo), settings, passageRandom());
  if (plan.isEmpty) {
    showInfo(context, TxQcm.nothingToCompose);
    return false;
  }
  // Une partie d'une épreuve est un entraînement, pas un passage complet.
  final practice = practiceMode || settings.part;
  await navigator.push<void>(
    MaterialPageRoute(
      builder: (_) => PassagePage(
        plan: plan,
        settings: settings,
        title: title,
        examId: examId,
        practice: practice,
        handwritten: handwritten,
        examTotal: examTotal,
      ),
    ),
  );
  return true;
}
