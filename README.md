# Carabin

Appli libre et gratuite de révision pour les étudiants en médecine : cours et polys annotables, flashcards à répétition espacée (FSRS), QCM, planning et méthode des J.

> **État : tout début (v0.1).** Pour l'instant, seul le cadre de l'application existe (navigation entre les cinq modules). Les fonctions arrivent une par une, dans l'ordre décrit dans [`docs/SPEC.md`](docs/SPEC.md), section 15.

## Objectifs

- Fonctionne **hors connexion**, **sans compte** ; les données restent sur l'appareil.
- Un seul code pour **Windows, Mac, Android, iPhone et iPad** (Flutter).
- Un dossier de travail lisible sans l'appli, des documents importés jamais modifiés.
- Un visuel épuré : une seule couleur d'accent, beaucoup d'espace.

## Télécharger

Les versions compilées automatiquement sont dans l'onglet **Actions** du dépôt : ouvrez la dernière exécution réussie, puis téléchargez l'archive de votre plateforme dans la section « Artifacts ».

| Plateforme | Fichier |
|---|---|
| Windows | `carabin-windows.zip` (décompresser, lancer `carabin.exe`) |
| Android | `carabin-android` (fichier `.apk`, à autoriser à l'installation) |
| Mac | `carabin-macos.zip` |
| iPhone / iPad | pas encore distribué (nécessite un compte développeur Apple) |

## Développer

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install) (version indiquée dans `.github/workflows/build.yml`).

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # ou macos, android…
```

La spécification fonctionnelle est dans [`docs/SPEC.md`](docs/SPEC.md). Les décisions et conventions du projet sont dans [`CLAUDE.md`](CLAUDE.md).

## Origine du projet

Carabin est une création **originale**. Son cahier des charges est fondé sur l'observation publique d'une application de révision existante et sur sa documentation publique ; **aucun code, texte, logo, nom ni visuel** n'en a été repris. Les contributions doivent respecter la même règle.

## Licence

[Apache-2.0](LICENSE). Copyright 2026 les contributeurs de Carabin.
