import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/qcm/question.dart';
import '../../l10n/textes_qcm.dart';
import '../flashcards/masked_image.dart';

/// Dessin des zones-réponses d'un QZP sur son image.
class ZoneEditor extends StatefulWidget {
  const ZoneEditor({
    super.key,
    required this.image,
    required this.zones,
    required this.onChanged,
  });

  final String image;
  final List<Zone> zones;
  final ValueChanged<List<Zone>> onChanged;

  @override
  State<ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<ZoneEditor> {
  int? _selected;
  Offset? _start;
  Rect? _drag;

  /// Plus petite zone gardée, en fraction de l'image.
  static const _minSize = 0.01;

  void _end(Size size) {
    final r = _drag;
    _start = null;
    _drag = null;
    if (r == null) return;
    final left = (r.left / size.width).clamp(0.0, 1.0);
    final top = (r.top / size.height).clamp(0.0, 1.0);
    final right = (r.right / size.width).clamp(0.0, 1.0);
    final bottom = (r.bottom / size.height).clamp(0.0, 1.0);
    if (right - left < _minSize ||
        bottom - top < _minSize ||
        widget.zones.length >= maxZones) {
      setState(() {});
      return;
    }
    final zones = [
      ...widget.zones,
      Zone(left: left, top: top, width: right - left, height: bottom - top),
    ];
    setState(() => _selected = zones.length - 1);
    widget.onChanged(zones);
  }

  void _select(Offset p, Size size) {
    final x = p.dx / size.width, y = p.dy / size.height;
    int? found;
    for (var i = widget.zones.length - 1; i >= 0; i--) {
      if (widget.zones[i].contains(x, y)) {
        found = i;
        break;
      }
    }
    setState(() => _selected = found);
  }

  void _deleteSelected() {
    final i = _selected;
    if (i == null || i >= widget.zones.length) return;
    final zones = [...widget.zones]..removeAt(i);
    setState(() => _selected = null);
    widget.onChanged(zones);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected != null && _selected! < widget.zones.length
        ? _selected
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TxQcm.qzpDrawHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: MaskedImage(
            name: widget.image,
            maxHeight: 420,
            overlay: (context, size) => GestureDetector(
              key: const ValueKey('zone-surface'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => setState(() {
                _start = d.localPosition;
                _drag = Rect.fromPoints(d.localPosition, d.localPosition);
              }),
              onPanUpdate: (d) {
                final s = _start;
                if (s == null) return;
                setState(() => _drag = Rect.fromPoints(s, d.localPosition));
              },
              onPanEnd: (_) => _end(size),
              onPanCancel: () => setState(() {
                _start = null;
                _drag = null;
              }),
              onTapUp: (d) => _select(d.localPosition, size),
              child: CustomPaint(
                size: size,
                painter: _ZonesPainter(
                  zones: widget.zones,
                  selected: selected,
                  drag: _drag,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              TxQcm.qzpZones(widget.zones.length),
              key: const ValueKey('zone-count'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('zone-delete'),
              onPressed: selected == null ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              label: const Text(TxQcm.qzpDeleteZone),
            ),
            TextButton(
              key: const ValueKey('zone-clear'),
              onPressed: widget.zones.isEmpty
                  ? null
                  : () {
                      setState(() => _selected = null);
                      widget.onChanged(const []);
                    },
              child: const Text(TxQcm.qzpClearZones),
            ),
          ],
        ),
      ],
    );
  }
}

class _ZonesPainter extends CustomPainter {
  _ZonesPainter({
    required this.zones,
    required this.selected,
    required this.drag,
    required this.color,
  });

  final List<Zone> zones;
  final int? selected;
  final Rect? drag;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < zones.length; i++) {
      final z = zones[i];
      final r = Rect.fromLTWH(
        z.left * size.width,
        z.top * size.height,
        z.width * size.width,
        z.height * size.height,
      );
      final on = i == selected;
      canvas.drawRect(
        r,
        Paint()..color = color.withValues(alpha: on ? 0.35 : 0.2),
      );
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 4 : 2.5
          ..color = color,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            backgroundColor: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.topLeft + const Offset(4, 2));
    }
    final d = drag;
    if (d != null) {
      final clipped = Rect.fromLTRB(
        max(0, d.left),
        max(0, d.top),
        min(size.width, d.right),
        min(size.height, d.bottom),
      );
      canvas.drawRect(clipped, Paint()..color = color.withValues(alpha: 0.2));
      canvas.drawRect(
        clipped,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ZonesPainter old) => true;
}
