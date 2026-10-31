import 'dart:io';
import 'dart:typed_data';

import 'package:carabin/app.dart';
import 'package:carabin/app_session.dart';
import 'package:carabin/data/background.dart';
import 'package:carabin/data/carabin_package.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:carabin/ui/pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_session.dart';

Future<void> pumpFlash(WidgetTester tester, Session session) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CarabinApp(session: session));
  await tester.tap(find.text('Flashcards').first);
  await tester.pumpAndSettle();
}

String writeFile(String name, String content) {
  final dir = Directory.systemTemp.createTempSync('carabin_imp_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final f = File(p.join(dir.path, name))..writeAsStringSync(content);
  return f.path;
}

Future<void> openImport(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus d\'actions').first);
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(PopupMenuItem<String>, 'Importer des cartes…'),
  );
  await tester.pumpAndSettle();
}

void main() {
  final originalFile = Pickers.file;
  final originalSave = Pickers.save;
  final originalRun = Background.run;

  setUp(() {
    // pas d'isolat dans les tests : on exécute le travail tout de suite
    Background.run = <T>(job) async => await job();
  });
  tearDown(() {
    Pickers.file = originalFile;
    Pickers.save = originalSave;
    Background.run = originalRun;
  });

  group('fichier texte', () {
    const csv =
        'Question;Réponse;Tags\nAorte;Naît du VG;anat\nVeine cave;Rejoint l\'OD;anat veines\n';

    testWidgets('colonnes reconnues, aperçu, import et compte rendu', (
      tester,
    ) async {
      final session = openTestSession();
      final path = writeFile('Cardio.csv', csv);
      Pickers.file = (_) async => path;
      await pumpFlash(tester, session);
      await openImport(tester);

      expect(find.text('Importer un fichier texte'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('rows-summary'))).data,
        '2 notes prêtes',
      );
      // le deck proposé porte le nom du fichier
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('target-deck')))
            .controller!
            .text,
        'Cardio',
      );
      await tester.tap(find.byKey(const ValueKey('text-import-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Import terminé'), findsOneWidget);
      expect(find.text('2 notes ajoutées'), findsOneWidget);
      expect(find.text('1 deck créé'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-report-close')));
      await tester.pumpAndSettle();

      final deck = session.flashcards.decks().single;
      expect(deck.name, 'Cardio');
      final notes = session.flashcards.notes(deck.id);
      expect(notes.length, 2);
      expect(
        notes.map((n) => n.fields.text('front')),
        containsAll(['Aorte', 'Veine cave']),
      );
      expect(notes.expand((n) => n.tags).toSet(), {'anat', 'veines'});
      expect(session.flashcards.counts().total, 2);
    });

    testWidgets('réimporter le même fichier ne duplique rien', (tester) async {
      final session = openTestSession();
      final path = writeFile('Cardio.csv', csv);
      Pickers.file = (_) async => path;
      await pumpFlash(tester, session);
      for (var i = 0; i < 2; i++) {
        await openImport(tester);
        await tester.tap(find.byKey(const ValueKey('text-import-confirm')));
        await tester.pumpAndSettle();
        if (i == 1) {
          expect(
            find.text('Rien de nouveau : ces cartes étaient déjà présentes.'),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(const ValueKey('import-report-close')));
        await tester.pumpAndSettle();
      }
      expect(
        session.flashcards.notes(session.flashcards.decks().single.id).length,
        2,
      );
    });

    testWidgets('changer de type : texte à trous sans trou = rien à importer', (
      tester,
    ) async {
      final session = openTestSession();
      Pickers.file = (_) async => writeFile('x.csv', csv);
      await pumpFlash(tester, session);
      await openImport(tester);

      await tester.tap(find.byKey(const ValueKey('type-basic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Texte à trous').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('rows-summary'))).data,
        '0 note prête · 2 lignes ignorées (contenu incomplet)',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('text-import-confirm')),
            )
            .onPressed,
        isNull,
      );
      // annuler ne crée rien
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(session.flashcards.decks(), isEmpty);
    });

    testWidgets('sans titres : la première ligne est une note', (tester) async {
      final session = openTestSession();
      Pickers.file = (_) async => writeFile('y.tsv', 'a\tb\nc\td\n');
      await pumpFlash(tester, session);
      await openImport(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('rows-summary'))).data,
        '2 notes prêtes',
      );
      // cocher « titres » retire une ligne
      await tester.tap(find.byKey(const ValueKey('header-switch')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('rows-summary'))).data,
        '1 note prête',
      );
    });

    testWidgets('fichier vide : message clair', (tester) async {
      final session = openTestSession();
      Pickers.file = (_) async => writeFile('vide.csv', '\n\n');
      await pumpFlash(tester, session);
      await openImport(tester);
      expect(find.textContaining('Aucune colonne exploitable'), findsOneWidget);
      expect(session.flashcards.decks(), isEmpty);
    });
  });

  group('autres fichiers', () {
    testWidgets('type inconnu', (tester) async {
      final session = openTestSession();
      Pickers.file = (_) async => writeFile('notes.pdf', 'x');
      await pumpFlash(tester, session);
      await openImport(tester);
      expect(
        find.textContaining('Ce type de fichier n\'est pas reconnu'),
        findsOneWidget,
      );
    });

    testWidgets('paquet Anki abîmé', (tester) async {
      final session = openTestSession();
      Pickers.file = (_) async => writeFile('abime.apkg', 'pas un zip');
      await pumpFlash(tester, session);
      await openImport(tester);
      expect(find.textContaining('n\'a pas pu être lu'), findsOneWidget);
      expect(session.flashcards.decks(), isEmpty);
    });

    testWidgets('annuler le choix du fichier', (tester) async {
      final session = openTestSession();
      Pickers.file = (_) async => null;
      await pumpFlash(tester, session);
      await openImport(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('paquet Anki', () {
    testWidgets('import avec progression, puis réimport sans rien dupliquer', (
      tester,
    ) async {
      final session = openTestSession();
      Pickers.file = (_) async => 'test/fixtures/anki_latest.apkg';
      await pumpFlash(tester, session);
      await openImport(tester);

      expect(find.text('Reprendre la progression ?'), findsOneWidget);
      await tester.tap(find.text('Reprendre la progression'));
      await tester.pumpAndSettle();

      expect(find.text('Import terminé'), findsOneWidget);
      expect(find.textContaining('notes ajoutées'), findsOneWidget);
      expect(find.textContaining('2 notes ignorées'), findsOneWidget);
      expect(find.textContaining('1 son ou vidéo ignoré'), findsOneWidget);
      expect(
        find.textContaining('1 zone d\'occlusion remplacée'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('import-report-close')));
      await tester.pumpAndSettle();

      final decks = session.flashcards.decks();
      expect(decks.map((d) => d.name).toSet(), {'Cardio › Cœur', 'Par défaut'});

      final cardio = decks.firstWhere((d) => d.name == 'Cardio › Cœur');
      final reversed = session.flashcards
          .notes(cardio.id)
          .firstWhere((n) => n.guid == 'anki-guidRevers02');
      final cards = session.flashcards.cardsOfNote(reversed.id);
      expect(cards.length, 2);
      final c0 = cards.firstWhere((c) => c.ord == 0);
      expect(c0.schedule.state, CardState.review);
      expect(c0.schedule.stability, 31.5);
      expect(cards.firstWhere((c) => c.ord == 1).suspended, isTrue);
      expect(
        session.db.select(
          'SELECT COUNT(*) AS n FROM review_logs WHERE card_id = ?',
          [c0.id],
        ).first['n'],
        3,
      );

      final occlusion = session.flashcards
          .notes(cardio.id)
          .firstWhere((n) => n.type == NoteType.occlusion);
      expect(session.media.exists(occlusion.fields.image), isTrue);
      expect(session.flashcards.cardsOfNote(occlusion.id).length, 2);

      // réimport : plus rien de nouveau
      final before = session.flashcards.counts().total;
      await openImport(tester);
      await tester.tap(find.text('Cartes seules'));
      await tester.pumpAndSettle();
      expect(
        find.text('Rien de nouveau : ces cartes étaient déjà présentes.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('import-report-close')));
      await tester.pumpAndSettle();
      expect(session.flashcards.counts().total, before);
    });

    testWidgets('sans reprendre la progression : cartes neuves', (
      tester,
    ) async {
      final session = openTestSession();
      Pickers.file = (_) async => 'test/fixtures/anki_latest.apkg';
      await pumpFlash(tester, session);
      await openImport(tester);
      await tester.tap(find.text('Cartes seules'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-report-close')));
      await tester.pumpAndSettle();

      final cardio = session.flashcards.decks().firstWhere(
        (d) => d.name == 'Cardio › Cœur',
      );
      final reversed = session.flashcards
          .notes(cardio.id)
          .firstWhere((n) => n.guid == 'anki-guidRevers02');
      for (final c in session.flashcards.cardsOfNote(reversed.id)) {
        expect(c.schedule.state, CardState.newCard);
        expect(c.suspended, isFalse);
      }
    });

    testWidgets('fermer la question sur la progression n\'importe rien', (
      tester,
    ) async {
      final session = openTestSession();
      Pickers.file = (_) async => 'test/fixtures/anki_latest.apkg';
      await pumpFlash(tester, session);
      await openImport(tester);
      await tester.tapAt(const Offset(5, 5)); // en dehors de la fenêtre
      await tester.pumpAndSettle();
      expect(session.flashcards.decks(), isEmpty);
    });
  });

  group('export', () {
    NoteFields qa(String q, String a) => NoteFields({'front': q, 'back': a});

    testWidgets('partager un deck : fichier sans progression', (tester) async {
      final session = openTestSession();
      final deck = session.flashcards.createDeck('Cardio / cœur');
      final n = session.flashcards.addNote(
        deck.id,
        NoteType.basic,
        qa('Q', 'R'),
      );
      final card = session.flashcards.cardsOfNote(n.id).single;
      session.flashcards.answer(card.id, Grade.good);

      String? savedName;
      Uint8List? saved;
      Pickers.save = (name, bytes) async {
        savedName = name;
        saved = bytes;
        return true;
      };
      await pumpFlash(tester, session);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('menu-deck-${deck.id}')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(ValueKey('menu-deck-${deck.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partager ce deck'));
      await tester.pumpAndSettle();

      expect(savedName, 'Cardio _ cœur.carabin');
      expect(find.textContaining('Fichier enregistré'), findsOneWidget);
      final file = File(
        p.join(
          Directory.systemTemp.createTempSync('carabin_exp_').path,
          'x.carabin',
        ),
      )..writeAsBytesSync(saved!);
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final parsed = readCarabinPackage(
        file.path,
        p.join(file.parent.path, 'media'),
      );
      expect(parsed.hasProgress, isFalse);
      expect(parsed.decks.single.name, 'Cardio / cœur');
      expect(parsed.decks.single.notes.single.fields.text('front'), 'Q');
      expect(parsed.decks.single.notes.single.cards, isEmpty);
      // pas de réglages propres : rien à transmettre
      expect(parsed.decks.single.options, isNull);
    });

    testWidgets('exporter avec la progression', (tester) async {
      final session = openTestSession();
      final deck = session.flashcards.createDeck('Neuro');
      final n = session.flashcards.addNote(
        deck.id,
        NoteType.basic,
        qa('Q', 'R'),
      );
      session.flashcards.answer(
        session.flashcards.cardsOfNote(n.id).single.id,
        Grade.good,
      );

      Uint8List? saved;
      Pickers.save = (name, bytes) async {
        saved = bytes;
        return true;
      };
      await pumpFlash(tester, session);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('menu-deck-${deck.id}')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(ValueKey('menu-deck-${deck.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exporter avec la progression'));
      await tester.pumpAndSettle();

      final dir = Directory.systemTemp.createTempSync('carabin_exp_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'x.carabin'))
        ..writeAsBytesSync(saved!);
      final parsed = readCarabinPackage(file.path, p.join(dir.path, 'media'));
      expect(parsed.hasProgress, isTrue);
      final card = parsed.decks.single.notes.single.cards.single;
      expect(card.schedule.lastReviewMs, isNotNull);
      expect(card.logs.length, 1);
    });

    testWidgets('tout exporter, puis annuler l\'enregistrement', (
      tester,
    ) async {
      final session = openTestSession();
      session.flashcards.addNote(
        session.flashcards.createDeck('A').id,
        NoteType.basic,
        qa('Q', 'R'),
      );
      session.flashcards.addNote(
        session.flashcards.createDeck('B').id,
        NoteType.basic,
        qa('Q2', 'R2'),
      );
      Uint8List? saved;
      var calls = 0;
      Pickers.save = (name, bytes) async {
        calls++;
        saved = bytes;
        return false; // l'utilisateur annule
      };
      await pumpFlash(tester, session);
      await tester.tap(find.byTooltip('Plus d\'actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exporter toute la progression'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.textContaining('Fichier enregistré'), findsNothing);
      final dir = Directory.systemTemp.createTempSync('carabin_exp_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'x.carabin'))
        ..writeAsBytesSync(saved!);
      final parsed = readCarabinPackage(file.path, p.join(dir.path, 'media'));
      expect(parsed.decks.map((d) => d.name).toSet(), {'A', 'B'});
    });
  });
}
