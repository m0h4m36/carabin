import 'dart:convert';
import 'dart:typed_data';

import 'package:carabin/app_session.dart';
import 'package:carabin/data/errors.dart';
import 'package:carabin/data/media_store.dart';
import 'package:carabin/data/qcm_models.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/exam_file.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/png.dart';
import '../support/test_session.dart';

Uint8List pdfBytes() =>
    Uint8List.fromList(utf8.encode('%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF'));

List<String> shape(ExamContent c) => [
  for (final u in c.units)
    switch (u) {
      SingleUnit(:final question) =>
        '${question.question.kind.name}:${question.question.body}',
      CaseUnit(:final kase, :final questions) =>
        '${kase.info.genre.name}(${questions.map((q) => q.question.body).join(',')})',
    },
];

void main() {
  late Session a; // l'expéditeur
  late Session b; // le destinataire

  setUp(() {
    a = openTestSession();
    b = openTestSession();
  });

  tearDown(() {
    a.dispose();
    b.dispose();
  });

  /// Une épreuve complète chez l'expéditeur.
  int build() {
    final y = a.courses.createYear('A');
    final sem = a.courses.createSemester(y.id, 'S1');
    final subject = a.courses.createSubject(sem.id, 'Cardiologie', color: 1);
    final e = a.qcm.createExam('Annale 2025', subjectId: subject.id);
    a.qcm.setExamItems(e.id, '12, 224');
    final img = a.media.addBytes(solidPng(4, 4), 'png');
    final img2 = a.media.addBytes(solidPng(6, 5, r: 10), 'png');
    final pdf = a.media.addBytes(pdfBytes(), 'pdf');
    a.qcm.addQuestion(
      e.id,
      ChoiceQuestion(
        body: 'Q1 [img:$img]',
        images: [img],
        explanation: 'Parce que',
        propositions: const [
          Proposition(text: 'A', correct: true, critical: true),
          Proposition(text: 'B'),
        ],
      ),
    );
    final c = a.qcm.addCase(
      e.id,
      CaseInfo(
        genre: CaseGenre.lca,
        context: 'ctx',
        articleText: 'Article',
        articleFile: pdf,
      ),
    );
    a.qcm.addQuestion(
      e.id,
      QzpQuestion(
        body: 'Où ?',
        image: img2,
        zones: const [Zone(left: 0, top: 0, width: 0.5, height: 0.5)],
      ),
      caseId: c.id,
    );
    a.qcm.addQuestion(
      e.id,
      const QrocQuestion(body: 'Q3', model: 'M'),
      caseId: c.id,
    );
    return e.id;
  }

  test('partage d\'une épreuve entre deux appareils', () {
    final id = build();
    final out = a.examExchange.exportExam(id);
    expect(out.fileName, 'Annale 2025.qcm.json');
    expect(out.missingMedia, 0);

    final file = b.examExchange.parse(out.bytes);
    expect(file.media, hasLength(3));
    final y = b.courses.createYear('B');
    final sem = b.courses.createSemester(y.id, 'S1');
    final mine = b.courses.createSubject(sem.id, 'Cardiologie', color: 1);

    final report = b.examExchange.apply(file);
    expect(report.questions, 3);
    expect(report.mediaAdded, 3);
    expect(report.mediaMissing, 0);
    expect(report.mediaRejected, 0);
    expect(report.subjectLinked, isTrue);
    expect(report.replaced, isFalse);

    final got = b.qcm.content(report.examId);
    expect(got.exam.title, 'Annale 2025');
    expect(got.exam.imported, isTrue);
    expect(got.exam.subjectId, mine.id);
    expect(got.exam.items, '12, 224');
    expect(got.exam.guid, a.qcm.exam(id).guid);
    expect(shape(got), [
      'qcm:Q1 [img:${(got.units.first.questions.first.question as ChoiceQuestion).images.first}]',
      'lca(Où ?,Q3)',
    ]);
    final first = got.units.first.questions.first.question as ChoiceQuestion;
    expect(first.propositions.first.critical, isTrue);
    expect(first.explanation, 'Parce que');
    // les médias sont bien dans le dossier du destinataire
    expect(b.media.exists(first.images.single), isTrue);
    final caseUnit = got.units[1] as CaseUnit;
    expect(b.media.exists(caseUnit.kase.info.articleFile), isTrue);
    final qzp = caseUnit.questions.first.question as QzpQuestion;
    expect(b.media.exists(qzp.image), isTrue);
  });

  test('les noms de médias suivent le contenu reçu, pas le nom annoncé', () {
    final id = build();
    final text = jsonDecode(
      utf8.decode(a.examExchange.exportExam(id).bytes),
    ) as Map<String, dynamic>;
    // un expéditeur qui triche sur le nom : le contenu fait foi
    final media = text['media'] as Map<String, dynamic>;
    final key = media.keys.firstWhere((k) => k.endsWith('.png'));
    final liar = 'ffffffffffffffffffff.png';
    media[liar] = media.remove(key);
    for (final u in (text['exam']['units'] as List)) {
      for (final q in (u['questions'] as List)) {
        if (q['images'] != null) q['images'] = [liar];
        if (q['image'] == key) q['image'] = liar;
      }
    }
    final file = b.examExchange.parse(
      Uint8List.fromList(utf8.encode(jsonEncode(text))),
    );
    final report = b.examExchange.apply(file);
    final got = b.qcm.content(report.examId);
    final first = got.units.first.questions.first.question as ChoiceQuestion;
    expect(first.images.single, isNot(liar));
    expect(first.images.single, MediaStore.nameFor(file.media[liar]!, 'png'));
    expect(b.media.exists(first.images.single), isTrue);
  });

  test('même épreuve reçue deux fois : copie, ou remplacement', () {
    final id = build();
    final bytes = a.examExchange.exportExam(id).bytes;
    final file = b.examExchange.parse(bytes);
    final first = b.examExchange.apply(file);
    expect(b.examExchange.existingId(file), first.examId);

    // sans remplacement : une deuxième épreuve, nouvel identifiant
    final second = b.examExchange.apply(file);
    expect(second.examId, isNot(first.examId));
    expect(
      b.qcm.exam(second.examId).guid,
      isNot(b.qcm.exam(first.examId).guid),
    );
    expect(b.qcm.exams(), hasLength(2));

    // avec remplacement : même épreuve, contenu refait, copies conservées
    final attempt = b.qcm.saveAttempt(
      AttemptDraft(
        title: 'x',
        examId: first.examId,
        settings: const PassageSettings(),
        startedAt: DateTime.utc(2026, 1, 1),
        duration: Duration.zero,
        answers: const [],
      ),
    );
    a.qcm.addQuestion(id, const QrocQuestion(body: 'Nouvelle', model: 'M'));
    a.qcm.renameExam(id, 'Annale 2025 corrigée');
    final newer = b.examExchange.parse(a.examExchange.exportExam(id).bytes);
    final replaced = b.examExchange.apply(newer, replace: true);
    expect(replaced.replaced, isTrue);
    expect(replaced.examId, first.examId);
    final got = b.qcm.content(first.examId);
    expect(got.exam.title, 'Annale 2025 corrigée');
    expect(got.questions, hasLength(4));
    expect(b.qcm.exams(), hasLength(2));
    expect(b.qcm.attemptRow(attempt).examId, first.examId);
    // aucun reste de l'ancien contenu
    expect(
      b.db.select('SELECT * FROM exam_questions WHERE exam_id = ?', [
        first.examId,
      ]),
      hasLength(4),
    );
  });

  test('remplacer garde la matière choisie ici si le fichier n\'en a pas', () {
    final id = build();
    final file = b.examExchange.parse(a.examExchange.exportExam(id).bytes);
    final first = b.examExchange.apply(file);
    // Chez le destinataire, la matière « Cardiologie » n'existe pas : on en
    // choisit une à la main.
    final y = b.courses.createYear('B');
    final sem = b.courses.createSemester(y.id, 'S1');
    final mine = b.courses.createSubject(sem.id, 'Ma matière', color: 2);
    b.qcm.setExamSubject([first.examId], mine.id);
    final again = b.examExchange.apply(file, replace: true);
    expect(again.replaced, isTrue);
    expect(b.qcm.exam(first.examId).subjectId, mine.id);
  });

  test('remplacer quand rien n\'existe : simple création', () {
    final id = build();
    final file = b.examExchange.parse(a.examExchange.exportExam(id).bytes);
    final r = b.examExchange.apply(file, replace: true);
    expect(r.replaced, isFalse);
    expect(b.qcm.exams(), hasLength(1));
  });

  test('matière absente ou ambiguë : épreuve non rangée', () {
    final id = build();
    final file = b.examExchange.parse(a.examExchange.exportExam(id).bytes);
    expect(b.examExchange.apply(file).subjectLinked, isFalse);

    final y = b.courses.createYear('B');
    final s1 = b.courses.createSemester(y.id, 'S1');
    final s2 = b.courses.createSemester(y.id, 'S2');
    b.courses.createSubject(s1.id, 'Cardiologie', color: 1);
    b.courses.createSubject(s2.id, 'Cardiologie', color: 1);
    final r = b.examExchange.apply(file);
    expect(r.subjectLinked, isFalse);
    expect(b.qcm.exam(r.examId).subjectId, isNull);
  });

  test('médias absents du fichier signalés', () {
    final e = a.qcm.createExam('Sans images');
    a.qcm.addQuestion(
      e.id,
      const ChoiceQuestion(
        body: 'Q',
        images: ['aaaaaaaaaa.png'],
        propositions: [
          Proposition(text: 'A', correct: true),
          Proposition(text: 'B'),
        ],
      ),
    );
    final out = a.examExchange.exportExam(e.id);
    expect(out.missingMedia, 1);
    final report = b.examExchange.apply(b.examExchange.parse(out.bytes));
    expect(report.mediaMissing, 1);
    expect(report.mediaAdded, 0);
  });

  test('média refusé : format inconnu, faux PDF', () {
    final id = build();
    final text = jsonDecode(
      utf8.decode(a.examExchange.exportExam(id).bytes),
    ) as Map<String, dynamic>;
    (text['media'] as Map<String, dynamic>)['aaaaaaaaaa.exe'] = base64Encode([
      1,
      2,
      3,
    ]);
    (text['media'] as Map<String, dynamic>)['bbbbbbbbbb.pdf'] = base64Encode(
      utf8.encode('pas un pdf'),
    );
    final file = b.examExchange.parse(
      Uint8List.fromList(utf8.encode(jsonEncode(text))),
    );
    final report = b.examExchange.apply(file);
    expect(report.mediaRejected, 2);
    expect(report.mediaAdded, 3);
  });

  group('fichiers refusés', () {
    ExchangeError? failure(Uint8List bytes) {
      try {
        b.examExchange.parse(bytes);
      } on ExchangeError catch (e) {
        return e;
      }
      return null;
    }

    Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

    test('pas du texte, pas du JSON, pas une épreuve', () {
      expect(
        failure(Uint8List.fromList([0xff, 0xfe, 0x00]))?.problem,
        ImportProblem.unreadable,
      );
      expect(failure(bytesOf('bonjour'))?.problem, ImportProblem.unreadable);
      expect(
        failure(bytesOf('{"format":"autre"}'))?.problem,
        ImportProblem.unreadable,
      );
    });

    test('version plus récente', () {
      final id = build();
      final text = jsonDecode(
        utf8.decode(a.examExchange.exportExam(id).bytes),
      ) as Map<String, dynamic>;
      text['version'] = examFileVersion + 1;
      expect(
        failure(bytesOf(jsonEncode(text)))?.problem,
        ImportProblem.newerFormat,
      );
    });

    test('épreuve sans question', () {
      final text = encodeExamFile(
        const ExamDoc(guid: 'abcdefgh12345678', title: 'Vide'),
        const {},
      );
      expect(failure(bytesOf(text))?.problem, ImportProblem.empty);
    });
  });

  test('un cas sans question n\'est pas exporté', () {
    final e = a.qcm.createExam('E');
    a.qcm.addQuestion(e.id, const QrocQuestion(body: 'Q', model: 'M'));
    a.qcm.addCase(e.id, const CaseInfo(genre: CaseGenre.kfp));
    final file = b.examExchange.parse(a.examExchange.exportExam(e.id).bytes);
    expect(file.exam.units, hasLength(1));
  });

  test('nom de fichier sûr', () {
    expect(
      b.examExchange.parse(a.examExchange.exportExam(build()).bytes).exam.title,
      'Annale 2025',
    );
    final odd = a.qcm.createExam('Cardio: "ECG" / 2025?');
    expect(a.examExchange.exportExam(odd.id).fileName, endsWith('.qcm.json'));
    expect(a.examExchange.exportExam(odd.id).fileName, isNot(contains('/')));
    expect(a.examExchange.exportExam(odd.id).fileName, isNot(contains(':')));
  });
}
