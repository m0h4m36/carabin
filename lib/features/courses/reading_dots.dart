import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Six pastilles : une par lecture complète d'un poly. Toucher une pastille
/// la coche ; la toucher de nouveau la décoche.
class ReadingDots extends StatelessWidget {
  const ReadingDots({super.key, required this.doc, required this.onToggle});

  final Doc doc;
  final void Function(int index, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < Doc.maxReads; i++)
          Semantics(
            button: true,
            checked: doc.isRead(i),
            label: 'Lecture ${i + 1}',
            child: InkResponse(
              onTap: () => onToggle(i, !doc.isRead(i)),
              radius: 22,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: doc.isRead(i) ? scheme.primary : Colors.transparent,
                      border: Border.all(
                        color: doc.isRead(i) ? scheme.primary : scheme.outline,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
