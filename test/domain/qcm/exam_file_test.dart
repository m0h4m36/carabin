import 'dart:convert';
import 'dart:typed_data';

import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/exam_file.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter_test/flutter_test.dart';

ExamDoc sample() => ExamDoc(
  guid: 'abcd1234efgh5678',
  title: 'Annale cardio 2025',
  subjectName: 'Cardiologie',
  items: '12, 224',
  pastPaper: true,
  units: [
    ExamUnitDoc([
      const ChoiceQuestion(
        body: 'Q1',
        propositions: [
          Proposition(text: 'A', correct: true),
          Proposition(text: 'B'),
        ],
      ),
    ]),
    ExamUnitDoc(
      [
        const QzpQuestion(
          body: 'Où ?',
          image: 'aaaaaaaaaa.png',
          zones: [Zone(left: 0, top: 0, width: 0.5, height: 0.5)],
        ),
        const QrocQuestion(body: 'Q3', model: 'M', images: ['bbbbbbbbbb.jpg']),
      ],
      info: const CaseInfo(
        genre: CaseGenre.lca,
        title: 'Article',
        context: 'Contexte',
        articleText: 'Texte de l\'article',
        articleFile: 'cccccccccc.pdf',
      ),
    ),
  ],
);

void main() {
  test('aller-retour avec médias', () {
    final media = {
      'aaaaaaaaaa.png': Uint8List.fromList([1, 2, 3]),
      'bbbbbbbbbb.jpg': Uint8List.fromList([4, 5]),
      'cccccccccc.pdf': Uint8List.fromList([6]),
    };
    final text = encodeExamFile(sample(), media, appVersion: '1.0.0');
    final file = decodeExamFile(text);
    expect(file.exam.title, 'Annale cardio 2025');
    expect(file.exam.subjectName, 'Cardiologie');
    expect(file.exam.items, '12, 224');
    expect(file.exam.pastPaper, isTrue);
    expect(file.exam.questionCount, 3);
    expect(file.exam.units, hasLength(2));
    expect(file.exam.units[0].info, isNull);
    final c = file.exam.units[1].info!;
    expect(c.genre, CaseGenre.lca);
    expect(c.articleFile, 'cccccccccc.pdf');
    expect(c.articleText, 'Texte de l\'article');
    expect(file.media['aaaaaaaaaa.png'], [1, 2, 3]);
    expect(file.media['cccccccccc.pdf'], [6]);
    expect(file.exam.mediaNames, {
      'aaaaaaaaaa.png',
      'bbbbbbbbbb.jpg',
      'cccccccccc.pdf',
    });
  });

  test('renommage des médias, article compris', () {
    final r = sample().remapMedia((n) => 'x$n');
    expect(r.mediaNames, {
      'xaaaaaaaaaa.png',
      'xbbbbbbbbbb.jpg',
      'xcccccccccc.pdf',
    });
    expect(r.units[1].info!.articleFile, 'xcccccccccc.pdf');
  });

  test('refus d\'un fichier qui n\'est pas une épreuve', () {
    expect(() => decodeExamFile('pas du json'), throwsFormatException);
    expect(() => decodeExamFile('[]'), throwsFormatException);
    expect(() => decodeExamFile('{"format":"autre"}'), throwsFormatException);
  });

  test('version plus récente signalée', () {
    final j = jsonDecode(
      encodeExamFile(sample(), {}, appVersion: '1'),
    ) as Map<String, dynamic>;
    j['version'] = examFileVersion + 1;
    expect(() => decodeExamFile(jsonEncode(j)), throwsA(isA<NewerExamFile>()));
  });

  Map<String, dynamic> base() =>
      jsonDecode(encodeExamFile(sample(), {}, appVersion: '1'))
          as Map<String, dynamic>;

  test('champs invalides refusés', () {
    var j = base();
    (j['exam'] as Map)['guid'] = '../x';
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);

    j = base();
    (j['exam'] as Map)['title'] = '   ';
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);

    j = base();
    (j['exam'] as Map)['units'] = 'x';
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);

    j = base();
    ((j['exam'] as Map)['units'] as List)[0]['questions'] = [];
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);

    // plusieurs questions sans cas
    j = base();
    final units = (j['exam'] as Map)['units'] as List;
    units[0]['questions'] = [
      units[0]['questions'][0],
      units[0]['questions'][0],
    ];
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);
  });

  test('médias invalides refusés', () {
    var j = base();
    j['media'] = {
      '../evil.png': base64Encode([1]),
    };
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);
    j = base();
    j['media'] = {'aaaaaaaaaa.png': '***pas du base64***'};
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);
    j = base();
    j['media'] = 'x';
    expect(() => decodeExamFile(jsonEncode(j)), throwsFormatException);
  });

  test('texte trop long tronqué plutôt que refusé', () {
    final j = base();
    (j['exam'] as Map)['title'] = 'T' * 500;
    final f = decodeExamFile(jsonEncode(j));
    expect(f.exam.title.length, 200);
  });
}
