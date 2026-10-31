import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/media_store.dart';
import '../../l10n/textes_occlusion.dart';

/// Une image du dossier de médias à sa vraie proportion, avec une couche
/// dessinée par-dessus (masques d'occlusion). Les coordonnées de la couche
/// vont de 0 à la largeur/hauteur affichées.
///
/// La proportion est lue sur l'image réellement décodée (et non sur un
/// enregistrement) : si le système tourne l'image d'après ses métadonnées,
/// les masques restent alignés.
class MaskedImage extends StatefulWidget {
  const MaskedImage({
    super.key,
    required this.name,
    required this.overlay,
    this.maxHeight = 460,
    this.width,
  });

  final String name;

  /// Dessine la couche au-dessus de l'image, à la taille affichée.
  final Widget Function(BuildContext context, Size size) overlay;
  final double maxHeight;

  /// Largeur imposée (zoom) ; sinon toute la largeur disponible.
  final double? width;

  @override
  State<MaskedImage> createState() => _MaskedImageState();
}

class _MaskedImageState extends State<MaskedImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspect;
  bool _failed = false;
  String? _loaded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(MaskedImage old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) _load();
  }

  void _load() {
    if (_loaded == widget.name) return;
    _unlisten();
    _loaded = widget.name;
    _aspect = null;
    _failed = false;
    final media = context.read<MediaStore>();
    if (!media.exists(widget.name)) {
      _failed = true;
      return;
    }
    final stream = FileImage(media.file(widget.name))
        .resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        setState(() => _aspect = h == 0 ? 1 : w / h);
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(_listener!);
    _stream = stream;
  }

  void _unlisten() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: scheme.outline),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                TxOcclusion.imageUnreadable,
                style: TextStyle(color: scheme.outline),
              ),
            ),
          ],
        ),
      );
    }
    final aspect = _aspect;
    if (aspect == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        var w = widget.width ?? constraints.maxWidth;
        if (!w.isFinite) w = 600;
        var h = w / aspect;
        if (widget.width == null && h > widget.maxHeight) {
          h = widget.maxHeight;
          w = h * aspect;
        }
        final size = Size(w, h);
        final media = context.read<MediaStore>();
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                media.file(widget.name),
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
              widget.overlay(context, size),
            ],
          ),
        );
      },
    );
  }
}
