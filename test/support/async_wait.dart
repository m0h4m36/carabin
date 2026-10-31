import 'package:flutter_test/flutter_test.dart';

/// Laisse le temps au système de décoder une image (vrai asynchrone) puis
/// vérifie que [finder] trouve quelque chose.
Future<void> waitForWidget(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsWidgets);
}
