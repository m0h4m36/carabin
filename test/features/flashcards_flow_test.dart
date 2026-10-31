import 'package:carabin/app.dart';
import 'package:carabin/app_session.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_session.dart';

Finder dialogField() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

Future<void> pumpFlash(
  WidgetTester tester,
  Session session, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CarabinApp(session: session));
  await tester.tap(find.text('Flashcards').first);
  await tester.pumpAndSettle();
}

NoteFields basic(String q, String a) => NoteFields({'front': q, 'back': a});

void main() {
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    group('accueil ($size)', () {
      testWidgets('aucun deck : invitation, puis création', (tester) async {
        final session = openTestSession();
        await pumpFlash(tester, session, size: size);

        expect(find.text('Aucun deck pour l\'instant'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Nouveau deck'));
        await tester.pumpAndSettle();
        await tester.enterText(dialogField().first, 'Anatomie');
        await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
        await tester.pumpAndSettle();

        expect(session.flashcards.decks().single.name, 'Anatomie');
        await tester.scrollUntilVisible(find.text('Anatomie'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text('Anatomie'), findsWidgets);
        expect(find.text('Aucun deck pour l\'instant'), findsNothing);
      });

      testWidgets('compteurs et liste des decks', (tester) async {
        final session = openTestSession();
        final a = session.flashcards.createDeck('Cardio');
        final b = session.flashcards.createDeck('Neuro');
        for (var i = 0; i < 3; i++) {
          session.flashcards.addNote(a.id, NoteType.basic, basic('Q$i', 'R$i'));
        }
        session.flashcards.addNote(b.id, NoteType.basic, basic('N', 'R'));
        await pumpFlash(tester, session, size: size);

        expect(find.text('2 decks · 4 cartes'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Neuro'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text('Cardio'), findsWidgets);
        expect(find.text('Neuro'), findsWidgets);
        // 4 nouvelles aujourd'hui
        expect(find.descendant(of: find.byKey(const ValueKey('counter-today')), matching: find.text('4')), findsOneWidget);

        // recherche
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('deck-search')), 'neu');
        await tester.pumpAndSettle();
        expect(find.text('Cardio'), findsNothing);
        await tester.scrollUntilVisible(find.text('Neuro'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text('Neuro'), findsWidgets);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('deck-search')), 'zzz');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Aucun deck ne correspond.'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text('Aucun deck ne correspond.'), findsOneWidget);
      });
    });
  }

  group('éditeur', () {
    testWidgets('ajoute un texte à trous, le compteur et les cartes suivent', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      await pumpFlash(tester, session);

      await tester.tap(find.byKey(ValueKey('menu-deck-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle carte').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Texte'),
        'Le {{c1::cœur}} pompe le {{c2::sang}}.',
      );
      await tester.pumpAndSettle();
      expect(find.text('Aperçu'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();

      final notes = session.flashcards.notes(d.id);
      expect(notes, hasLength(1));
      expect(notes.single.cardCount, 2);
      expect(find.text('2 cartes créées pendant cette séance'), findsOneWidget);
      // le champ est vidé pour la carte suivante
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Texte')).controller!.text, isEmpty);
    });

    testWidgets('le bouton Trou enveloppe la sélection puis passe au numéro suivant', (tester) async {
      final session = openTestSession();
      session.flashcards.createDeck('Cardio');
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(ValueKey('menu-deck-${session.flashcards.decks().single.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle carte').last);
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, 'Texte');
      await tester.enterText(field, 'abc def ghi');
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
      await tester.tap(find.widgetWithText(FilledButton, 'Trou'));
      await tester.pumpAndSettle();
      expect(controller.text, 'abc {{c1::def}} ghi');
      expect(find.text('c2'), findsOneWidget);

      controller.selection = const TextSelection(baseOffset: 16, extentOffset: 19);
      await tester.tap(find.widgetWithText(FilledButton, 'Trou'));
      await tester.pumpAndSettle();
      expect(controller.text, 'abc {{c1::def}} {{c2::ghi}}');
    });

    testWidgets('sans sélection : message ; carte invalide : erreur', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(ValueKey('menu-deck-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle carte').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Texte'), 'sans trou');
      await tester.tap(find.widgetWithText(FilledButton, 'Trou'));
      await tester.pump();
      expect(find.text('Sélectionnez d\'abord le texte à masquer.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Il faut au moins un trou'), findsOneWidget);
      expect(session.flashcards.notes(d.id), isEmpty);
    });

    testWidgets('question-réponse, puis modification', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(ValueKey('menu-deck-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouvelle carte').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Question-réponse'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Recto'), 'Capitale de la France ?');
      await tester.enterText(find.widgetWithText(TextField, 'Verso'), 'Paris');
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      final note = session.flashcards.notes(d.id).single;
      expect(note.fields.text('back'), 'Paris');

      // doublon : confirmation demandée
      await tester.enterText(find.widgetWithText(TextField, 'Recto'), 'Capitale de la France ?');
      await tester.enterText(find.widgetWithText(TextField, 'Verso'), 'Paris');
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Carte en double ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();
      expect(session.flashcards.notes(d.id), hasLength(1));
    });
  });

  group('révision', () {
    testWidgets('afficher la réponse, délais sous les boutons, puis écran de fin', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      session.flashcards.addNote(d.id, NoteType.basic, basic('Q1', 'R1'));
      session.flashcards.addNote(d.id, NoteType.basic, basic('Q2', 'R2'));
      await pumpFlash(tester, session);

      await tester.tap(find.byKey(ValueKey('review-deck-${d.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Dans quel ordre ?'), findsOneWidget);
      await tester.tap(find.text('Comme d\'habitude'));
      await tester.pumpAndSettle();

      expect(find.text('Afficher la réponse'), findsOneWidget);
      expect(find.textContaining('première fois'), findsOneWidget);
      await tester.tap(find.text('Afficher la réponse'));
      await tester.pumpAndSettle();
      for (final t in ['Encore', 'Difficile', 'Bien', 'Facile', '1 min', '10 min']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      await tester.tap(find.byKey(const ValueKey('grade-4')));
      await tester.pumpAndSettle();

      // deuxième carte : réponse au clavier (espace puis 4)
      expect(find.text('Afficher la réponse'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Facile'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();

      expect(find.text('Terminé'), findsOneWidget);
      expect(find.textContaining('2 cartes révisées'), findsOneWidget);
      expect(find.text('Réviser à nouveau'), findsOneWidget);
      expect(session.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'], 2);

      // annuler la dernière depuis l'écran de fin
      await tester.tap(find.text('Annuler la dernière réponse'));
      await tester.pumpAndSettle();
      expect(find.text('Terminé'), findsNothing);
      expect(session.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'], 1);
    });

    testWidgets('« Encore » : la carte revient dans la séance', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      session.flashcards.addNote(d.id, NoteType.basic, basic('Q1', 'R1'));
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(const ValueKey('review-all')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(find.text('Terminé'), findsNothing);
      expect(find.text('Afficher la réponse'), findsOneWidget);
      expect(find.textContaining('vue 1 fois'), findsOneWidget);
    });

    testWidgets('carte à saisie : bonne réponse reconnue', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      session.flashcards.addNote(d.id, NoteType.typed, basic('Organe qui pompe le sang ?', 'Cœur'));
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(const ValueKey('review-all')));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Tapez votre réponse'), ' coeur ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Bonne réponse'), findsOneWidget);
    });

    testWidgets('mettre de côté et supprimer (avec confirmation)', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      final n1 = session.flashcards.addNote(d.id, NoteType.basic, basic('Q1', 'R1'));
      final n2 = session.flashcards.addNote(d.id, NoteType.basic, basic('Q2', 'R2'));
      session.flashcards.setDeckOptions(d.id, null);
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(const ValueKey('review-all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mettre la carte de côté (S)'));
      await tester.pumpAndSettle();
      final suspended = [
        for (final n in [n1, n2]) session.flashcards.note(n.id).allSuspended,
      ];
      expect(suspended.where((s) => s), hasLength(1));

      await tester.tap(find.byTooltip('Supprimer la carte (Ctrl+Suppr)'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer la carte'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(session.flashcards.notes(d.id), hasLength(1));
      expect(find.text('Terminé'), findsOneWidget);
    });
  });

  group('cartes d\'un deck', () {
    testWidgets('liste, recherche, pause, suppression', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      session.flashcards.addNote(d.id, NoteType.basic, basic('Aorte', 'Artère'));
      session.flashcards.addNote(d.id, NoteType.cloze, NoteFields({'text': 'Le {{c1::cœur}} bat'}));
      await pumpFlash(tester, session);

      await tester.tap(find.byKey(ValueKey('menu-deck-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir les cartes'));
      await tester.pumpAndSettle();

      expect(find.text('Cardio · 2 notes · 2 cartes'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'aorte');
      await tester.pumpAndSettle();
      expect(find.textContaining('Aorte'), findsWidgets);
      expect(find.textContaining('Le cœur bat'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Le cœur bat').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mettre en pause'));
      await tester.pumpAndSettle();
      final cloze = session.flashcards.notes(d.id).firstWhere((n) => n.type == NoteType.cloze);
      expect(cloze.allSuspended, isTrue);
      expect(find.text('Rétablir'), findsOneWidget);

      await tester.tap(find.byTooltip('Supprimer la note'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(session.flashcards.notes(d.id), hasLength(1));
    });
  });

  group('s\'entraîner', () {
    testWidgets('se tester : note sur 20, rien n\'est reprogrammé, historique', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      for (var i = 1; i <= 4; i++) {
        session.flashcards.addNote(d.id, NoteType.basic, basic('Q$i', 'R$i'));
      }
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(const ValueKey('open-practice')));
      await tester.pumpAndSettle();

      // rien de coché : le bouton est grisé
      final start = find.widgetWithText(FilledButton, 'Réviser');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);

      await tester.tap(find.byKey(ValueKey('practice-deck-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se tester'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Se tester'));
      await tester.pumpAndSettle();

      // 3 justes sur 4
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('test-reveal')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(i == 0 ? 'test-no' : 'test-yes')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('test-score')), findsOneWidget);
      expect(find.text('15 / 20'), findsOneWidget);
      expect(find.text('3 justes sur 4 · 75 %'), findsOneWidget);
      expect(find.textContaining('Rien n\'a été reprogrammé'), findsOneWidget);

      expect(session.flashcards.practiceHistory().single.correct, 3);
      expect(session.flashcards.counts().newToday, 4);
      expect(session.db.select('SELECT COUNT(*) AS n FROM review_logs').first['n'], 0);

      await tester.tap(find.text('Voir l\'historique'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 / 4'), findsOneWidget);
      expect(find.text('15 / 20'), findsOneWidget);
    });
  });

  group('réglages d\'étude', () {
    testWidgets('généraux : plafond, exigence et retour aux valeurs par défaut', (tester) async {
      final session = openTestSession();
      session.flashcards.createDeck('Cardio');
      await pumpFlash(tester, session);

      await tester.tap(find.byTooltip('Plus d\'actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réglages d\'étude'));
      await tester.pumpAndSettle();

      expect(find.text('90 %'), findsOneWidget);
      expect(find.textContaining('J+4, J+18, J+63, J+198'), findsOneWidget);
      expect(find.textContaining('≈ 100 révisions par jour'), findsOneWidget);

      // « sans plafond » pour les nouvelles
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(session.flashcards.globalOptions().newPerDay, isNull);

      // exigence de mémorisation 97 %
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(session.flashcards.globalOptions().retention, 0.97);

      await tester.scrollUntilVisible(find.text('Revenir aux valeurs par défaut'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Revenir aux valeurs par défaut'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pumpAndSettle();
      expect(session.flashcards.globalOptions().retention, 0.9);
      expect(session.flashcards.globalOptions().newPerDay, 20);
    });

    testWidgets('propres à un deck', (tester) async {
      final session = openTestSession();
      final d = session.flashcards.createDeck('Cardio');
      await pumpFlash(tester, session);
      await tester.tap(find.byKey(ValueKey('menu-deck-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réglages d\'étude').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('suit les réglages généraux'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(session.flashcards.deckOptions(d.id), isNotNull);
      expect(find.textContaining('le plus strict l\'emporte'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(session.flashcards.deckOptions(d.id), isNull);
    });
  });

  testWidgets('ranger un deck dans une matière', (tester) async {
    final session = openTestSession();
    final y = session.courses.createYear('DFGSM2');
    final s = session.courses.createSemester(y.id, 'S3');
    final m = session.courses.createSubject(s.id, 'Anatomie', color: 0xFFE53935);
    final d = session.flashcards.createDeck('Ostéo');
    await pumpFlash(tester, session);

    expect(find.text('Sans matière'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('menu-deck-${d.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer de matière'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anatomie').last);
    await tester.pumpAndSettle();
    expect(session.flashcards.deck(d.id).subjectId, m.id);
    expect(find.text('Sans matière'), findsNothing);
  });

  test('toute carte neuve répondue « Facile » sort de l\'apprentissage', () {
    final session = openTestSession();
    final d = session.flashcards.createDeck('X');
    final n = session.flashcards.addNote(d.id, NoteType.basic, basic('Q', 'R'));
    final c = session.flashcards.cardsOfNote(n.id).single;
    session.flashcards.answer(c.id, Grade.easy);
    expect(session.flashcards.card(c.id).schedule.state, CardState.review);
  });
}
