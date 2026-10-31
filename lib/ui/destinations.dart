import 'package:flutter/material.dart';

/// Un écran principal de l'application (une entrée de la barre latérale).
class CarabinDestination {
  const CarabinDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.description,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
}

/// Les modules, dans l'ordre de la barre latérale (voir docs/SPEC.md, §10.1).
const List<CarabinDestination> carabinDestinations = [
  CarabinDestination(
    id: 'dashboard',
    label: 'Tableau de bord',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    description: 'Votre journée : cartes à réviser, J du jour, progression.',
  ),
  CarabinDestination(
    id: 'courses',
    label: 'Cours',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    description: 'Années, semestres, matières, thèmes et polys.',
  ),
  CarabinDestination(
    id: 'flashcards',
    label: 'Flashcards',
    icon: Icons.style_outlined,
    selectedIcon: Icons.style,
    description: 'Paquets de cartes et révision espacée.',
  ),
  CarabinDestination(
    id: 'qcm',
    label: 'QCM',
    icon: Icons.checklist_outlined,
    selectedIcon: Icons.checklist,
    description: 'Épreuves, entraînements et copies.',
  ),
  CarabinDestination(
    id: 'planning',
    label: 'Planning',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    description: 'Agenda et méthode des J.',
  ),
];
