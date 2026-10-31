import 'dart:math';

import 'package:carabin/app_session.dart';
import 'package:carabin/data/errors.dart';
import 'package:carabin/data/qcm_models.dart';
import 'package:carabin/data/qcm_repository.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/grading.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_session.dart';

ChoiceQuestion q(String body, {bool ready = true}) => ChoiceQuestion(
  body: body,
  propositions: [
    Proposition(text: 'A', correct: ready),
    const Proposition(text: 'B'),
  ],
);

List<String> bodies(ExamContent c) => [
  for (final u in c.units)
    switch (u) {
      SingleUnit(:final question) => question.question.body,
      CaseUnit(:final kase, :final questions) =>
        '[${kase.info.genre.name}: ${questions.map((x) => x.question.body).join(',')}]',
    },
];

AttemptDraft draft(
  QcmRepository repo, {
  required String title,
  int? examId,
  required List<AnswerDraft> answers,
  DateTime? at,
  bool practice = false,
  Scoring scoring = Scoring.edn,
  int? examTotal,
}) => AttemptDraft(
  title: title,
  examId: examId,
  practice: practice,
  settings: PassageSettings(scoring: scoring),
  startedAt: at ?? DateTime.utc(2026, 10, 1),
  duration: const Duration(minutes: 12),
  examTotal: examTotal,
  answers: answers,
);

AnswerDraft ans(
  Question question,
  Answer? answer, {
  Scoring scoring = Scoring.edn,
  int? subjectId,
  int? topicId,
  int? examId,
}) => AnswerDraft(
  question: question,
  answer: answer,
  grade: gradeQuestion(question, answer, scoring),
  subjectId: subjectId,
  topicId: topicId,
  examId: examId,
);

