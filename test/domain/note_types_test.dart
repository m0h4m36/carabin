import 'package:carabin/domain/note_types.dart';
import 'package:flutter_test/flutter_test.dart';

NoteFields f(Map<String, Object?> m) => NoteFields(m);

void main() {
  group('trous', () {
    test('découpe un texte à trous avec indice', () {
      final parts = parseCloze('Le {{c1::cœur}} pompe le {{c2::sang::liquide}}.');
      expect(parts.map((p) => p.text), ['Le ', 'cœur', ' pompe le ', 'sang', '.']);
      expect(parts.where((p) => p.isCloze).map((p) => p.number), [1, 2]);
      expect(parts[3].hint, 'liquide');
    });

    test('numéros triés et sans doublon', () {
      expect(clozeNumbers('{{c2::a}} {{c1::b}} {{c2::c}}'), [1, 2]);
      expect(nextClozeNumber('{{c1::a}} {{c3::b}}'), 4);
      expect(nextClozeNumber('rien'), 1);
    });

    test('enveloppe une sélection', () {
      expect(wrapCloze('Le cœur bat', 3, 7, 1), 'Le {{c1::cœur}} bat');
    });

    test('un trou peut contenir un retour à la ligne', () {
      expect(clozeNumbers('{{c1::a\nb}}'), [1]);
    });
  });

  group('validation', () {
    test('texte à trous', () {
      expect(validateNote(NoteType.cloze, f({'text': ''})), NoteIssue.emptyFront);
      expect(validateNote(NoteType.cloze, f({'text': 'sans trou'})), NoteIssue.noCloze);
      expect(validateNote(NoteType.cloze, f({'text': '{{c1::a'})), NoteIssue.clozeNotClosed);
      expect(validateNote(NoteType.cloze, f({'text': '{{c1::a}}'})), isNull);
    });

    test('question-réponse', () {
      expect(validateNote(NoteType.basic, f({'front': '', 'back': 'x'})), NoteIssue.emptyFront);
      expect(validateNote(NoteType.basic, f({'front': 'q', 'back': ' '})), NoteIssue.emptyBack);
      expect(validateNote(NoteType.reversed, f({'front': 'q', 'back': 'r'})), isNull);
      expect(validateNote(NoteType.typed, f({'front': 'q', 'back': 'r'})), isNull);
    });

    test('occlusion', () {
      expect(validateNote(NoteType.occlusion, f({})), NoteIssue.noImage);
      expect(validateNote(NoteType.occlusion, f({'image': 'a.png'})), NoteIssue.noMask);
      expect(
        validateNote(NoteType.occlusion, f({'image': 'a.png', 'masks': [
          {'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.2},
        ]})),
        isNull,
      );
    });
  });

  group('cartes fabriquées', () {
    test('une carte par numéro de trou', () {
      expect(cardOrdinals(NoteType.cloze, f({'text': '{{c1::a}} {{c3::b}} {{c1::c}}'})), [1, 3]);
    });
    test('question-réponse : 1 ; réversible : 2 ; saisie : 1', () {
      expect(cardOrdinals(NoteType.basic, f({})), [0]);
      expect(cardOrdinals(NoteType.reversed, f({})), [0, 1]);
      expect(cardOrdinals(NoteType.typed, f({})), [0]);
    });
  });

  group('affichage', () {
    test('le trou actif est masqué à la question, révélé à la réponse', () {
      final fields = f({'text': 'Le {{c1::cœur}} et le {{c2::foie}}'});
      final q = renderFace(NoteType.cloze, fields, 1);
      expect(q.question.map((s) => s.role), contains(SegmentRole.hidden));
      expect(q.question.map((s) => s.text).join(), isNot(contains('cœur')));
      expect(q.question.map((s) => s.text).join(), contains('foie'));
      expect(q.answer.map((s) => s.role), contains(SegmentRole.revealed));
      expect(q.answer.map((s) => s.text).join(), contains('cœur'));
    });

    test('texte brut sans marques', () {
      expect(plainText(NoteType.cloze, f({'text': 'Le {{c1::**cœur**::organe}} bat'})), 'Le cœur bat');
      expect(plainText(NoteType.basic, f({'front': 'Q', 'back': 'R'})), 'Q — R');
      expect(plainText(NoteType.occlusion, f({'extra': ''})), '');
      expect(plainText(NoteType.occlusion, f({'extra': 'Coupe du cœur'})), 'Coupe du cœur');
    });
  });

  group('réponse saisie', () {
    test('ignore casse, accents, espaces et ponctuation finale', () {
      expect(typedAnswerMatches('  Œdème  ', 'oedème'), isTrue);
      expect(typedAnswerMatches('Aorte.', 'aorte'), isTrue);
      expect(typedAnswerMatches('', ''), isFalse);
      expect(typedAnswerMatches('veine', 'artère'), isFalse);
    });
  });

  group('mise en forme', () {
    test('gras, italique, souligné', () {
      final runs = parseRich('a **b** c');
      expect(runs.map((r) => r.text).join(), 'a b c');
      expect(runs.where((r) => r.bold).map((r) => r.text), ['b']);
    });
    test('marques non fermées restent du texte', () {
      expect(stripRich('2 * 3 = 6'), '2 * 3 = 6');
    });
  });
}
