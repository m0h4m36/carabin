import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/media_store.dart';
import '../../l10n/textes_occlusion.dart';

/// Une image d'un champ de carte (`[img:nom.png]`). Un toucher l'ouvre en
/// grand.
class CardImage extends StatelessWidget {
  const CardImage(this.name, {super.key, this.maxHeight = 260});

  final String name;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final media = context.read<MediaStore>();
    if (!media.exists(name)) return const _MissingImage();
    final file = media.file(name);
    return Semantics(
      image: true,
      child: InkWell(
        onTap: () => showImageViewer(context, file),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const _MissingImage(unreadable: true),
          ),
        ),
      ),
    );
  }
}

class _MissingImage extends StatelessWidget {
  const _MissingImage({this.unreadable = false});
  final bool unreadable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: scheme.outline),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            unreadable ? TxOcclusion.imageUnreadable : TxOcclusion.imageMissing,
            style: TextStyle(color: scheme.outline),
          ),
        ),
      ],
    );
  }
}

/// Affiche une image en grand, déplaçable et agrandissable.
Future<void> showImageViewer(BuildContext context, File file) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: Image.file(
                  file,
                  errorBuilder: (_, _, _) =>
                      const _MissingImage(unreadable: true),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: TxOcclusion.closeViewer,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}
