import 'package:flutter/material.dart';

import '../../domain/note_types.dart';
import 'masked_image.dart';

/// Une carte d'occlusion : l'image avec les zones à deviner. À la question
/// elles sont pleines ; à la réponse elles se réduisent à un contour.
class OcclusionView extends StatelessWidget {
  const OcclusionView({
    super.key,
    required this.fields,
    required this.ord,
    required this.revealed,
    this.maxHeight = 460,
  });

  final NoteFields fields;
  final int ord;
  final bool revealed;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final masks = activeMasks(fields, ord);
    final color = Theme.of(context).colorScheme.primary;
    return Center(
      child: MaskedImage(
        name: fields.image,
        maxHeight: maxHeight,
        overlay: (context, size) => CustomPaint(
          key: const ValueKey('occlusion-masks'),
          size: size,
          painter: MaskPainter(masks: masks, color: color, outlined: revealed),
        ),
      ),
    );
  }
}

/// Dessine des zones masquées (pleines ou en contour) sur une image.
class MaskPainter extends CustomPainter {
  MaskPainter({
    required this.masks,
    required this.color,
    required this.outlined,
    this.selected,
    this.showGroups = false,
    this.labelColor = Colors.white,
  });

  final List<OcclusionMask> masks;
  final Color color;
  final bool outlined;

  /// Masque mis en avant (éditeur).
  final OcclusionMask? selected;

  /// Écrit le numéro de groupe dans chaque zone (éditeur).
  final bool showGroups;
  final Color labelColor;

  static Rect rectOf(OcclusionMask m, Size size) => Rect.fromLTWH(
    m.left * size.width,
    m.top * size.height,
    m.width * size.width,
    m.height * size.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in masks) {
      final r = rectOf(m, size);
      final isSelected = identical(m, selected);
      if (outlined) {
        canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.14));
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color,
        );
      } else {
        canvas.drawRect(
          r,
          Paint()..color = color.withValues(alpha: showGroups ? 0.82 : 1),
        );
        if (isSelected) {
          canvas.drawRect(
            r.deflate(1.5),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = labelColor,
          );
        }
      }
      if (showGroups) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${m.group}',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, r.topLeft + const Offset(4, 2));
      }
    }
  }

  @override
  bool shouldRepaint(MaskPainter old) =>
      old.masks != masks ||
      old.color != color ||
      old.outlined != outlined ||
      old.selected != selected ||
      old.showGroups != showGroups;
}
