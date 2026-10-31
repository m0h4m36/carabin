import 'package:flutter/material.dart';

import '../features/courses/courses_page.dart';
import '../features/flashcards/flashcards_page.dart';
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

  /// Les modules déjà visités restent en vie (leur pile de pages est gardée).
  final Set<int> _visited = {0};

  void _select(int index) => setState(() {
        _index = index;
        _visited.add(index);
      });

  Widget _pageFor(int i) {
    final destination = carabinDestinations[i];
    return switch (destination.id) {
      'courses' => const CoursesPage(),
      'flashcards' => const FlashcardsPage(),
      _ => PlaceholderPage(destination: destination),
    };
  }

  Widget _body() => IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < carabinDestinations.length; i++)
            if (_visited.contains(i))
              KeyedSubtree(
                key: ValueKey(carabinDestinations[i].id),
                child: _pageFor(i),
              )
            else
              const SizedBox.shrink(),
        ],
      );

  @override
  Widget build(BuildContext context) {
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
                Expanded(child: SafeArea(child: _body())),
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(child: _body()),
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
