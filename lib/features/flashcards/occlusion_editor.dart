import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/errors.dart';
import '../../data/media_store.dart';
import '../../domain/note_types.dart';
import '../../l10n/textes_occlusion.dart';
import '../../ui/dialogs.dart';
import '../../ui/pickers.dart';
import 'masked_image.dart';
import 'occlusion_view.dart';

enum OcclusionTool { draw, move }

/// État de l'éditeur d'occlusion : image, zones et réglages. Les zones sont
/// des fractions de l'image (0 à 1), donc indépendantes de l'affichage.
class OcclusionDraft extends ChangeNotifier {
  String image = '';
  OcclusionMode mode = OcclusionMode.hideAll;
  List<OcclusionMask> masks = [];
  int group = 1;
  int? selectedId;
  double zoom = 1;
  OcclusionTool tool = OcclusionTool.draw;
  final List<List<OcclusionMask>> _history = [];

  bool get hasImage => image.isNotEmpty;

  OcclusionMask? get selected {
    for (final m in masks) {
      if (m.id == selectedId) return m;
    }
    return null;
  }

  int get groupCount => {for (final m in masks) m.group}.length;

  NoteFields toFields({String extra = '', String context = ''}) => NoteFields({
    if (image.isNotEmpty) 'image': image,
    'mode': mode.name,
    'masks': [for (final m in masks) m.toJson()],
    if (extra.isNotEmpty) 'extra': extra,
    if (context.isNotEmpty) 'context': context,
  });

  /// Nombre de cartes que fabriquerait la note telle qu'elle est.
  int get cardCount =>
      masks.isEmpty ? 0 : cardOrdinals(NoteType.occlusion, toFields()).length;

  void load(NoteFields f) {
    image = f.image;
    mode = f.occlusionMode;
    masks = f.masks;
    group = masks.isEmpty ? 1 : masks.map((m) => m.group).reduce(min);
    selectedId = null;
    _history.clear();
    notifyListeners();
  }

  /// Repart de zéro (après l'ajout d'une note).
  void reset() {
    image = '';
    masks = [];
    selectedId = null;
    group = 1;
    zoom = 1;
    _history.clear();
    notifyListeners();
  }

  void setImage(String name) {
    image = name;
    notifyListeners();
  }

  void _remember() {
    _history.add(List.of(masks));
    if (_history.length > 100) _history.removeAt(0);
  }

  int _nextId() => masks.isEmpty ? 1 : masks.map((m) => m.id).reduce(max) + 1;

  /// Ajoute une zone (fractions de l'image) ; ignore les rectangles trop
  /// petits pour être voulus.
  bool addMask(Rect r) {
    final left = r.left.clamp(0.0, 1.0);
    final top = r.top.clamp(0.0, 1.0);
    final right = r.right.clamp(0.0, 1.0);
    final bottom = r.bottom.clamp(0.0, 1.0);
    if (right - left < 0.01 || bottom - top < 0.01) return false;
    _remember();
    final m = OcclusionMask(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
      group: mode == OcclusionMode.group ? group : 1,
      id: _nextId(),
    );
    masks = [...masks, m];
    selectedId = null;
    notifyListeners();
    return true;
  }

  /// Sélectionne la zone sous le point [p] (fractions), ou rien.
  void selectAt(Offset p) {
    int? found;
    for (final m in masks.reversed) {
      if (p.dx >= m.left &&
          p.dx <= m.left + m.width &&
          p.dy >= m.top &&
          p.dy <= m.top + m.height) {
        found = m.id;
        break;
      }
    }
    selectedId = found;
    notifyListeners();
  }

  void removeSelected() {
    if (selected == null) return;
    _remember();
    masks = [
      for (final m in masks)
        if (m.id != selectedId) m,
    ];
    selectedId = null;
    notifyListeners();
  }

  void clearMasks() {
    if (masks.isEmpty) return;
    _remember();
    masks = [];
    selectedId = null;
    notifyListeners();
  }

  /// Annule le dernier changement de zones.
  bool undo() {
    if (_history.isEmpty) return false;
    masks = _history.removeLast();
    if (selected == null) selectedId = null;
    notifyListeners();
    return true;
  }

