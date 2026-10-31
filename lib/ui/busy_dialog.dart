import 'package:flutter/material.dart';

/// Fenêtre d'attente qui bloque l'interface pendant un travail long (import,
/// export). Se ferme avec [close] ; le texte peut changer avec [update].
class BusyDialog {
  BusyDialog._(this._navigator, this._message);

  final NavigatorState _navigator;
  final ValueNotifier<String> _message;
  bool _closed = false;

  static BusyDialog show(BuildContext context, String message) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final notifier = ValueNotifier<String>(message);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('busy-dialog'),
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: notifier,
                  builder: (_, text, _) => Text(text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return BusyDialog._(navigator, notifier);
  }

  void update(String message) {
    if (!_closed) _message.value = message;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _navigator.pop();
    _message.dispose();
  }
}
