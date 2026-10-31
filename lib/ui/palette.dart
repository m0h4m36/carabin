import 'package:flutter/material.dart';

/// Couleurs proposées pour les matières (petite touche de couleur, pas de
/// fond de carte : l'unique accent de l'interface reste dans le thème).
const List<int> subjectColors = [
  0xFFE53935, // rouge
  0xFFD81B60, // rose
  0xFF8E24AA, // violet
  0xFF5E35B1, // indigo
  0xFF3949AB, // bleu nuit
  0xFF1E88E5, // bleu
  0xFF00ACC1, // turquoise
  0xFF00897B, // vert d'eau
  0xFF43A047, // vert
  0xFF7CB342, // vert clair
  0xFFFB8C00, // orange
  0xFFF4511E, // corail
  0xFF6D4C41, // brun
];

Color colorOf(int argb) => Color(argb);

/// Convertit « #RRGGBB » ou « RRGGBB » en couleur ARGB opaque, ou null.
int? parseHexColor(String input) {
  var s = input.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return 0xFF000000 | v;
}

String hexOf(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
