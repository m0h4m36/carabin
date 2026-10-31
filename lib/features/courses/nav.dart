import 'package:flutter/material.dart';

/// Ouvre une page de la pile « Cours » en lui donnant un nom, pour que le
/// fil d'Ariane puisse revenir exactement à ce niveau.
void pushNamedPage(BuildContext context, String name, WidgetBuilder builder) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: builder,
    ),
  );
}

void popToRoute(BuildContext context, String name) {
  Navigator.of(context).popUntil(
    (r) => r.isFirst || r.settings.name == name,
  );
}

/// Quand l'élément affiché a disparu (supprimé ailleurs), on ferme la page.
Widget goneScaffold(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) Navigator.of(context).maybePop();
  });
  return const Scaffold();
}
