import 'package:flutter/material.dart';

import 'destinations.dart';
import 'placeholder_page.dart';

/// Largeur à partir de laquelle on passe de la barre du bas (téléphone)
/// à la barre latérale (tablette, ordinateur).
const double kWideLayoutBreakpoint = 720;

/// Cadre de l'application : barre latérale sur grand écran,
/// barre de navigation du bas sur téléphone.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final destination = carabinDestinations[_index];
    final page = PlaceholderPage(
      key: ValueKey(destination.id),
      destination: destination,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kWideLayoutBreakpoint;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in carabinDestinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(),
                Expanded(child: SafeArea(child: page)),
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(child: page),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final d in carabinDestinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
