import 'package:flutter/material.dart';

/// Écran vide avec une invitation à agir.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Petite pastille de couleur (matière).
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 12});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Fil d'Ariane : une suite de libellés, chacun cliquable sauf le dernier.
class Crumbs extends StatelessWidget {
  const Crumbs({super.key, required this.items});
  final List<Crumb> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('›', style: style),
            ),
          if (items[i].onTap != null)
            InkWell(
              onTap: items[i].onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                child: Text(items[i].label, style: style),
              ),
            )
          else
            Text(items[i].label, style: style),
        ],
      ],
    );
  }
}

class Crumb {
  const Crumb(this.label, [this.onTap]);
  final String label;
  final VoidCallback? onTap;
}

/// En-tête de page : titre, sous-titre facultatif et actions à droite.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.crumbs,
    this.actions = const [],
  });

  final String title;
  final List<Crumb>? crumbs;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (crumbs != null && crumbs!.isNotEmpty) Crumbs(items: crumbs!),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}
