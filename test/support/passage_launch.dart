import 'package:carabin/app_session.dart';
import 'package:carabin/domain/qcm/exam.dart';
import 'package:carabin/domain/qcm/question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_page.dart';

/// Page de départ avec un bouton qui ouvre [page] : permet de vérifier qu'un
/// écran se ferme (il n'est pas la dernière page de la pile).
class Launcher extends StatelessWidget {
  const Launcher(this.page, {super.key});

  final Widget Function() page;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        key: const ValueKey('launch'),
        onPressed: () =>
            Navigator.of(context)
                .push<void>(MaterialPageRoute(builder: (_) => page())),
        child: const Text('Lancer'),
      ),
    ),
  );
}

/// Montre [Launcher] puis ouvre la page.
Future<void> openFromLauncher(
  WidgetTester tester,
  Session session,
  Widget Function() page, {
  Size size = const Size(1400, 900),
}) async {
  await pumpPage(tester, session, Launcher(page), size: size);
  await tester.tap(find.byKey(const ValueKey('launch')));
  await tester.pumpAndSettle();
}

/// QRU : une bonne réponse, une mauvaise.
ChoiceQuestion qru(String good, String bad, {String? body}) => ChoiceQuestion(
  body: body ?? 'Énoncé de $good',
  propositions: [
    Proposition(text: good, correct: true),
    Proposition(text: bad),
  ],
);

PlannedQuestion planned(
  Question q, {
  CaseInfo? info,
  int group = -1,
  List<int> order = const [],
}) => PlannedQuestion(question: q, info: info, caseGroup: group, order: order);
