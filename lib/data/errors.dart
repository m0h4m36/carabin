import '../domain/note_types.dart';

/// Erreurs prévues de la couche de données. Les écrans les traduisent en
/// phrases françaises (voir `lib/l10n/textes.dart`) : aucun texte ici.
sealed class DataError implements Exception {
  const DataError();
}

/// Le nom saisi est vide.
class EmptyNameError extends DataError {
  const EmptyNameError();
}

/// Un élément du même niveau porte déjà ce nom (ou un nom qui donnerait le
/// même dossier).
class NameTakenError extends DataError {
  const NameTakenError(this.name);
  final String name;
}

/// L'élément demandé n'existe plus.
class NotFoundError extends DataError {
  const NotFoundError();
}

/// Problème d'accès au disque (dossier occupé, fichier introuvable…).
class FileProblemError extends DataError {
  const FileProblemError(this.detail);
  final String detail;
  @override
  String toString() => 'FileProblemError($detail)';
}

/// La note est incomplète ou invalide (voir [NoteIssue]).
class InvalidNoteError extends DataError {
  const InvalidNoteError(this.issue);
  final NoteIssue issue;
}

/// Le fichier n'est pas d'un type pris en charge (par exemple une image
/// d'un format que Carabin ne sait pas afficher).
class UnsupportedFileError extends DataError {
  const UnsupportedFileError();
}

/// Ce qui a empêché un import.
enum ImportProblem {
  /// Le fichier n'est ni une archive lisible ni un paquet connu.
  unreadable,

  /// L'archive est abîmée ou incomplète.
  corrupt,

  /// Le paquet ne contient aucune carte.
  empty,

  /// Paquet Anki exporté sans la compatibilité avec les anciennes versions et
  /// dont le contenu réel n'a pas pu être lu.
  ankiNeedsOlderFormat,

  /// Fichier fabriqué par une version plus récente de Carabin.
  newerFormat,

  /// Fichier texte sans colonne exploitable.
  noColumns,
}

/// Un import ou un export a échoué.
class ExchangeError extends DataError {
  const ExchangeError(this.problem, [this.detail = '']);
  final ImportProblem problem;
  final String detail;
  @override
  String toString() => 'ExchangeError($problem, $detail)';
}
