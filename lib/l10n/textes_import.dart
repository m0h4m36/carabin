import '../domain/note_types.dart';
import 'textes.dart';

/// Textes de l'import de cartes (fichiers Carabin, Anki, CSV) et des exports.
abstract final class TxImport {
  // menus
  static const importCards = 'Importer des cartes…';
  static const shareDeck = 'Partager ce deck';
  static const exportProgress = 'Exporter avec la progression';
  static const exportAllProgress = 'Exporter toute la progression';

  // choix du fichier
  static const importing = 'Importation en cours…';
  static const unknownFile =
      'Ce type de fichier n\'est pas reconnu. Choisissez un fichier .carabin, '
      '.apkg, .colpkg, .csv, .tsv ou .txt.';
  static const unnamedDeck = 'Cartes importées';

  // progression reprise
  static const keepProgressTitle = 'Reprendre la progression ?';
  static const keepProgressMessage =
      'Ce fichier contient aussi l\'avancement des cartes (dates de révision '
      'et historique des réponses). Voulez-vous le reprendre ?';
  static const keepProgressYes = 'Reprendre la progression';
  static const keepProgressNo = 'Cartes seules';

  // fichier texte
  static const textTitle = 'Importer un fichier texte';
  static const textHelp =
      'Chaque ligne du fichier devient une note. Indiquez à quoi sert chaque '
      'colonne.';
  static const cardType = 'Type de cartes';
  static const firstRowIsHeader = 'La première ligne contient les titres';
  static const containsHtml = 'Le texte contient du HTML (export d\'Anki…)';
  static const preview = 'Aperçu';
  static const none = 'Aucune';
  static const targetDeck = 'Deck de destination';
  static const targetDeckHint = 'Nom du deck (créé s\'il n\'existe pas)';
  static const targetDeckByColumn =
      'Les lignes sans deck vont dans le deck ci-dessous.';
  static const columnText = 'Texte à trous';
  static const columnFront = 'Recto';
  static const columnBack = 'Verso';
  static const columnExtra = 'Complément';
  static const columnTags = 'Étiquettes';
  static const columnDeck = 'Deck';
  static const columnId = 'Identifiant';
  static const columnIdHelp =
      'Évite les doublons si vous réimportez le fichier après l\'avoir '
      'modifié.';
  static const importButton = 'Importer';
  static const emptyCell = '(vide)';

  static String columnName(int i) => 'Colonne ${i + 1}';

  static String typeName(NoteType t) => switch (t) {
    NoteType.cloze => 'Texte à trous',
    NoteType.basic => 'Recto-verso',
    NoteType.reversed => 'Recto-verso avec carte inverse',
    NoteType.typed => 'Réponse à saisir',
    NoteType.occlusion => 'Occlusion d\'image',
  };

  /// Types qu'un fichier texte peut produire (pas d'occlusion).
  static const textTypes = [
    NoteType.basic,
    NoteType.reversed,
    NoteType.typed,
    NoteType.cloze,
  ];

  static String rowsSummary(int notes, int skipped) =>
      Tx.plural(notes, 'note prête', 'notes prêtes') +
      (skipped > 0
          ? ' · ${Tx.plural(skipped, 'ligne ignorée', 'lignes ignorées')} '
                '(contenu incomplet)'
          : '');

  static String sampleNote(int n) => ' (aperçu sur les $n premières lignes)';

  // compte rendu
  static const reportTitle = 'Import terminé';
  static const reportNothing =
      'Rien de nouveau : ces cartes étaient déjà présentes.';
  static const close = 'Fermer';

  static String reportAdded(int n) =>
      Tx.plural(n, 'note ajoutée', 'notes ajoutées');
  static String reportUpdated(int n) =>
      Tx.plural(n, 'note mise à jour', 'notes mises à jour');
  static String reportPresent(int n) =>
      n == 1 ? '1 note déjà présente' : '$n notes déjà présentes';
  static String reportDecks(List<String> names) => names.length == 1
      ? 'Deck : ${names.single}'
      : 'Decks : ${names.take(4).join(', ')}'
            '${names.length > 4 ? ' et ${names.length - 4} autres' : ''}';
  static String reportCreated(int n) =>
      Tx.plural(n, 'deck créé', 'decks créés');
  static String reportProgress(int cards, int logs) =>
      'Progression reprise : ${Tx.plural(cards, 'carte', 'cartes')}, '
      '${Tx.plural(logs, 'réponse enregistrée', 'réponses enregistrées')}';
  static String reportImages(int n) =>
      Tx.plural(n, 'image reprise', 'images reprises');
  static String reportSkipped(int n) =>
      '${Tx.plural(n, 'note ignorée', 'notes ignorées')} (contenu incomplet ou '
      'type non pris en charge)';
  static String reportImagesDropped(int n) => Tx.plural(
    n,
    'image introuvable ou d\'un format non pris en charge',
    'images introuvables ou d\'un format non pris en charge',
  );
  static String reportSounds(int n) =>
      '${Tx.plural(n, 'son ou vidéo ignoré', 'sons ou vidéos ignorés')} '
      '(non pris en charge)';
  static String reportShapes(int n) =>
      '${Tx.plural(n, 'zone d\'occlusion remplacée', 'zones d\'occlusion remplacées')} '
      'par un rectangle';
  static String reportShapesDropped(int n) => Tx.plural(
    n,
    'zone d\'occlusion abandonnée',
    'zones d\'occlusion abandonnées',
  );

  // export
  static String exportDone(String fileName) => 'Fichier enregistré : $fileName';
  static const exportNothing = 'Il n\'y a aucun deck à exporter.';
  static const exporting = 'Préparation du fichier…';
  static const exportAllName = 'Carabin - toutes les cartes';
}
