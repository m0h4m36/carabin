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
