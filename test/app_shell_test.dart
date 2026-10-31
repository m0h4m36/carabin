import 'package:carabin/app.dart';
import 'package:carabin/ui/destinations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_session.dart';

void main() {
  group('Cadre de l\'application', () {
    testWidgets('grand écran : barre latérale avec les cinq modules', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CarabinApp(session: openTestSession()));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(carabinDestinations, hasLength(5));
      for (final d in carabinDestinations) {
        expect(find.text(d.label), findsWidgets);
      }
    });

    testWidgets('téléphone : barre de navigation du bas', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CarabinApp(session: openTestSession()));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('on change de module en touchant son entrée', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CarabinApp(session: openTestSession()));
      expect(find.text('Agenda et méthode des J.'), findsNothing);

      await tester.tap(find.text('Planning'));
      await tester.pumpAndSettle();

      expect(find.text('Agenda et méthode des J.'), findsOneWidget);
    });

    testWidgets('le module Cours garde sa page quand on change d\'onglet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = openTestSession();
      session.courses.createYear('2026');

      await tester.pumpWidget(CarabinApp(session: session));
      await tester.tap(find.text('Cours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau semestre'), findsOneWidget);

      await tester.tap(find.text('QCM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cours'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau semestre'), findsOneWidget);
    });
  });
}
