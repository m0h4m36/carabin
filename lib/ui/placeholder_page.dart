import 'package:flutter/material.dart';

import '../l10n/textes.dart';
import 'destinations.dart';

/// Page provisoire d'un module, en attendant son implémentation.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.destination});

  final CarabinDestination destination;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(destination.label, style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                destination.description,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Text(
                Tx.comingSoon,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
