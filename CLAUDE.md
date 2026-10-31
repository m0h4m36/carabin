# Carabin — repères pour travailler sur le projet

## Quoi
Appli de révision pour étudiants en médecine (cours/polys, flashcards FSRS, QCM, planning, méthode des J). Flutter, une seule base de code pour Windows, macOS, Android, iOS/iPadOS. Spécification : `docs/SPEC.md` (la lire avant toute nouvelle fonction).

## Règles non négociables
- **Création originale** : ne jamais copier de code, de texte, de logo, de nom, d'icône ni de capture d'une autre appli. S'inspirer des fonctions, pas de la forme.
- Les 367 items des EDN viennent de la **source officielle**, pas d'une autre appli.
- Hors connexion, sans compte, sans télémétrie. Les données restent sur l'appareil.
- Les documents importés ne sont jamais modifiés : les annotations vivent dans une copie.
- Textes de l'interface en **français** (prévoir l'internationalisation ensuite). Pas de texte en dur dans la logique : passer par une couche de textes.
- Une seule couleur d'accent (`lib/ui/theme.dart`), mode sombre géré dès le départ, cibles tactiles ≥ 44 pt.

## Décisions prises
- Licence : Apache-2.0 (compatible App Store).
- Identifiant d'appli : `io.github.m0h4m36.carabin` (à ne pas changer une fois publié sur une boutique).
- Pas de synchronisation entre appareils en v1 : sauvegarde par export/import d'un fichier ; synchro envisagée plus tard.
- Algorithme de révision : FSRS. Base de données : SQLite.
- Ordre de développement : voir `docs/SPEC.md` §15 (dossier + base + import PDF, puis flashcards + FSRS, etc.).

## Commandes
```
flutter pub get
flutter analyze     # doit rester sans aucun avertissement
flutter test        # doit passer avant chaque envoi
```
Le workflow `.github/workflows/build.yml` compile Windows, Android, macOS et iOS (non signée) à chaque envoi sur `main`.

## Organisation du code
- `lib/main.dart`, `lib/app.dart` : point d'entrée et racine.
- `lib/ui/` : cadre de navigation, thème, pages.
- À venir : `lib/data/` (SQLite, dossier de travail), `lib/features/<module>/` (cours, flashcards, qcm, planning).
- Tests dans `test/`, au même chemin que le code testé.
