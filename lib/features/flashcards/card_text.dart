import 'package:flutter/material.dart';

import '../../domain/note_types.dart';

const _open = '';
const _close = '';
final _placeholder = RegExp('$_open(\\d+)$_close');

/// Texte mis en forme (gras, italique…) d'un champ de carte.
List<InlineSpan> richSpans(String text, TextStyle base, ColorScheme scheme) {
  return [
    for (final run in parseRich(text))
      if (run.text.isNotEmpty) _runSpan(run, base, scheme),
  ];
}

TextSpan _runSpan(RichRun run, TextStyle base, ColorScheme scheme, [TextStyle? extra]) {
  var style = base;
  if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
  if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
  if (run.underline) style = style.copyWith(decoration: TextDecoration.underline);
  if (run.highlight) {
    style = style.copyWith(
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onTertiaryContainer,
    );
  }
  if (extra != null) style = style.merge(extra);
  return TextSpan(text: run.text, style: style);
}

/// Segments d'une face de carte (texte normal, trou masqué, trou révélé),
/// avec la mise en forme qui peut enjamber un trou (`**{{c1::mot}}**`).
List<InlineSpan> faceSpans(
  List<FaceSegment> segments,
  TextStyle base,
  ColorScheme scheme,
) {
  final special = <int, FaceSegment>{};
  final buffer = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    if (s.role == SegmentRole.normal) {
      buffer.write(s.text);
    } else {
      special[i] = s;
      buffer.write('$_open$i$_close');
    }
  }
  final spans = <InlineSpan>[];
  for (final run in parseRich(buffer.toString())) {
    var last = 0;
    for (final m in _placeholder.allMatches(run.text)) {
      if (m.start > last) {
        spans.add(_runSpan(RichRun(run.text.substring(last, m.start),
            bold: run.bold, italic: run.italic, underline: run.underline, highlight: run.highlight), base, scheme));
      }
      final seg = special[int.parse(m.group(1)!)]!;
      spans.add(_clozeSpan(seg, run, base, scheme));
      last = m.end;
    }
    if (last < run.text.length) {
      spans.add(_runSpan(RichRun(run.text.substring(last),
          bold: run.bold, italic: run.italic, underline: run.underline, highlight: run.highlight), base, scheme));
    }
  }
  return spans;
}

InlineSpan _clozeSpan(FaceSegment seg, RichRun outer, TextStyle base, ColorScheme scheme) {
  final hidden = seg.role == SegmentRole.hidden;
  final accent = scheme.primary;
  final extra = TextStyle(
    color: accent,
    fontWeight: FontWeight.w700,
    backgroundColor: hidden ? scheme.primaryContainer : null,
  );
  final inner = parseRich(seg.text);
  return TextSpan(children: [
    for (final r in inner)
      if (r.text.isNotEmpty)
        _runSpan(
          RichRun(r.text,
              bold: r.bold || outer.bold,
              italic: r.italic || outer.italic,
              underline: r.underline || outer.underline,
              highlight: false),
          base,
          scheme,
          extra,
        ),
  ]);
}

/// Une face de carte (question ou réponse), centrée et lisible.
class FaceText extends StatelessWidget {
  const FaceText(this.segments, {super.key, this.style, this.textAlign = TextAlign.center});
  final List<FaceSegment> segments;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400, height: 1.5) ?? const TextStyle();
    return Text.rich(
      TextSpan(children: faceSpans(segments, base, theme.colorScheme)),
      textAlign: textAlign,
    );
  }
}

/// Un champ libre (complément, contexte) en texte mis en forme.
class RichFieldText extends StatelessWidget {
  const RichFieldText(this.text, {super.key, this.style, this.textAlign = TextAlign.start});
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    return Text.rich(
      TextSpan(children: richSpans(text, base, theme.colorScheme)),
      textAlign: textAlign,
    );
  }
}
