import 'package:carabin/app.dart';
import 'package:carabin/ui/destinations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cadre de l\'application', () {
    testWidgets('grand écran : barre latérale avec les cinq modules',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const CarabinApp());

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

      await tester.pumpWidget(const CarabinApp());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('on change de module en touchant son entrée', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const CarabinApp());
      expect(find.text('Agenda et méthode des J.'), findsNothing);

      await tester.tap(find.text('Planning'));
      await tester.pumpAndSettle();

      expect(find.text('Agenda et méthode des J.'), findsOneWidget);
    });
  });
}
