import 'package:carabin/domain/anki_convert.dart';
import 'package:carabin/domain/scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deckNameFromAnki', () {
    test('hiérarchie ancienne et récente', () {
      expect(
        deckNameFromAnki('Cardio::Cœur::Valves'),
        'Cardio › Cœur › Valves',
      );
      expect(deckNameFromAnki('Cardio\x1fCœur'), 'Cardio › Cœur');
    });
    test('espaces et segments vides', () {
      expect(deckNameFromAnki('  A :: :: B  '), 'A › B');
      expect(deckNameFromAnki('Simple'), 'Simple');
      expect(deckNameFromAnki(''), '');
    });
  });

  group('parseAnkiOcclusion', () {
    test('rectangles groupés par numéro de trou', () {
      final r = parseAnkiOcclusion(
        '{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.1:oi=1}}<br>'
        '{{c2::image-occlusion:rect:left=.5:top=.5:width=.2:height=.2:oi=1}}<br>'
        '{{c1::image-occlusion:rect:left=.6:top=.1:width=.1:height=.1:oi=1}}',
      );
      expect(r.masks.length, 3);
      expect(r.masks.map((m) => m.group), [1, 2, 1]);
      expect(r.masks.map((m) => m.id), [1, 2, 3]);
      expect(r.masks[0].left, closeTo(0.1, 1e-9));
      expect(r.masks[0].width, closeTo(0.3, 1e-9));
      expect(r.approximated, 0);
      expect(r.dropped, 0);
    });

    test('ellipse : rectangle englobant', () {
      final r = parseAnkiOcclusion(
        '{{c1::image-occlusion:ellipse:left=.2:top=.3:rx=.1:ry=.05:oi=0}}',
      );
      expect(r.masks.single.left, closeTo(0.2, 1e-9));
      expect(r.masks.single.top, closeTo(0.3, 1e-9));
      expect(r.masks.single.width, closeTo(0.2, 1e-9));
      expect(r.masks.single.height, closeTo(0.1, 1e-9));
      expect(r.approximated, 1);
    });

    test('polygone : rectangle englobant', () {
      final r = parseAnkiOcclusion(
        '{{c3::image-occlusion:polygon:points=.1,.2 .4,.2 .3,.5:oi=1}}',
      );
      final m = r.masks.single;
      expect(m.group, 3);
      expect(m.left, closeTo(0.1, 1e-9));
      expect(m.top, closeTo(0.2, 1e-9));
      expect(m.width, closeTo(0.3, 1e-9));
      expect(m.height, closeTo(0.3, 1e-9));
      expect(r.approximated, 1);
    });

    test('texte, pixels et valeurs illisibles : écartés', () {
      final r = parseAnkiOcclusion(
        '{{c1::image-occlusion:text:left=.1:top=.1:text=bonjour:scale=1}}'
        '{{c1::image-occlusion:rect:left=120:top=40:width=300:height=80}}'
        '{{c1::image-occlusion:rect:left=abc:top=.1:width=.1:height=.1}}'
        '{{c1::image-occlusion:rect:left=.1:top=.1:width=0:height=.1}}'
        '{{c1::image-occlusion:polygon:points=.1,.1:oi=1}}'
        '{{c1::image-occlusion:rect:left=.1:top=.1:width=.1:height=.1}}',
      );
      expect(r.masks.length, 1);
      expect(r.dropped, 5);
      expect(r.approximated, 0);
    });

    test('rectangle qui dépasse : ramené dans l\'image', () {
      final r = parseAnkiOcclusion(
        '{{c1::image-occlusion:rect:left=.9:top=.9:width=.3:height=.3}}',
      );
      final m = r.masks.single;
      expect(m.left + m.width, lessThanOrEqualTo(1.0 + 1e-9));
      expect(m.top + m.height, lessThanOrEqualTo(1.0 + 1e-9));
    });

    test('rien à lire', () {
      final r = parseAnkiOcclusion('pas de masque ici');
      expect(r.masks, isEmpty);
      expect(r.dropped, 0);
    });
  });

  group('scheduleFromAnki', () {
    const crt = 1700000000; // secondes
    Schedule? conv({
      int type = 2,
      int due = 100,
      int ivl = 10,
      int factor = 2500,
      String data = '',
      int? last,
    }) => scheduleFromAnki(
      type: type,
      due: due,
      ivl: ivl,
      factor: factor,
      reps: 5,
      lapses: 1,
      collectionCreatedSec: crt,
      dataJson: data,
      lastReviewMs: last,
    );

    test('cartes neuves et en premier apprentissage : pas de progression', () {
      expect(conv(type: 0), isNull);
      expect(conv(type: 1), isNull);
    });

    test(
      'révision SM-2 : stabilité = intervalle, difficulté d\'après la facilité',
      () {
        final s = conv()!;
        expect(s.state, CardState.review);
        expect(s.stability, 10);
        expect(s.difficulty, closeTo(5, 1e-9)); // facilité 2,5
        expect(s.dueMs, (crt + 100 * 86400) * 1000);
        expect(s.lastReviewMs, s.dueMs - 10 * 86400000);
        expect(s.reps, 5);
        expect(s.lapses, 1);
      },
    );

    test('difficulté bornée entre 1 et 10', () {
      expect(conv(factor: 1300)!.difficulty, 10);
      expect(conv(factor: 1000)!.difficulty, 10);
      expect(conv(factor: 4000)!.difficulty, 1);
      expect(conv(factor: 0)!.difficulty, closeTo(5, 1e-9));
    });

    test('mémoire FSRS d\'Anki reprise', () {
      final s = conv(data: '{"s":42.5,"d":6.2,"dr":0.9}')!;
      expect(s.stability, 42.5);
      expect(s.difficulty, 6.2);
    });

    test('mémoire FSRS incohérente ou texte illisible : repli SM-2', () {
      expect(conv(data: '{"s":-3,"d":99}')!.stability, 10);
      expect(conv(data: '{"s":-3,"d":99}')!.difficulty, closeTo(5, 1e-9));
      expect(conv(data: 'pas du json')!.stability, 10);
      expect(conv(data: '[1,2]')!.stability, 10);
    });

    test('échéance en secondes (réapprentissage)', () {
      final s = conv(type: 3, due: 1760000000, ivl: 3)!;
      expect(s.dueMs, 1760000000 * 1000);
      expect(s.state, CardState.review);
    });

    test('dernière révision connue prioritaire', () {
      expect(conv(last: 12345)!.lastReviewMs, 12345);
    });

    test('intervalle nul : stabilité minimale d\'un jour', () {
      final s = conv(ivl: 0)!;
      expect(s.stability, 1);
      expect(s.lastReviewMs, isNull);
    });
  });

  group('logsFromAnki', () {
    const t0 = 1700000000000;
    test('ordre chronologique, première réponse = carte neuve', () {
      final logs = logsFromAnki([
        const AnkiReview(id: t0 + 2000, ease: 3, ivl: 4, time: 5000, type: 1),
        const AnkiReview(id: t0, ease: 1, ivl: -600, time: 3000, type: 0),
        const AnkiReview(id: t0 + 1000, ease: 3, ivl: 1, time: 2000, type: 0),
      ]);
      expect(logs.map((l) => l.atMs), [t0, t0 + 1000, t0 + 2000]);
      expect(logs.map((l) => l.stateBefore), [
        CardState.newCard,
        CardState.learning,
        CardState.review,
      ]);
      expect(logs[0].intervalDays, closeTo(600 / 86400, 1e-12));
      expect(logs[1].intervalDays, 1);
      expect(logs[0].durationMs, 3000);
    });

    test('reports manuels, révisions filtrées et valeurs absurdes écartés', () {
      final logs = logsFromAnki([
        const AnkiReview(id: t0, ease: 0, ivl: 5, time: 0, type: 4),
        const AnkiReview(id: t0 + 1, ease: 3, ivl: 5, time: 0, type: 3),
        const AnkiReview(id: t0 + 2, ease: 5, ivl: 5, time: 0, type: 1),
        const AnkiReview(id: 1000, ease: 3, ivl: 5, time: 0, type: 1),
        const AnkiReview(id: t0 + 3, ease: 2, ivl: 0, time: 9999999, type: 2),
      ]);
      expect(logs.length, 1);
      expect(logs.single.stateBefore, CardState.relearning);
      expect(logs.single.durationMs, 3600000);
      expect(logs.single.intervalDays, isNull);
    });
  });

  group('hasNestedCloze', () {
    test('trous à plat', () {
      expect(hasNestedCloze('Le {{c1::cœur}} bat {{c2::vite}}'), isFalse);
      expect(hasNestedCloze('{{c1::a::indice}}'), isFalse);
      expect(hasNestedCloze('sans trou'), isFalse);
    });
    test('trou dans un trou', () {
      expect(hasNestedCloze('{{c1::a {{c2::b}} c}}'), isTrue);
    });
    test('accolades fermantes en trop ou trou non fermé', () {
      expect(hasNestedCloze('}} {{c1::a}}'), isFalse);
      expect(hasNestedCloze('{{c1::a {{c2::b'), isTrue);
    });
  });
}
