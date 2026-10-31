import 'dart:io';

import 'package:carabin/data/media_store.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:carabin/features/qcm/question_form.dart';
import 'package:carabin/ui/pickers.dart';
import 'package:carabin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/png.dart';
import '../../support/test_session.dart';

class FormOut {
  Question? last;
  int count = 0;
  int? caseId;
}

Future<FormOut> pump(
  WidgetTester tester,
  Question q, {
  List<CaseChoice> cases = const [],
  int? caseId,
  MediaStore? media,
}) async {
  final out = FormOut()..caseId = caseId;
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = media ?? openTestSession().media;
  await tester.pumpWidget(
    Provider<MediaStore>.value(
      value: store,
      child: MaterialApp(
        theme: CarabinTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuestionForm(
                key: const ValueKey('form'),
                question: q,
                cases: cases,
                caseId: out.caseId,
                onCaseChanged: cases.isEmpty
                    ? null
                    : (id) => setState(() => out.caseId = id),
                onChanged: (v) {
                  out.last = v;
                  out.count++;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return out;
}

ChoiceQuestion choice(FormOut o) => o.last! as ChoiceQuestion;

void main() {
  testWidgets('écrire l\'énoncé et les propositions', (tester) async {
    final o = await pump(tester, Question.empty(QuestionKind.qcm));
    await tester.enterText(
      find.byKey(const ValueKey('body')),
      'Quelle est la cause ?',
    );
    expect(o.last!.body, 'Quelle est la cause ?');
    await tester.enterText(
      find.byKey(const ValueKey('proposition-0')),
      'Infarctus',
    );
    await tester.enterText(
      find.byKey(const ValueKey('proposition-1')),
      'Embolie',
    );
    await tester.tap(find.byKey(const ValueKey('correct-0')));
    await tester.pump();
    final c = choice(o);
    expect(c.propositions.map((p) => p.text), ['Infarctus', 'Embolie']);
    expect(c.propositions.map((p) => p.correct), [true, false]);
    expect(c.issues, isEmpty);
    expect(find.text('QRU : une seule bonne réponse.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('correct-1')));
    await tester.pump();
    expect(find.textContaining('QRM : 2 bonnes réponses'), findsOneWidget);
  });

  testWidgets('ajouter, supprimer des propositions garde les textes', (
    tester,
  ) async {
    final o = await pump(tester, Question.empty(QuestionKind.qcm));
    await tester.enterText(find.byKey(const ValueKey('proposition-0')), 'A0');
    await tester.enterText(find.byKey(const ValueKey('proposition-1')), 'B1');
    await tester.tap(find.byKey(const ValueKey('add-proposition')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('proposition-2')), 'C2');
    expect(choice(o).propositions.length, 3);
    // Supprimer la première : B1 et C2 gardent leur texte.
    await tester.tap(find.byKey(const ValueKey('remove-proposition-0')));
    await tester.pump();
    expect(choice(o).propositions.map((p) => p.text), ['B1', 'C2']);
    expect(find.text('B1'), findsOneWidget);
    expect(find.text('C2'), findsOneWidget);
    expect(find.text('A0'), findsNothing);
    // Deux propositions au minimum.
    final remove = tester.widget<IconButton>(
      find.byKey(const ValueKey('remove-proposition-0')),
    );
    expect(remove.onPressed, isNull);
  });

  testWidgets('la limite de propositions est respectée', (tester) async {
    final q = ChoiceQuestion(
      propositions: [
        for (var i = 0; i < maxPropositions; i++) Proposition(text: 'p$i'),
      ],
    );
    await pump(tester, q);
    expect(find.byKey(const ValueKey('add-proposition')), findsNothing);
  });

  testWidgets('proposition critique et passage en QRP', (tester) async {
    final o = await pump(tester, Question.empty(QuestionKind.qcm));
    await tester.tap(find.byKey(const ValueKey('critical-1')));
    await tester.pump();
    expect(choice(o).propositions[1].critical, isTrue);
    await tester.tap(find.byKey(const ValueKey('qrp-switch')));
    await tester.pump();
    expect(choice(o).pointed, isTrue);
    expect(o.last!.kind, QuestionKind.qrp);
    expect(choice(o).propositions[1].critical, isTrue);
  });

  testWidgets('points : valeur invalide signalée, non enregistrée', (
    tester,
  ) async {
    final o = await pump(tester, Question.empty(QuestionKind.qcm));
    await tester.enterText(find.byKey(const ValueKey('points')), '2,5');
    expect(o.last!.points, 2.5);
    final count = o.count;
    await tester.enterText(find.byKey(const ValueKey('points')), '0');
    await tester.pump();
    expect(o.count, count);
    expect(o.last!.points, 2.5);
    expect(find.text('Un nombre entre 0,01 et 1000'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('points')), 'abc');
    await tester.pump();
    expect(o.last!.points, 2.5);
    await tester.enterText(find.byKey(const ValueKey('points')), '1001');
    await tester.pump();
    expect(o.last!.points, 2.5);
    await tester.enterText(find.byKey(const ValueKey('points')), '3');
    await tester.pump();
    expect(o.last!.points, 3);
    expect(find.text('Un nombre entre 0,01 et 1000'), findsNothing);
  });

  testWidgets('changer de type sans rien perdre ne demande rien', (
    tester,
  ) async {
    final o = await pump(tester, Question.empty(QuestionKind.qcm));
    await tester.enterText(find.byKey(const ValueKey('body')), 'Énoncé');
    await tester.tap(find.byKey(const ValueKey('kind-qroc')));
    await tester.pumpAndSettle();
    expect(o.last, isA<QrocQuestion>());
    expect(o.last!.body, 'Énoncé');
    expect(find.byKey(const ValueKey('qroc-model')), findsOneWidget);
  });

  testWidgets('changer de type avec du contenu demande confirmation', (
    tester,
  ) async {
    final o = await pump(
      tester,
      const ChoiceQuestion(
        body: 'x',
        propositions: [
          Proposition(text: 'a', correct: true),
          Proposition(text: 'b'),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('kind-tcs')));
    await tester.pumpAndSettle();
    expect(find.text('Changer de type ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(o.last, isNull);
    await tester.tap(find.byKey(const ValueKey('kind-tcs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer de type'));
    await tester.pumpAndSettle();
    expect(o.last, isA<TcsQuestion>());
    expect(o.last!.body, 'x');
    expect(find.byKey(const ValueKey('tcs-hypothesis')), findsOneWidget);
  });

  testWidgets('QROC : nature, longueur, éléments', (tester) async {
    final o = await pump(tester, Question.empty(QuestionKind.qroc));
    await tester.enterText(
      find.byKey(const ValueKey('qroc-nature')),
      'Un diagnostic',
    );
    await tester.enterText(
      find.byKey(const ValueKey('qroc-model')),
      'Infarctus',
    );
    await tester.tap(find.byKey(const ValueKey('add-element')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-element')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('element-0')),
      'infarctus|IDM',
    );
    await tester.enterText(
      find.byKey(const ValueKey('element-1')),
      'troponine',
    );
    await tester.enterText(
      find.byKey(const ValueKey('element-points-1')),
      '0,5',
    );
    var q = o.last! as QrocQuestion;
    expect(q.nature, 'Un diagnostic');
    expect(q.model, 'Infarctus');
    expect(q.elements.map((e) => e.pattern), ['infarctus|IDM', 'troponine']);
    expect(q.elements.map((e) => e.points), [1, 0.5]);
    await tester.tap(find.byKey(const ValueKey('remove-element-0')));
    await tester.pump();
    q = o.last! as QrocQuestion;
    expect(q.elements.single.pattern, 'troponine');
    expect(find.text('troponine'), findsOneWidget);
    // Longueur maximale.
    await tester.tap(find.byKey(const ValueKey('qroc-lines')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 lignes').last);
    await tester.pumpAndSettle();
    expect((o.last! as QrocQuestion).maxLines, 3);
  });

  testWidgets('TCS : texte et panel', (tester) async {
    final o = await pump(tester, Question.empty(QuestionKind.tcs));
    await tester.enterText(
      find.byKey(const ValueKey('tcs-hypothesis')),
      'Embolie',
    );
    await tester.enterText(
      find.byKey(const ValueKey('tcs-new-info')),
      'D-dimères négatifs',
    );
    await tester.tap(find.byKey(const ValueKey('panel-plus--2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('panel-plus--2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('panel-plus-1')));
    await tester.pump();
    final q = o.last! as TcsQuestion;
    expect(q.hypothesis, 'Embolie');
    expect(q.newInfo, 'D-dimères négatifs');
    expect(q.panel, [2, 0, 0, 1, 0]);
    expect(find.text('3 experts'), findsOneWidget);
    expect(q.issues, isEmpty);
    // Le panel ne descend pas sous zéro.
    final minus = tester.widget<IconButton>(
      find.byKey(const ValueKey('panel-minus-0')),
    );
    expect(minus.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('panel-minus--2')));
    await tester.pump();
    expect((o.last! as TcsQuestion).panel[0], 1);
  });

  testWidgets('QZP : choisir l\'image puis garder les zones', (tester) async {
    final session = openTestSession();
    final tmp = Directory.systemTemp.createTempSync('carabin_qzp_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/zone.png')
      ..writeAsBytesSync(solidPng(40, 30));
    final original = Pickers.image;
    Pickers.image = () async => file.path;
    addTearDown(() => Pickers.image = original);

    final o = await pump(
      tester,
      Question.empty(QuestionKind.qzp),
      media: session.media,
    );
    expect(find.byKey(const ValueKey('qzp-pick')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qzp-pick')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final q = o.last! as QzpQuestion;
    expect(q.image, endsWith('.png'));
    expect(session.media.exists(q.image), isTrue);
    expect(q.zones, isEmpty);
    expect(q.issues, contains(QuestionIssue.qzpZone));
  });

  testWidgets('images jointes : ajout et retrait', (tester) async {
    final session = openTestSession();
    final tmp = Directory.systemTemp.createTempSync('carabin_img_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/a.png')..writeAsBytesSync(solidPng(10, 10));
    final original = Pickers.image;
    Pickers.image = () async => file.path;
    addTearDown(() => Pickers.image = original);

    final o = await pump(
      tester,
      Question.empty(QuestionKind.qcm),
      media: session.media,
    );
    await tester.tap(find.byKey(const ValueKey('add-image')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(o.last!.images.length, 1);
    // Même image : pas de doublon.
    await tester.tap(find.byKey(const ValueKey('add-image')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(o.last!.images.length, 1);
    await tester.tap(find.text('Retirer l\'image'));
    await tester.pump();
    expect(o.last!.images, isEmpty);
  });

  testWidgets('rangement dans un cas', (tester) async {
    final o = await pump(
      tester,
      Question.empty(QuestionKind.qcm),
      cases: const [CaseChoice(7, 'Dossier 1'), CaseChoice(9, 'KFP 2')],
    );
    await tester.tap(find.byKey(const ValueKey('case-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KFP 2').last);
    await tester.pumpAndSettle();
    expect(o.caseId, 9);
  });

  testWidgets('sans cas dans l\'épreuve, pas de liste de cas', (tester) async {
    await pump(tester, Question.empty(QuestionKind.qcm));
    expect(find.byKey(const ValueKey('case-dropdown')), findsNothing);
  });
}
