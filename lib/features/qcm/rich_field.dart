import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/textes_qcm.dart';
import '../flashcards/text_editing.dart';

/// Champ de texte avec gras, italique, souligné et surlignage (mêmes marques
/// que les cartes). Le champ garde son propre texte : on le recrée (autre
/// `key`) pour le changer de l'extérieur.
class QcmRichField extends StatefulWidget {
  const QcmRichField({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.minLines = 3,
    this.fieldKey,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final int minLines;
  final Key? fieldKey;

  @override
  State<QcmRichField> createState() => _QcmRichFieldState();
}

class _QcmRichFieldState extends State<QcmRichField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _format(Format f) {
    _controller.value = toggleFormat(_controller.value, f);
    _focus.requestFocus();
    widget.onChanged(_controller.text);
  }

  Map<ShortcutActivator, VoidCallback> _bindings() {
    final map = <ShortcutActivator, VoidCallback>{};
    void both(LogicalKeyboardKey key, Format f) {
      map[SingleActivator(key, control: true)] = () => _format(f);
      map[SingleActivator(key, meta: true)] = () => _format(f);
    }

    both(LogicalKeyboardKey.keyB, Format.bold);
    both(LogicalKeyboardKey.keyI, Format.italic);
    both(LogicalKeyboardKey.keyU, Format.underline);
    return map;
  }

  @override
  Widget build(BuildContext context) {
    Widget fmt(IconData icon, String tip, Format f) => IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 20),
      onPressed: () => _format(f),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            fmt(Icons.format_bold, TxQcm.bold, Format.bold),
            fmt(Icons.format_italic, TxQcm.italic, Format.italic),
            fmt(Icons.format_underline, TxQcm.underline, Format.underline),
            fmt(Icons.border_color_outlined, TxQcm.highlight, Format.highlight),
          ],
        ),
        CallbackShortcuts(
          bindings: _bindings(),
          child: TextField(
            key: widget.fieldKey,
            controller: _controller,
            focusNode: _focus,
            minLines: widget.minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: widget.label,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ],
    );
  }
}
