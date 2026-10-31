import 'dart:io';

import 'package:carabin/app.dart';
import 'package:carabin/app_session.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/features/flashcards/occlusion_editor.dart';
import 'package:carabin/features/flashcards/occlusion_view.dart';
import 'package:carabin/ui/pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/png.dart';
import '../support/test_session.dart';

Future<void> pumpFlash(WidgetTester tester, Session session) async {
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CarabinApp(session: session));
  await tester.tap(find.text('Flashcards').first);
  await tester.pumpAndSettle();
}

/// Laisse le temps au système de décoder une image (vrai asynchrone).
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

String writePng(String name, {int w = 200, int h = 100}) {
  final dir = Directory.systemTemp.createTempSync('carabin_img_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final f = File(p.join(dir.path, name))..writeAsBytesSync(solidPng(w, h));
  return f.path;
}

void main() {
  group('brouillon d\'occlusion', () {
    OcclusionDraft draft() => OcclusionDraft()..image = 'a.png';

    test('une zone trop petite est ignorée', () {
      final d = draft();
      expect(d.addMask(const Rect.fromLTWH(0.1, 0.1, 0.005, 0.2)), isFalse);
      expect(d.masks, isEmpty);
      expect(d.addMask(const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)), isTrue);
      expect(d.masks, hasLength(1));
    });

    test('les zones restent dans l\'image', () {
      final d = draft()..addMask(const Rect.fromLTRB(-0.3, 0.5, 1.4, 2));
      final m = d.masks.single;
      expect(m.left, 0);
      expect(m.left + m.width, 1);
      expect(m.top + m.height, 1);
    });

    test('annuler défait le dernier changement, un par un', () {
      final d = draft()
        ..addMask(const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2))
        ..addMask(const Rect.fromLTWH(0.5, 0.5, 0.2, 0.2));
      expect(d.masks, hasLength(2));
      expect(d.undo(), isTrue);
      expect(d.masks, hasLength(1));
      d.clearMasks();
      expect(d.masks, isEmpty);
      expect(d.undo(), isTrue);
      expect(d.masks, hasLength(1));
      expect(d.undo(), isTrue);
      expect(d.masks, isEmpty);
      expect(d.undo(), isFalse);
    });

    test(
      'chaque zone a un identifiant qui ne change pas quand on en supprime une',
      () {
        final d = draft()
          ..addMask(const Rect.fromLTWH(0.1, 0.1, 0.1, 0.1))
          ..addMask(const Rect.fromLTWH(0.3, 0.1, 0.1, 0.1))
          ..addMask(const Rect.fromLTWH(0.5, 0.1, 0.1, 0.1));
        expect(d.masks.map((m) => m.id), [1, 2, 3]);
        d.selectAt(const Offset(0.35, 0.15));
        d.removeSelected();
        expect(d.masks.map((m) => m.id), [1, 3]);
        d.addMask(const Rect.fromLTWH(0.7, 0.1, 0.1, 0.1));
        expect(d.masks.map((m) => m.id), [1, 3, 4]);
      },
    );

    test('mode groupement : les zones prennent le groupe courant et on peut les déplacer', () {
      final d = draft()..setMode(OcclusionMode.group);
      d.addMask(const Rect.fromLTWH(0.1, 0.1, 0.1, 0.1));
      d.setGroup(2);
      d.addMask(const Rect.fromLTWH(0.3, 0.1, 0.1, 0.1));
      d.addMask(const Rect.fromLTWH(0.5, 0.1, 0.1, 0.1));
      expect(d.masks.map((m) => m.group), [1, 2, 2]);
      expect(d.groupCount, 2);
      expect(d.cardCount, 2);

      // changer de groupe ne touche à aucune zone déjà dessinée
      d.setGroup(3);
      expect(d.masks.map((m) => m.group), [1, 2, 2]);

      // sauf si on le demande pour la zone choisie
      expect(d.selected, isNull);
      d.selectAt(const Offset(0.55, 0.15));
      expect(d.selected!.id, 3);
      d.moveSelectedToGroup();
      expect(d.masks.map((m) => m.group), [1, 2, 3]);
      expect(d.cardCount, 3);
      expect(d.undo(), isTrue);
      expect(d.masks.map((m) => m.group), [1, 2, 2]);
    });

    test('hors mode groupement, toutes les zones sont dans le groupe 1', () {
      final d = draft()
        ..setGroup(5)
        ..addMask(const Rect.fromLTWH(0.1, 0.1, 0.1, 0.1));
      expect(d.masks.single.group, 1);
    });

    test('nombre de cartes selon le mode', () {
      final d = draft()
        ..addMask(const Rect.fromLTWH(0.1, 0.1, 0.1, 0.1))
        ..addMask(const Rect.fromLTWH(0.3, 0.1, 0.1, 0.1))
        ..addMask(const Rect.fromLTWH(0.5, 0.1, 0.1, 0.1));
      expect(d.cardCount, 1); // tout caché
      d.setMode(OcclusionMode.hideOne);
      expect(d.cardCount, 3);
      d.setMode(OcclusionMode.group);
      expect(d.cardCount, 1); // tous dans le groupe 1
    });

    test('toFields puis load redonnent la même note', () {
      final d = draft()
        ..setMode(OcclusionMode.hideOne)
        ..addMask(const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4));
      final f = d.toFields(extra: 'Coupe');
      final e = OcclusionDraft()..load(f);
      expect(e.image, 'a.png');
      expect(e.mode, OcclusionMode.hideOne);
      expect(e.masks.single.left, closeTo(0.1, 1e-12));
      expect(e.masks.single.height, closeTo(0.4, 1e-12));
      expect(f.extra, 'Coupe');
    });
  });

  group('écrans', () {
    final restore = Pickers.image;
    tearDown(() => Pickers.image = restore);

    testWidgets('créer une note d\'occlusion : image, zones, mode, ajout', (
      tester,
    ) async {
      final session = openTestSession();
      final deck = session.flashcards.createDeck('Anatomie');
      final path = writePng('schema.PNG');
      Pickers.image = () async => path;
      await pumpFlash(tester, session);

      await tester.tap(find.byKey(ValueKey('menu-deck-${deck.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle carte').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Occlusion d\'image'));
      await tester.pumpAndSettle();

      // sans image ni zone : message clair, rien n'est créé
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez d\'abord une image.'), findsOneWidget);
      expect(session.flashcards.notes(deck.id), isEmpty);

      await tester.tap(find.byKey(const ValueKey('occlusion-pick')));
      await tester.pump();
      final canvas = find.byKey(const ValueKey('occlusion-canvas'));
      await waitFor(tester, canvas);
      await tester.pumpAndSettle();
      expect(
        find.text('0 zone · 0 groupe · 0 carte à fabriquer'),
        findsOneWidget,
      );

      // sans zone : message clair
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dessinez au moins une zone à masquer.'),
        findsOneWidget,
      );

      final size = tester.getSize(canvas);
      expect(
        size.width / size.height,
        closeTo(2, 0.02),
      ); // l'image est 200 × 100

      /// Trace un rectangle : coin et taille en fractions de l'image.
      Future<void> draw(Offset from, Offset by) async {
        final start =
            tester.getTopLeft(canvas) +
            Offset(from.dx * size.width, from.dy * size.height);
        final move = Offset(by.dx * size.width / 2, by.dy * size.height / 2);
        final g = await tester.startGesture(start);
        await g.moveBy(move);
        await g.moveBy(move);
        await g.up();
        await tester.pumpAndSettle();
      }

      await draw(const Offset(0.10, 0.10), const Offset(0.30, 0.30));
      await draw(const Offset(0.60, 0.50), const Offset(0.25, 0.40));
      expect(
        find.text('2 zones · 1 groupe · 1 carte à fabriquer'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Ajouter 1 carte'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('occlusion-mode-hideOne')));
      await tester.pumpAndSettle();
      expect(
        find.text('2 zones · 1 groupe · 2 cartes à fabriquer'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Ajouter 2 cartes'),
        findsOneWidget,
      );

      // annuler la dernière zone
      await tester.tap(find.byKey(const ValueKey('occlusion-undo')));
      await tester.pumpAndSettle();
      expect(
        find.text('1 zone · 1 groupe · 1 carte à fabriquer'),
        findsOneWidget,
      );
      await draw(const Offset(0.60, 0.50), const Offset(0.25, 0.40));

      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter 2 cartes'));
      await tester.pumpAndSettle();

      final note = session.flashcards.notes(deck.id).single;
      expect(note.type, NoteType.occlusion);
      expect(note.cardCount, 2);
      expect(note.fields.occlusionMode, OcclusionMode.hideOne);
      expect(note.fields.masks, hasLength(2));
      final m = note.fields.masks.first;
      expect(m.left, closeTo(0.10, 0.01));
      expect(m.top, closeTo(0.10, 0.01));
      expect(m.width, closeTo(0.30, 0.01));
      expect(m.height, closeTo(0.30, 0.01));
      expect(session.media.exists(note.fields.image), isTrue);
      expect(note.fields.image, endsWith('.png'));

      // le formulaire est prêt pour une nouvelle image
      expect(find.byKey(const ValueKey('occlusion-pick')), findsOneWidget);
    });

    testWidgets(
      'la carte d\'occlusion est montrée à la révision, zones pleines puis en contour',
      (tester) async {
        final session = openTestSession();
        final deck = session.flashcards.createDeck('Anatomie');
        final name = session.media.addBytes(solidPng(200, 100), 'png');
        session.flashcards.addNote(
          deck.id,
          NoteType.occlusion,
          NoteFields({
            'image': name,
            'mode': 'hideOne',
            'masks': [
              {'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.2, 'g': 1, 'i': 1},
              {'x': 0.5, 'y': 0.5, 'w': 0.2, 'h': 0.2, 'g': 1, 'i': 2},
            ],
            'extra': 'Face antérieure',
          }),
        );
        await pumpFlash(tester, session);
        await tester.tap(find.byKey(ValueKey('review-deck-${deck.id}')));
        await tester.pumpAndSettle();
        // fenêtre « ordre de passage »
        expect(find.text('Dans quel ordre ?'), findsOneWidget);
        await tester.tap(find.text('Dans l\'ordre du cours'));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(OcclusionView), findsOneWidget);
        await waitFor(tester, find.byKey(const ValueKey('occlusion-masks')));
        expect(find.text('Face antérieure'), findsNothing);

        await tester.tap(find.text('Afficher la réponse'));
        await tester.pump();
        expect(find.byType(OcclusionView), findsOneWidget);
        await waitFor(tester, find.byKey(const ValueKey('occlusion-masks')));
        expect(find.text('Face antérieure'), findsOneWidget);
        expect(find.byKey(const ValueKey('grade-3')), findsOneWidget);
      },
    );
  });
}
