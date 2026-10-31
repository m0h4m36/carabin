import 'dart:convert';
import 'dart:math' as math;

import 'exchange.dart';
import 'note_types.dart';
import 'scheduling.dart';

/// Nom de paquet Carabin d'après un nom Anki (`Parent::Enfant` dans les
/// anciennes versions, `Parent\x1fEnfant` dans les récentes).
String deckNameFromAnki(String name) => name
    .split(RegExp(r'::|\x1f'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .join(' › ');

// ----------------------------------------------------- occlusion d'image

/// Zones d'une note « Occlusion d'image » d'Anki.
class AnkiOcclusion {
  AnkiOcclusion(this.masks, {this.approximated = 0, this.dropped = 0});

  final List<OcclusionMask> masks;

  /// Formes qui ne sont pas des rectangles (ellipses, polygones) : remplacées
  /// par leur rectangle englobant.
  final int approximated;

  /// Formes impossibles à reprendre (texte, coordonnées illisibles).
  final int dropped;
}

final _occlusionCloze = RegExp(
  r'\{\{c(\d+)::image-occlusion:([A-Za-z]+):((?:(?!\}\}).)*)\}\}',
  dotAll: true,
);

/// Lit le champ « Occlusion » d'une note d'Anki :
/// `{{c1::image-occlusion:rect:left=.4:top=.3:width=.1:height=.1:oi=1}}`.
/// Les coordonnées sont des fractions de l'image. Le numéro du trou devient le
/// groupe de la zone (une carte par groupe).
AnkiOcclusion parseAnkiOcclusion(String field) {
  final masks = <OcclusionMask>[];
  var approximated = 0;
  var dropped = 0;
  for (final m in _occlusionCloze.allMatches(field)) {
    final group = int.parse(m.group(1)!);
    final kind = m.group(2)!.toLowerCase();
    final props = <String, String>{};
    for (final piece in m.group(3)!.split(':')) {
      final eq = piece.indexOf('=');
      if (eq > 0) {
        props[piece.substring(0, eq).trim()] = piece.substring(eq + 1).trim();
      }
    }
    double? num(String k) => double.tryParse(props[k] ?? '');

    double? left, top, width, height;
    var approx = false;
    switch (kind) {
      case 'rect':
        left = num('left');
        top = num('top');
        width = num('width');
        height = num('height');
      case 'ellipse':
        // `left` et `top` désignent le coin du rectangle englobant
        left = num('left');
        top = num('top');
        final rx = num('rx');
        final ry = num('ry');
        width = rx == null ? null : rx * 2;
        height = ry == null ? null : ry * 2;
        approx = true;
      case 'polygon':
        final box = _polygonBox(props['points'] ?? '');
        if (box != null) {
          left = box.left;
          top = box.top;
          width = box.width;
          height = box.height;
        }
        approx = true;
      default:
        break; // texte, etc.
    }
    final mask = _clampMask(left, top, width, height, group, masks.length + 1);
    if (mask == null) {
      dropped++;
      continue;
    }
    if (approx) approximated++;
    masks.add(mask);
  }
  return AnkiOcclusion(masks, approximated: approximated, dropped: dropped);
}

({double left, double top, double width, double height})? _polygonBox(
  String points,
) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  var n = 0;
  for (final pair in points.trim().split(RegExp(r'\s+'))) {
    final xy = pair.split(',');
    if (xy.length != 2) continue;
    final x = double.tryParse(xy[0]);
    final y = double.tryParse(xy[1]);
    if (x == null || y == null) continue;
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
    n++;
  }
  if (n < 2) return null;
  return (left: minX, top: minY, width: maxX - minX, height: maxY - minY);
}

/// Rectangle valide dans l'image, ou null si les nombres sont absents,
/// absurdes (coordonnées en pixels plutôt qu'en fractions) ou si la zone est
/// hors de l'image.
OcclusionMask? _clampMask(
  double? left,
  double? top,
  double? width,
  double? height,
  int group,
  int id,
) {
  if (left == null || top == null || width == null || height == null) {
    return null;
  }
  for (final v in [left, top, width, height]) {
    if (!v.isFinite || v < -0.01 || v > 1.01) return null;
  }
  final l = left.clamp(0.0, 1.0);
  final t = top.clamp(0.0, 1.0);
  final w = math.min(width, 1.0 - l);
  final h = math.min(height, 1.0 - t);
  if (w < 0.0005 || h < 0.0005) return null;
  return OcclusionMask(
    left: l,
    top: t,
    width: w,
    height: h,
    group: group,
    id: id,
  );
}

// ------------------------------------------------- avancement des cartes

/// Plus petite valeur d'« échéance » qu'Anki exprime en secondes depuis 1970
/// (en dessous, c'est un numéro de jour depuis la création de la collection).
const _secondsThreshold = 100000000;

/// Avancement d'une carte Anki converti pour FSRS, ou null si la carte est
/// neuve (ou en tout premier apprentissage : elle recommence à zéro).
///
/// - la stabilité vient de la mémoire FSRS d'Anki quand elle existe
///   (`data` : `{"s":…,"d":…}`), sinon c'est l'intervalle en jours (à 90 % de
///   rétention, intervalle et stabilité coïncident) ;
/// - la difficulté vient d'elle aussi, sinon du facteur de facilité SM-2
///   (2,5 → 5 ; 1,3 → 10 ; 3,5 et plus → 1) ;
/// - l'échéance est un jour relatif à la création de la collection
///   ([collectionCreatedSec]).
Schedule? scheduleFromAnki({
  required int type,
  required int due,
  required int ivl,
  required int factor,
  required int reps,
  required int lapses,
  required int collectionCreatedSec,
  required String dataJson,
  int? lastReviewMs,
}) {
  if (type != 2 && type != 3) return null;

  double? memoryS, memoryD;
  try {
    final j = jsonDecode(dataJson.isEmpty ? '{}' : dataJson);
    if (j is Map) {
      final s = j['s'], d = j['d'];
      if (s is num && s > 0 && s.isFinite) memoryS = s.toDouble();
      if (d is num && d >= 1 && d <= 10 && d.isFinite) memoryD = d.toDouble();
    }
  } on FormatException {
    // champ `data` illisible : on s'en passe
  }

  final days = ivl > 0 ? ivl.toDouble() : 1.0;
  final stability = (memoryS ?? days).clamp(0.01, 36500.0);
  final ease = (factor > 0 ? factor : 2500) / 1000.0;
  final difficulty = (memoryD ?? (11 - 5 * (ease - 1.3))).clamp(1.0, 10.0);

  final dueMs = due >= _secondsThreshold
      ? due * 1000
      : (collectionCreatedSec + due * 86400) * 1000;
  final last = lastReviewMs ?? (ivl > 0 ? dueMs - ivl * 86400000 : null);

  return Schedule(
    state: CardState.review,
    stability: stability,
    difficulty: difficulty,
    dueMs: dueMs,
    lastReviewMs: last,
    reps: math.max(reps, 1),
    lapses: math.max(lapses, 0),
  );
}

/// Une ligne de l'historique d'Anki (`revlog`).
class AnkiReview {
  const AnkiReview({
    required this.id,
    required this.ease,
    required this.ivl,
    required this.time,
    required this.type,
  });

  /// Heure de la réponse, en millisecondes depuis 1970.
  final int id;
  final int ease;

  /// Intervalle après la réponse : jours, ou secondes si négatif.
  final int ivl;

  /// Temps de réponse en millisecondes.
  final int time;

  /// 0 apprentissage, 1 révision, 2 réapprentissage, 3 filtré, 4 manuel.
  final int type;
}

/// Historique d'une carte converti, du plus ancien au plus récent. Les
/// reports manuels et les révisions « filtrées » sont écartés.
List<IncomingLog> logsFromAnki(List<AnkiReview> reviews) {
  final sorted = [...reviews]..sort((a, b) => a.id.compareTo(b.id));
  final out = <IncomingLog>[];
  const minTime = 946684800000; // 2000-01-01
  for (final r in sorted) {
    if (r.ease < 1 || r.ease > 4 || r.type < 0 || r.type > 2) continue;
    if (r.id < minTime) continue;
    final state = out.isEmpty && r.type == 0
        ? CardState.newCard
        : switch (r.type) {
            0 => CardState.learning,
            1 => CardState.review,
            _ => CardState.relearning,
          };
    out.add(
      IncomingLog(
        rating: r.ease,
        atMs: r.id,
        stateBefore: state,
        durationMs: r.time > 0 ? math.min(r.time, 3600000) : null,
        intervalDays: r.ivl > 0
            ? r.ivl.toDouble()
            : r.ivl < 0
            ? -r.ivl / 86400.0
            : null,
      ),
    );
  }
  return out;
}

// ------------------------------------------------------------ texte à trous

final _clozeToken = RegExp(r'\{\{c\d+::|\}\}');

/// Vrai si un trou en contient un autre (`{{c1::a {{c2::b}} c}}`), ce que le
/// texte à trous de Carabin ne représente pas.
bool hasNestedCloze(String text) {
  var depth = 0;
  for (final m in _clozeToken.allMatches(text)) {
    if (m.group(0) == '}}') {
      if (depth > 0) depth--;
    } else {
      depth++;
      if (depth > 1) return true;
    }
  }
  return false;
}
