import '../data/errors.dart';
import 'textes_cartes.dart';

/// Couche de textes de l'interface (français). Aucun texte d'écran ne doit
/// être écrit en dur ailleurs : on passe par cette classe, ce qui prépare
/// l'internationalisation.
abstract final class Tx {
  // ---------------------------------------------------------------- commun
  static const appName = 'Carabin';
  static const cancel = 'Annuler';
  static const create = 'Créer';
  static const validate = 'Valider';
  static const save = 'Enregistrer';
  static const delete = 'Supprimer';
  static const rename = 'Renommer';
  static const close = 'Fermer';
  static const back = 'Retour';
  static const open = 'Ouvrir';
  static const search = 'Rechercher';
  static const later = 'Plus tard';
  static const more = 'Plus d\'options';
  static const yes = 'Oui';
  static const no = 'Non';
  static const name = 'Nom';
  static const moveTo = 'Déplacer vers…';
  static const comingSoon = 'Ce module arrive bientôt.';

  static String plural(int n, String one, String many) =>
      '$n ${n <= 1 ? one : many}';

  /// « 10 min », « 3 j », « 2 mois »… (délai affiché sous les boutons de réponse).
  static String interval(Duration d) {
    final minutes = d.inSeconds / 60;
    if (minutes < 1) return '< 1 min';
    if (minutes < 60) return '${minutes.round()} min';
    final hours = d.inMinutes / 60;
    if (hours < 24) return '${hours.round()} h';
    final days = d.inMinutes / 1440;
    if (days < 31) return '${days.round()} j';
    final months = days / 30.4375;
    if (months.round() < 12) return '${months.round()} mois';
    final years = days / 365.25;
    final text = years.toStringAsFixed(1).replaceAll('.', ',');
    final trimmed = text.endsWith(',0') ? text.substring(0, text.length - 2) : text;
    return '$trimmed an${years >= 2 ? 's' : ''}';
  }

  // ------------------------------------------------------------- navigation
  static const navDashboard = 'Tableau de bord';
  static const navCourses = 'Cours';
  static const navFlashcards = 'Flashcards';
  static const navQcm = 'QCM';
  static const navPlanning = 'Planning';
  static const navSettings = 'Réglages';

  // --------------------------------------------------- dossier de travail
  static const setupTitle = 'Où ranger vos données ?';
  static const setupIntro =
      'Carabin garde tout dans un dossier ordinaire sur cet appareil : vos '
      'cours, vos cartes, vos QCM et la base de données. Rien n\'est envoyé '
      'sur Internet, l\'appli fonctionne sans connexion.';
  static const setupCreateDefault = 'Créer le dossier « Carabin »';
  static const setupOpenExisting = 'Ouvrir un dossier existant';
  static const setupWillCreate = 'Dossier créé dans :';
  static const setupNotFound =
      'Le dossier de travail n\'a pas été retrouvé. Il a peut-être été '
      'déplacé : choisissez-le de nouveau, ou créez-en un nouveau.';
  static const setupNotWorkspace =
      'Ce dossier n\'est pas un dossier Carabin et il n\'est pas vide. '
      'Choisissez un dossier vide ou un dossier Carabin existant.';
  static const setupFailed =
      'Impossible d\'ouvrir ce dossier. Vérifiez qu\'il est accessible et '
      'qu\'il reste de la place sur l\'appareil.';
  static const setupBusy = 'Ouverture du dossier…';