void main() {
  late Session s;
  late QcmRepository repo;

  setUp(() {
    s = openTestSession();
    repo = s.qcm;
  });

  tearDown(() => s.dispose());

  group('épreuves', () {
    test('création, titre nettoyé, refus du titre vide', () {
      final e = repo.createExam('  Annale   cardio  ');
      expect(e.title, 'Annale cardio');
      expect(e.guid, hasLength(32));
      expect(() => repo.createExam('   '), throwsA(isA<EmptyNameError>()));
      expect(repo.createExam('x' * 300).title.length, 200);
    });

    test('identifiants uniques', () {
      final a = repo.createExam('A');
      final b = repo.createExam('B');
      expect(a.guid, isNot(b.guid));
    });

    test('renommer, matière, items, annales', () {
      final e = repo.createExam('Série 1');
      repo.renameExam(e.id, 'Série 2');
      repo.setExamItems(e.id, ' 12, 224 ');
      final y = s.courses.createYear('A');
      final sem = s.courses.createSemester(y.id, 'S1');
      final m = s.courses.createSubject(sem.id, 'Cardio', color: 0xFF000000);
      repo.setExamSubject([e.id], m.id);
      var r = repo.exam(e.id);
      expect(r.title, 'Série 2');
      expect(r.items, '12, 224');
      expect(r.subjectId, m.id);
      expect(r.isPastPaper, isFalse);
      repo.setPastPaper([e.id], true);
      expect(repo.exam(e.id).isPastPaper, isTrue);
      repo.setPastPaper([e.id], false);
      repo.renameExam(e.id, 'Annale 2024');
      r = repo.exam(e.id);
      expect(r.isPastPaper, isTrue); // le titre le dit
      expect(() => repo.exam(9999), throwsA(isA<NotFoundError>()));
    });

    test('suppression : les copies restent, détachées', () {
      final e = repo.createExam('E');
      final id = repo.addQuestion(e.id, q('1'));
      final question = repo.question(id).question;
      final attempt = repo.saveAttempt(
        draft(
          repo,
          title: 'E',
          examId: e.id,
          answers: [
            ans(question, const ChoiceAnswer({0})),
          ],
        ),
      );
      repo.deleteExams([e.id]);
      expect(repo.attemptRow(attempt).examId, isNull);
      expect(repo.attempt(attempt).answers, hasLength(1));
      expect(repo.exams(), isEmpty);
      expect(
        s.db.select('SELECT * FROM exam_questions'),
        isEmpty,
      ); // contenu supprimé en cascade
    });

    test('résumé : questions, prêtes, à finir', () {
      final e = repo.createExam('E');
      repo.addQuestion(e.id, q('1'));
      repo.addQuestion(e.id, q('2', ready: false));
      repo.addQuestion(e.id, const QrocQuestion());
      final sum = repo.exams().single;
      expect(sum.questions, 3);
      expect(sum.ready, 1);
      expect(sum.unfinished, 2);
      expect(sum.attempts, 0);
      expect(sum.lastNote, isNull);
    });
  });

  group('questions', () {
    test('ajout à la suite, lecture dans l\'ordre', () {
      final e = repo.createExam('E');
      for (final b in ['1', '2', '3']) {
        repo.addQuestion(e.id, q(b));
      }
      expect(bodies(repo.content(e.id)), ['1', '2', '3']);
    });

    test('modification met à jour l\'état « prête »', () {
      final e = repo.createExam('E');
      final id = repo.addQuestion(e.id, q('1', ready: false));
      expect(repo.question(id).ready, isFalse);
      repo.updateQuestion(id, q('1 bis'));
      final r = repo.question(id);
      expect(r.ready, isTrue);
      expect(r.question.body, '1 bis');
    });

    test('changement de genre à l\'enregistrement', () {
      final e = repo.createExam('E');
      final id = repo.addQuestion(e.id, q('1'));
      repo.updateQuestion(id, const QrocQuestion(body: 'Q', model: 'M'));
      expect(repo.question(id).question, isA<QrocQuestion>());
    });

    test('monter, descendre, limites', () {
      final e = repo.createExam('E');
      final ids = [
        for (final b in ['1', '2', '3']) repo.addQuestion(e.id, q(b)),
      ];
      repo.moveQuestion(ids[2], -1);
      expect(bodies(repo.content(e.id)), ['1', '3', '2']);
      repo.moveQuestion(ids[0], -1); // déjà en haut
      repo.moveQuestion(ids[1], 1); // déjà en bas
      expect(bodies(repo.content(e.id)), ['1', '3', '2']);
      repo.moveQuestion(ids[0], 1);
      expect(bodies(repo.content(e.id)), ['3', '1', '2']);
    });

    test('dupliquer juste après', () {
      final e = repo.createExam('E');
      final ids = [
        for (final b in ['1', '2']) repo.addQuestion(e.id, q(b)),
      ];
      repo.duplicateQuestion(ids[0]);
      expect(bodies(repo.content(e.id)), ['1', '1', '2']);
    });

    test('supprimer renumérote', () {
      final e = repo.createExam('E');
      final ids = [
        for (final b in ['1', '2', '3']) repo.addQuestion(e.id, q(b)),
      ];
      repo.deleteQuestion(ids[1]);
      expect(bodies(repo.content(e.id)), ['1', '3']);
      final positions = [
        for (final r in s.db.select(
          'SELECT position FROM exam_questions ORDER BY position',
        ))
          r['position'],
      ];
      expect(positions, [0, 1]);
    });
  });

  group('cas', () {
    test('un cas et ses questions gardent leur place et leur ordre', () {
      final e = repo.createExam('E');
      repo.addQuestion(e.id, q('1'));
      final c = repo.addCase(
        e.id,
        const CaseInfo(genre: CaseGenre.progressive),
      );
      repo.addQuestion(e.id, q('c1'), caseId: c.id);
      repo.addQuestion(e.id, q('c2'), caseId: c.id);
      repo.addQuestion(e.id, q('2'));
      expect(bodies(repo.content(e.id)), ['1', '[progressive: c1,c2]', '2']);
    });

    test('déplacer un cas entier', () {
      final e = repo.createExam('E');
      final c = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      repo.addQuestion(e.id, q('c1'), caseId: c.id);
      repo.addQuestion(e.id, q('1'));
      repo.moveCase(c.id, 1);
      expect(bodies(repo.content(e.id)), ['1', '[kfp: c1]']);
      repo.moveCase(c.id, -1);
      expect(bodies(repo.content(e.id)), ['[kfp: c1]', '1']);
    });

    test('monter une question dans son cas', () {
      final e = repo.createExam('E');
      final c = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      repo.addQuestion(e.id, q('a'), caseId: c.id);
      final b = repo.addQuestion(e.id, q('b'), caseId: c.id);
      repo.moveQuestion(b, -1);
      expect(bodies(repo.content(e.id)), ['[kfp: b,a]']);
    });

    test('ranger une question dans un cas, puis la ressortir', () {
      final e = repo.createExam('E');
      final one = repo.addQuestion(e.id, q('1'));
      final c = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      repo.addQuestion(e.id, q('c1'), caseId: c.id);
      repo.addQuestion(e.id, q('2'));
      repo.setQuestionCase(one, c.id);
      expect(bodies(repo.content(e.id)), ['[kfp: c1,1]', '2']);
      repo.setQuestionCase(one, null);
      // ressortie juste après son ancien cas
      expect(bodies(repo.content(e.id)), ['[kfp: c1]', '1', '2']);
      expect(repo.question(one).caseId, isNull);
    });

    test('changer de cas', () {
      final e = repo.createExam('E');
      final c1 = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      final c2 = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.lca));
      final a = repo.addQuestion(e.id, q('a'), caseId: c1.id);
      repo.addQuestion(e.id, q('b'), caseId: c1.id);
      repo.setQuestionCase(a, c2.id);
      expect(bodies(repo.content(e.id)), ['[kfp: b]', '[lca: a]']);
    });

    test('un cas d\'une autre épreuve est refusé', () {
      final e1 = repo.createExam('E1');
      final e2 = repo.createExam('E2');
      final c = repo.addCase(e1.id, const CaseInfo(genre: CaseGenre.kfp));
      expect(
        () => repo.addQuestion(e2.id, q('x'), caseId: c.id),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('modifier le cas et son genre', () {
      final e = repo.createExam('E');
      final c = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      repo.updateCase(
        c.id,
        const CaseInfo(
          genre: CaseGenre.lca,
          title: 'Article X',
          context: 'ctx',
          articleText: 'texte',
          articleFile: 'abcdef0123.pdf',
        ),
      );
      final back = repo.caseRow(c.id).info;
      expect(back.genre, CaseGenre.lca);
      expect(back.title, 'Article X');
      expect(back.articleFile, 'abcdef0123.pdf');
    });

    test('supprimer un cas supprime ses questions', () {
      final e = repo.createExam('E');
      repo.addQuestion(e.id, q('1'));
      final c = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      repo.addQuestion(e.id, q('c1'), caseId: c.id);
      repo.deleteCase(c.id);
      expect(bodies(repo.content(e.id)), ['1']);
      expect(s.db.select('SELECT * FROM exam_questions'), hasLength(1));
    });

    test('mélanger garde les cas entiers', () {
      final e = repo.createExam('E');
      for (var i = 0; i < 6; i++) {
        repo.addQuestion(e.id, q('s$i'));
      }
      final c = repo.addCase(
        e.id,
        const CaseInfo(genre: CaseGenre.progressive),
      );
      repo.addQuestion(e.id, q('c1'), caseId: c.id);
      repo.addQuestion(e.id, q('c2'), caseId: c.id);
      repo.shuffleUnits(e.id, Random(5));
      final list = bodies(repo.content(e.id));
      expect(list, hasLength(7));
      expect(list, contains('[progressive: c1,c2]'));
      expect(list.where((b) => b.startsWith('s')).toSet(), hasLength(6));
    });

    test('cas vide : présent dans l\'épreuve', () {
      final e = repo.createExam('E');
      repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
      expect(bodies(repo.content(e.id)), ['[kfp: ]']);
    });
  });

  test('dupliquer une épreuve', () {
    final e = repo.createExam('E', pastPaper: true);
    repo.setExamItems(e.id, '3');
    repo.addQuestion(e.id, q('1'));
    final c = repo.addCase(
      e.id,
      const CaseInfo(genre: CaseGenre.kfp, context: 'ctx'),
    );
    repo.addQuestion(e.id, q('c1'), caseId: c.id);
    final copy = repo.duplicateExam(e.id, title: 'E (copie)');
    expect(copy.id, isNot(e.id));
    expect(copy.guid, isNot(e.guid));
    expect(copy.title, 'E (copie)');
    expect(copy.pastPaper, isTrue);
    expect(copy.items, '3');
    expect(bodies(repo.content(copy.id)), ['1', '[kfp: c1]']);
    // la copie est indépendante
    repo.addQuestion(copy.id, q('2'));
    expect(bodies(repo.content(e.id)), ['1', '[kfp: c1]']);
  });

  group('copies', () {
    test('enregistrement et relecture', () {
      final e = repo.createExam('E');
      final right = q('1');
      final wrong = q('2');
      final id = repo.saveAttempt(
        draft(
          repo,
          title: 'E',
          examId: e.id,
          examTotal: 2,
          answers: [
            ans(right, const ChoiceAnswer({0}), examId: e.id),
            AnswerDraft(
              question: wrong,
              info: const CaseInfo(genre: CaseGenre.kfp, context: 'ctx'),
              caseGroup: 0,
              order: const [1, 0],
              answer: const ChoiceAnswer({1}),
              grade: gradeQuestion(wrong, const ChoiceAnswer({1}), Scoring.edn),
              doubt: true,
            ),
            ans(q('3'), null),
          ],
        ),
      );
      final d = repo.attempt(id);
      expect(d.attempt.title, 'E');
      expect(d.attempt.examId, e.id);
      expect(d.attempt.questionCount, 3);
      expect(d.attempt.score, 1);
      expect(d.attempt.max, 3);
      expect(d.attempt.note, closeTo(20 / 3, 1e-6));
      expect(d.attempt.duration, const Duration(minutes: 12));
      expect(d.attempt.startedAt.toUtc(), DateTime.utc(2026, 10, 1));
      expect(d.attempt.part, closeTo(1, 1e-9));
      expect(d.answers.map((a) => a.verdict), [
        Verdict.right,
        Verdict.wrong,
        Verdict.skipped,
      ]);
      expect(d.answers[1].info?.context, 'ctx');
      expect(d.answers[1].caseGroup, 0);
      expect(d.answers[1].order, [1, 0]);
      expect(d.answers[1].doubt, isTrue);
      expect((d.answers[1].answer as ChoiceAnswer).ticked, {1});
      expect(d.answers[2].answer, isNull);
      expect(d.totals.right, 1);
      expect(d.totals.skipped, 1);
    });

    test('la copie ne dépend plus de l\'épreuve', () {
      final e = repo.createExam('E');
      final id = repo.addQuestion(e.id, q('1'));
      final attempt = repo.saveAttempt(
        draft(
          repo,
          title: 'E',
          examId: e.id,
          answers: [
            ans(repo.question(id).question, const ChoiceAnswer({0})),
          ],
        ),
      );
      repo.updateQuestion(id, q('modifiée'));
      repo.deleteQuestion(id);
      expect(repo.attempt(attempt).answers.single.question.body, '1');
    });

    test('la carte d\'épreuve montre passages et dernière note', () {
      final e = repo.createExam('E');
      final question = q('1');
      repo.saveAttempt(
        draft(
          repo,
          title: 'E',
          examId: e.id,
          at: DateTime.utc(2026, 10, 1),
          answers: [
            ans(question, const ChoiceAnswer({1})),
          ],
        ),
      );
      repo.saveAttempt(
        draft(
          repo,
          title: 'E',
          examId: e.id,
          at: DateTime.utc(2026, 10, 5),
          answers: [
            ans(question, const ChoiceAnswer({0})),
          ],
        ),
      );
      final sum = repo.exams().single;
      expect(sum.attempts, 2);
      expect(sum.lastNote, 20);
    });

    test('liste : épreuves et entraînements séparés, récent d\'abord', () {
      final question = q('1');
      repo.saveAttempt(
        draft(
          repo,
          title: 'ancien',
          at: DateTime.utc(2026, 1, 1),
          answers: [ans(question, null)],
        ),
      );
      repo.saveAttempt(
        draft(
          repo,
          title: 'récent',
          practice: true,
          at: DateTime.utc(2026, 2, 1),
          answers: [ans(question, null)],
        ),
      );
      expect(repo.attempts().map((a) => a.title), ['récent', 'ancien']);
      expect(repo.attempts(practice: true).map((a) => a.title), ['récent']);
      expect(repo.attempts(practice: false).map((a) => a.title), ['ancien']);
    });

    test('suppression', () {
      final id = repo.saveAttempt(
        draft(repo, title: 'x', answers: [ans(q('1'), null)]),
      );
      repo.deleteAttempt(id);
      expect(repo.attempts(), isEmpty);
      expect(s.db.select('SELECT * FROM attempt_answers'), isEmpty);
    });

    test('auto-évaluation d\'un QROC', () {
      const free = QrocQuestion(body: 'Q', model: 'M');
      final id = repo.saveAttempt(
        draft(
          repo,
          title: 'x',
          answers: [
            ans(free, const TextAnswer('ma réponse')),
            ans(q('2'), const ChoiceAnswer({0})),
          ],
        ),
      );
      var d = repo.attempt(id);
      expect(d.answers[0].verdict, Verdict.pending);
      expect(d.attempt.score, 1);
      repo.setSelfScore(d.answers[0].id, 0.5);
      d = repo.attempt(id);
      expect(d.answers[0].verdict, Verdict.partial);
      expect(d.answers[0].score, 0.5);
      expect(d.attempt.score, 1.5);
      expect((d.answers[0].answer as TextAnswer).self, 0.5);
      repo.setSelfScore(d.answers[0].id, 1);
      expect(repo.attempt(id).attempt.score, 2);
      repo.setSelfScore(d.answers[0].id, null);
      expect(repo.attempt(id).answers[0].verdict, Verdict.pending);
      expect(repo.attempt(id).attempt.score, 1);
      expect(
        () => repo.setSelfScore(d.answers[0].id, 0.3),
        throwsArgumentError,
      );
    });

    test(
      'auto-évaluation sans effet sur une question corrigée par l\'appli',
      () {
        const auto = QrocQuestion(
          body: 'Q',
          elements: [ExpectedElement(pattern: 'foie')],
        );
        final id = repo.saveAttempt(
          draft(
            repo,
            title: 'x',
            answers: [ans(auto, const TextAnswer('foie'))],
          ),
        );
        final a = repo.attempt(id).answers.single;
        repo.setSelfScore(a.id, 0);
        expect(repo.attempt(id).answers.single.verdict, Verdict.right);
      },
    );

    test('auto-évaluation d\'une question passée : sans effet', () {
      const free = QrocQuestion(body: 'Q', model: 'M');
      final id = repo.saveAttempt(
        draft(repo, title: 'x', answers: [ans(free, null)]),
      );
      repo.setSelfScore(repo.attempt(id).answers.single.id, 1);
      expect(repo.attempt(id).answers.single.verdict, Verdict.skipped);
    });
  });

  test(
    '« Où je chute » : par matière et par thème, du plus bas au plus haut',
    () {
      final y = s.courses.createYear('A');
      final sem = s.courses.createSemester(y.id, 'S1');
      final cardio = s.courses.createSubject(
        sem.id,
        'Cardio',
        color: 0xFF000000,
      );
      final pneumo = s.courses.createSubject(
        sem.id,
        'Pneumo',
        color: 0xFF000000,
      );
      final topic = s.courses.createTopic(cardio.id, 'ECG');
      final question = q('1');
      repo.saveAttempt(
        draft(
          repo,
          title: 'a',
          answers: [
            ans(
              question,
              const ChoiceAnswer({0}),
              subjectId: cardio.id,
              topicId: topic.id,
            ),
            ans(
              question,
              const ChoiceAnswer({1}),
              subjectId: cardio.id,
              topicId: topic.id,
            ),
            ans(question, const ChoiceAnswer({0}), subjectId: pneumo.id),
            ans(question, const ChoiceAnswer({0})),
            ans(question, const ChoiceAnswer({1})),
          ],
        ),
      );
      final bySubject = repo.weakSpots(byTopic: false);
      expect(bySubject.map((w) => w.id), [null, cardio.id, pneumo.id]);
      final cardioSpot = bySubject[1];
      expect(cardioSpot.total, 2);
      expect(cardioSpot.right, 1);
      expect(cardioSpot.ratio, 0.5);
      expect(bySubject.first.total, 2); // non rangé
      final byTopic = repo.weakSpots(byTopic: true);
      expect(byTopic.firstWhere((w) => w.id == topic.id).total, 2);
      // entraînements seulement : rien
      expect(repo.weakSpots(byTopic: false, practice: true), isEmpty);
      expect(repo.weakSpots(byTopic: false, practice: false), hasLength(3));
    },
  );

  group('prochaine épreuve', () {
    test('première jamais passée, sinon la plus ancienne', () {
      expect(repo.nextExam(), isNull);
      final a = repo.createExam('A');
      final b = repo.createExam('B');
      final empty = repo.createExam('Vide');
      repo.addQuestion(a.id, q('1'));
      repo.addQuestion(b.id, q('1'));
      repo.addQuestion(empty.id, q('x', ready: false));
      expect(repo.nextExam()!.exam.id, a.id);
      final question = q('1');
      repo.saveAttempt(
        draft(
          repo,
          title: 'A',
          examId: a.id,
          at: DateTime.utc(2026, 5, 1),
          answers: [ans(question, null)],
        ),
      );
      expect(repo.nextExam()!.exam.id, b.id);
      repo.saveAttempt(
        draft(
          repo,
          title: 'B',
          examId: b.id,
          at: DateTime.utc(2026, 6, 1),
          answers: [ans(question, null)],
        ),
      );
      expect(repo.nextExam()!.exam.id, a.id); // passée il y a le plus longtemps
    });
  });

  test('blocs à poser : matière de l\'épreuve ou du poly', () async {
    final y = s.courses.createYear('A');
    final sem = s.courses.createSemester(y.id, 'S1');
    final m = s.courses.createSubject(sem.id, 'Cardio', color: 0xFF000000);
    final t = s.courses.createTopic(m.id, 'ECG');
    final e = repo.createExam('E');
    repo.addQuestion(e.id, q('1'));
    final c = repo.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
    repo.addQuestion(e.id, q('c1'), caseId: c.id);
    s.db.execute(
      "INSERT INTO documents(topic_id, title, kind, rel_path, imported_at) "
      "VALUES (?, 'poly', 'pdf', 'x.pdf', 't')",
      [t.id],
    );
    repo.setExamDocument(e.id, s.db.lastInsertId);
    final units = repo.sourceUnits([e.id]);
    expect(units, hasLength(2));
    expect(units[0].info, isNull);
    expect(units[1].info?.genre, CaseGenre.kfp);
    for (final u in units) {
      for (final sq in u.questions) {
        expect(sq.examId, e.id);
        expect(sq.topicId, t.id);
        expect(sq.subjectId, m.id); // déduite du thème
      }
    }
    // la matière de l'épreuve l'emporte
    final other = s.courses.createSubject(sem.id, 'Pneumo', color: 0xFF000000);
    repo.setExamSubject([e.id], other.id);
    expect(repo.sourceUnits([e.id]).first.questions.single.subjectId, other.id);
  });

  group('réglages mémorisés', () {
    test('défauts, puis valeurs enregistrées sans « une partie »', () {
      expect(repo.passageSettings().correction, Correction.end);
      repo.setPassageSettings(
        const PassageSettings(
          part: true,
          partCount: 5,
          random: true,
          correction: Correction.each,
          backAllowed: true,
          timerMinutes: 45,
          scoring: Scoring.points,
          shuffleProps: false,
        ),
      );
      final r = repo.passageSettings();
      expect(r.part, isFalse);
      expect(r.random, isFalse);
      expect(r.correction, Correction.each);
      expect(r.backAllowed, isTrue);
      expect(r.timerMinutes, 45);
      expect(r.scoring, Scoring.points);
      expect(r.shuffleProps, isFalse);
    });

    test('réglage abîmé : valeurs par défaut', () {
      s.settings.set(QcmRepository.passageSettingsKey, '{pas du json');
      expect(repo.passageSettings().scoring, Scoring.edn);
    });
  });

  test('médias cités par les épreuves et les copies', () {
    final e = repo.createExam('E');
    repo.addQuestion(
      e.id,
      const QzpQuestion(
        body: 'Q',
        images: ['aaaaaaaa.png'],
        image: 'bbbbbbbb.png',
        zones: [Zone(left: 0, top: 0, width: 1, height: 1)],
      ),
    );
    final c = repo.addCase(
      e.id,
      const CaseInfo(genre: CaseGenre.lca, articleFile: 'cccccccc.pdf'),
    );
    repo.addQuestion(e.id, q('1'), caseId: c.id);
    repo.saveAttempt(
      draft(
        repo,
        title: 'x',
        answers: [
          AnswerDraft(
            question: const QzpQuestion(body: 'Q', image: 'dddddddd.png'),
            grade: const Grade(0, 1, Verdict.skipped),
            info: const CaseInfo(
              genre: CaseGenre.lca,
              articleFile: 'eeeeeeee.pdf',
            ),
          ),
        ],
      ),
    );
    expect(repo.referencedMedia(), {
      'aaaaaaaa.png',
      'bbbbbbbb.png',
      'cccccccc.pdf',
      'dddddddd.png',
      'eeeeeeee.pdf',
    });
  });

  test('question illisible en base : remplacée sans bloquer', () {
    final e = repo.createExam('E');
    final id = repo.addQuestion(e.id, q('1'));
    s.db.execute("UPDATE exam_questions SET data_json = '{oups' WHERE id = ?", [
      id,
    ]);
    expect(repo.question(id).question.body, '(question illisible)');
    expect(repo.content(e.id).questions, hasLength(1));
  });

  test('supprimer une épreuve emporte ses cas et ses questions', () {
    // les clés étrangères en cascade ne laissent pas d'orphelins
    final e = repo.createExam('E');
    repo.addQuestion(e.id, q('1'));
    s.db.execute('DELETE FROM exams WHERE id = ?', [e.id]);
    expect(s.db.select('SELECT * FROM exam_questions'), isEmpty);
    expect(s.db.select('SELECT * FROM exam_cases'), isEmpty);
  });
}
