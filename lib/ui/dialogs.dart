import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/textes.dart';
import 'palette.dart';

/// Demande un texte à l'utilisateur ; renvoie null s'il annule.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = Tx.validate,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(Tx.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Confirmation ; renvoie vrai seulement si l'utilisateur confirme.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(Tx.cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Choix d'une couleur de matière (13 pastilles ou valeur hexadécimale).
Future<int?> pickColor(BuildContext context, {int? initial}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _ColorDialog(initial: initial),
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({this.initial});
  final int? initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int _selected = widget.initial ?? subjectColors.first;
  late final TextEditingController _hex = TextEditingController(
    text: hexOf(_selected),
  );
  bool _hexInvalid = false;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _choose(int argb) {
    setState(() {
      _selected = argb;
      _hex.text = hexOf(argb);
      _hexInvalid = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(Tx.colorTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in subjectColors)
                  _Swatch(
                    color: colorOf(c),
                    selected: c == _selected,
                    onTap: () => _choose(c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hex,
              decoration: InputDecoration(
                labelText: Tx.colorCustom,
                errorText: _hexInvalid ? '#RRGGBB' : null,
              ),
              onChanged: (v) {
                final parsed = parseHexColor(v);
                setState(() {
                  _hexInvalid = parsed == null;
                  if (parsed != null) _selected = parsed;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(Tx.cancel)),
        FilledButton(
          onPressed: _hexInvalid ? null : () => Navigator.pop(context, _selected),
          child: const Text(Tx.validate),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

/// Affiche une erreur de la couche de données dans une bannière brève.
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(Tx.errorMessage(error))));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Exécute [action] et affiche l'erreur éventuelle ; renvoie vrai si elle a
/// réussi.
Future<bool> guarded(BuildContext context, FutureOr<void> Function() action) async {
  try {
    await action();
    return true;
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// Nom et couleur d'une matière, saisis ensemble.
Future<({String name, int color})?> promptSubject(
  BuildContext context, {
  required String title,
  String initialName = '',
  int? initialColor,
  String confirmLabel = Tx.create,
}) {
  return showDialog<({String name, int color})>(
    context: context,
    builder: (ctx) => _SubjectDialog(
      title: title,
      initialName: initialName,
      initialColor: initialColor ?? subjectColors.first,
      confirmLabel: confirmLabel,
    ),
  );
}

class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog({
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.confirmLabel,
  });
  final String title;
  final String initialName;
  final int initialColor;
  final String confirmLabel;

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: Tx.subjectName),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in subjectColors)
                  _Swatch(
                    color: colorOf(c),
                    selected: c == _color,
                    onTap: () => setState(() => _color = c),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(Tx.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (name: _name.text, color: _color)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Une ligne d'une liste de choix.
class Choice<T> {
  const Choice(this.value, this.label, {this.subtitle, this.color});
  final T value;
  final String label;
  final String? subtitle;
  final Color? color;
}

/// Propose une liste de choix ; renvoie la valeur choisie ou null.
Future<T?> pickFromList<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  String emptyMessage = Tx.nothingToMoveTo,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: choices.isEmpty
            ? Text(emptyMessage)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final c in choices)
                    ListTile(
                      leading: c.color == null
                          ? null
                          : Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                      title: Text(c.label),
                      subtitle: c.subtitle == null ? null : Text(c.subtitle!),
                      onTap: () => Navigator.pop(ctx, c.value),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(Tx.cancel),
        ),
      ],
    ),
  );
}