  // ------------------------------------------------------------------ cours
  static const coursesTitle = 'Cours';
  static const coursesEmptyTitle = 'Aucune année pour l\'instant';
  static const coursesEmptyBody =
      'Créez une année (par exemple « DFGSM2 2025-2026 »), puis ajoutez vos '
      'matières, vos thèmes et vos polys.';
  static const newYear = 'Nouvelle année';
  static const newSemester = 'Nouveau semestre';
  static const newSubject = 'Nouvelle matière';
  static const newTopic = 'Nouveau thème';
  static const yearName = 'Année (ex. DFGSM2 2025-2026)';
  static const semesterName = 'Semestre (ex. Semestre 3)';
  static const subjectName = 'Nom de la matière';
  static const topicName = 'Nom du thème';
  static const colorTitle = 'Couleur de la matière';
  static const colorCustom = 'Couleur personnalisée (hexadécimal)';
  static const searchDocs = 'Chercher un poly…';
  static const noResults = 'Aucun résultat.';
  static const recents = 'Récents';
  static const syncFolder = 'Synchroniser le dossier';
  static const importFiles = 'Importer';
  static const importing = 'Import en cours…';
  static const importTopicEmpty =
      'Ce thème est vide. Importez un PDF, un document Word ou une image.';
  static const noTopics = 'Aucun thème. Créez-en un pour y ranger vos polys.';
  static const noSubjects = 'Aucune matière dans ce semestre.';
  static const noSemesters =
      'Aucun semestre. Créez-en un pour y ajouter des matières.';
  static const documentsLabel = 'Documents';
  static const myWork = 'Mon travail';
  static const readings = 'Lectures';
  static const neverReread = 'pas encore lu';
  static const openDocument = 'Consulter';
  static const archiveDoc = 'Archiver';
  static const deleteForever = 'Supprimer définitivement';
  static const examDate = 'Date d\'examen';
  static const noExamDate = 'Aucune date d\'examen';
  static const removeDate = 'Retirer la date';
  static const moveTopicTitle = 'Déplacer le thème dans quelle matière ?';
  static const moveDocTitle = 'Déplacer le document dans quel thème ?';
  static const nothingToMoveTo = 'Aucune destination disponible.';
  static const previewUnavailable =
      'Ce type de fichier ne peut pas être affiché dans Carabin. Il reste '
      'rangé dans le thème.';
  static const pdfError = 'Ce PDF n\'a pas pu être ouvert.';
  static const fileMissing =
      'Le fichier est introuvable sur le disque. Il a peut-être été déplacé '
      'ou supprimé hors de l\'appli.';
  static const page = 'Page';
  static const zoomIn = 'Agrandir';
  static const zoomOut = 'Réduire';
  static const readThrough = 'Relu';
  static const readN = 'Lecture';

  static String subjectSummary(int topics, int docs) =>
      '${plural(topics, 'thème', 'thèmes')} · ${plural(docs, 'poly', 'polys')}';

  static String confirmDeleteTitle(String what) => 'Supprimer « $what » ?';
  static const confirmDeleteLevelBody =
      'Le dossier et ses documents sont déplacés dans le dossier « Archives » '
      'de Carabin : rien n\'est effacé du disque.';
  static const confirmArchiveDocBody =
      'Le document est déplacé dans le dossier « Archives » : rien n\'est '
      'effacé du disque.';
  static const confirmDeleteForeverBody =
      'Le fichier sera effacé du disque et ne pourra pas être récupéré.';
  static const confirmDeleteForeverAgain =
      'Dernière confirmation : effacer ce fichier définitivement ?';

  static String syncReport(int added, int missing) {
    final a = added == 0
        ? 'Aucun nouveau fichier trouvé.'
        : '${plural(added, 'fichier ajouté', 'fichiers ajoutés')} à l\'appli.';
    final m = missing == 0
        ? ''
        : ' ${plural(missing, 'document est introuvable', 'documents sont introuvables')} '
            'sur le disque (rien n\'a été supprimé).';
    return '$a$m';
  }

  static String importedCount(int n) => n == 1
      ? '1 document importé.'
      : '$n documents importés.';

  // --------------------------------------------------------------- erreurs
  static String errorMessage(Object e) {
    if (e is EmptyNameError) return 'Le nom ne peut pas être vide.';
    if (e is NameTakenError) {
      return 'Le nom « ${e.name} » est déjà utilisé à cet endroit '
          '(ou donnerait le même nom de dossier).';
    }
    if (e is NotFoundError) {
      return 'Cet élément n\'existe plus. Revenez en arrière et réessayez.';
    }
    if (e is InvalidNoteError) return TxCards.issue(e.issue);
    if (e is FileProblemError) {
      return 'Problème avec le disque : ${e.detail}';
    }
    return 'Une erreur inattendue est survenue. Réessayez ; si elle revient, '
        'signalez-la sur la page du projet.';
  }
}