  bool get canUndo => _history.isNotEmpty;

  void setMode(OcclusionMode m) {
    mode = m;
    notifyListeners();
  }

  /// Change le groupe dans lequel seront rangées les prochaines zones.
  void setGroup(int g) {
    group = max(1, g);
    notifyListeners();
  }

  /// Range la zone sélectionnée dans le groupe courant.
  void moveSelectedToGroup() {
    final s = selected;
    if (s == null || s.group == group) return;
    _remember();
    masks = [
      for (final m in masks) m.id == s.id ? m.copyWith(group: group) : m,
    ];
    notifyListeners();
  }

  void setZoom(double z) {
    zoom = z.clamp(0.5, 4.0);
    notifyListeners();
  }

  void setTool(OcclusionTool t) {
    tool = t;
    notifyListeners();
  }
}

/// Éditeur d'occlusion : choix de l'image, tracé des zones, mode.
class OcclusionEditor extends StatefulWidget {
  const OcclusionEditor({super.key, required this.draft});
  final OcclusionDraft draft;

  @override
  State<OcclusionEditor> createState() => _OcclusionEditorState();
}

class _OcclusionEditorState extends State<OcclusionEditor> {
  final _focus = FocusNode(debugLabel: 'occlusion');
  Offset? _start;
  Rect? _drag;

  OcclusionDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    d.addListener(_changed);
  }

  @override
  void didUpdateWidget(OcclusionEditor old) {
    super.didUpdateWidget(old);
    if (old.draft != d) {
      old.draft.removeListener(_changed);
      d.addListener(_changed);
    }
  }

  @override
  void dispose() {
    d.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    final media = context.read<MediaStore>();
    final String? path;
    try {
      path = await Pickers.image();
    } on Object catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (path == null || !mounted) return;
    try {
      d.setImage(media.addFile(path));
    } on UnsupportedFileError catch (e) {
      showError(context, e);
    } on Object catch (e) {
      showError(context, e);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.keyG && !ctrl) {
      d.setGroup(shift ? d.group - 1 : d.group + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ && ctrl) {
      d.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      d.removeSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!d.hasImage) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.image_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              TxOcclusion.chooseImageHelp,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('occlusion-pick'),
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text(TxOcclusion.chooseImage),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(theme),
        const SizedBox(height: 8),
        _modeRow(theme),
        const SizedBox(height: 8),
        Text(
          TxOcclusion.counters(d.masks.length, d.groupCount, d.cardCount),
          key: const ValueKey('occlusion-counters'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _canvas(theme),
        const SizedBox(height: 6),
        Text(
          d.tool == OcclusionTool.draw
              ? TxOcclusion.toolDrawHelp
              : TxOcclusion.toolMoveHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ThemeData theme) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<OcclusionTool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: OcclusionTool.draw,
              icon: Icon(Icons.crop_square),
              label: Text(TxOcclusion.toolDraw),
            ),
            ButtonSegment(
              value: OcclusionTool.move,
              icon: Icon(Icons.pan_tool_outlined),
              label: Text(TxOcclusion.toolMove),
            ),
          ],
          selected: {d.tool},
          onSelectionChanged: (s) => d.setTool(s.first),
        ),
        IconButton(
          tooltip: TxOcclusion.zoomOut,
          onPressed: d.zoom > 0.5 ? () => d.setZoom(d.zoom - 0.25) : null,
          icon: const Icon(Icons.zoom_out),
        ),
        Text(
          '${(d.zoom * 100).round()} %',
          key: const ValueKey('occlusion-zoom'),
        ),
        IconButton(
          tooltip: TxOcclusion.zoomIn,
          onPressed: d.zoom < 4 ? () => d.setZoom(d.zoom + 0.25) : null,
          icon: const Icon(Icons.zoom_in),
        ),
        IconButton(
          key: const ValueKey('occlusion-undo'),
          tooltip: TxOcclusion.undoMask,
          onPressed: d.canUndo ? d.undo : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          key: const ValueKey('occlusion-delete'),
          tooltip: TxOcclusion.deleteMask,
          onPressed: d.selected != null ? d.removeSelected : null,
          icon: const Icon(Icons.delete_outline),
        ),
        TextButton(
          onPressed: d.masks.isEmpty ? null : d.clearMasks,
          child: const Text(TxOcclusion.clearMasks),
        ),
        TextButton.icon(
          key: const ValueKey('occlusion-change-image'),
          onPressed: _pickImage,
          icon: const Icon(Icons.image_outlined),
          label: const Text(TxOcclusion.changeImage),
        ),
      ],
    );
  }

  Widget _modeRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final m in OcclusionMode.values)
              ChoiceChip(
                key: ValueKey('occlusion-mode-${m.name}'),
                label: Text(TxOcclusion.modeName(m)),
                selected: d.mode == m,
                onSelected: (_) => d.setMode(m),
              ),
            if (d.mode == OcclusionMode.group) ...[
              IconButton(
                tooltip: TxOcclusion.groupPrev,
                onPressed: d.group > 1 ? () => d.setGroup(d.group - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Text(
                TxOcclusion.group(d.group),
                key: const ValueKey('occlusion-group'),
              ),
              IconButton(
                tooltip: TxOcclusion.groupNext,
                onPressed: () => d.setGroup(d.group + 1),
                icon: const Icon(Icons.add),
              ),
              if (d.selected != null)
                TextButton(
                  key: const ValueKey('occlusion-assign'),
                  onPressed: d.moveSelectedToGroup,
                  child: Text(TxOcclusion.assignToGroup(d.group)),
                ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          TxOcclusion.modeHelp(d.mode),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Offset _frac(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  Widget _canvas(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth * d.zoom;
          final image = MaskedImage(
            key: ValueKey('occlusion-image-${d.image}'),
            name: d.image,
            width: width,
            overlay: (context, size) {
              final dragging = _drag;
              return GestureDetector(
                key: const ValueKey('occlusion-canvas'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: d.tool == OcclusionTool.draw
                    ? (details) {
                        _focus.requestFocus();
                        d.selectAt(_frac(details.localPosition, size));
                      }
                    : null,
                onPanStart: d.tool == OcclusionTool.draw
                    ? (details) {
                        _focus.requestFocus();
                        _start = _frac(details.localPosition, size);
                        setState(
                          () => _drag = Rect.fromPoints(_start!, _start!),
                        );
                      }
                    : null,
                onPanUpdate: d.tool == OcclusionTool.draw
                    ? (details) {
                        final s = _start;
                        if (s == null) return;
                        setState(
                          () => _drag = Rect.fromPoints(
                            s,
                            _frac(details.localPosition, size),
                          ),
                        );
                      }
                    : null,
                onPanEnd: d.tool == OcclusionTool.draw
                    ? (_) {
                        final r = _drag;
                        _start = null;
                        setState(() => _drag = null);
                        if (r != null) d.addMask(r);
                      }
                    : null,
                onPanCancel: () {
                  _start = null;
                  if (_drag != null) setState(() => _drag = null);
                },
                child: CustomPaint(
                  size: size,
                  painter: _EditorPainter(
                    masks: d.masks,
                    selected: d.selected,
                    drag: dragging,
                    color: scheme.primary,
                    showGroups: d.mode == OcclusionMode.group,
                  ),
                ),
              );
            },
          );
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: d.zoom > 1
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: image,
                  )
                : Align(alignment: Alignment.topLeft, child: image),
          );
        },
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({
    required this.masks,
    required this.selected,
    required this.drag,
    required this.color,
    required this.showGroups,
  });

  final List<OcclusionMask> masks;
  final OcclusionMask? selected;
  final Rect? drag;
  final Color color;
  final bool showGroups;

  @override
  void paint(Canvas canvas, Size size) {
    MaskPainter(
      masks: masks,
      color: color,
      outlined: false,
      selected: selected,
      showGroups: showGroups,
    ).paint(canvas, size);
    final r = drag;
    if (r != null) {
      final px = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      canvas.drawRect(px, Paint()..color = color.withValues(alpha: 0.35));
      canvas.drawRect(
        px,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) => true;
}
