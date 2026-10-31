import '../domain/note_types.dart';
import '../domain/scheduling.dart';

/// Textes du module Flashcards (français).
abstract final class TxCards {
  // ----------------------------------------------------------------- accueil
  static const title = 'Flashcards';
  static String summary(int decks, int cards) =>
      '${_n(decks, 'deck', 'decks')} · ${_n(cards, 'carte', 'cartes')}';
  static const review = 'Réviser';
  static const reviewAgain = 'Réviser à nouveau';
  static const searchDecks = 'Rechercher un deck';
  static const newDeck = 'Nouveau deck';
  static const deckName = 'Nom du deck';
  static const deckNameHint = 'Anatomie, Foie…';
  static const menu = 'Plus d\'actions';
  static const allDecks = 'Tous les decks';
  static const dueToday = 'À réviser aujourd\'hui';
  static const byCourse = 'Par matière';
  static const flat = 'À plat';
  static const noSubject = 'Sans matière';
  static const emptySubject = 'Aucun deck dans cette matière.';
  static const counterToday = 'Aujourd\'hui';
  static const counterWaiting = 'Nouvelles en attente';
  static const counterTotal = 'Cartes au total';
  static const counterHard = 'Cartes difficiles';
  static String todayDetail(int due, int fresh) =>
      '$due à revoir · $fresh ${fresh <= 1 ? 'nouvelle' : 'nouvelles'}';
  static String estimate(int minutes) =>
      minutes < 1 ? '< 1 min' : '≈ $minutes min';
  static const nothingToDo = 'Rien à réviser pour le moment.';
  static const nothingToDoDetail =
      'Tout est à jour. Revenez plus tard ou ajoutez de nouvelles cartes.';
  static const noDecks = 'Aucun deck pour l\'instant';
  static const noDecksDetail =
      'Un deck regroupe des cartes sur un même sujet. Créez-en un pour commencer.';
  static const noDeckMatches = 'Aucun deck ne correspond.';
  static const practiceTitle = 'S\'entraîner';
  static const practiceDetail =
      'Plusieurs decks à la suite, pour réviser ou pour vous noter sur 20.';
  static const practiceOpen = 'Ouvrir';
  static const dueShort = 'à revoir';
  static const newShort = 'nouvelles';
  static const cardsShort = 'cartes';
  static String cardCount(int n) => _n(n, 'carte', 'cartes');
  static String noteCount(int n) => _n(n, 'note', 'notes');

  // --------------------------------------------------------- menu d'un deck
  static const seeCards = 'Voir les cartes';
  static const studySettings = 'Réglages d\'étude';
  static const changeSubject = 'Changer de matière';
  static const linkCourse = 'Associer un poly';
  static const unlinkCourse = 'Retirer le poly associé';
  static const deadline = 'Date butoir';
  static const catchUp = 'Rattraper le retard';
  static const deleteDeck = 'Supprimer le deck';
  static String deleteDeckAsk(String name, int notes) =>
      'Supprimer « $name » et ses ${_n(notes, 'note', 'notes')} ? '
      'Les cartes et leur historique de révision seront effacés. '
      'Cette action est définitive.';
  static const pickSubject = 'Ranger dans quelle matière ?';
  static const pickCourse = 'Associer un poly';
  static const searchCourse = 'Titre du poly';
  static const noCourseFound = 'Aucun poly trouvé.';
  static const typeToSearch = 'Saisissez une partie du titre.';
  static const deadlineHelp =
      'Pour quand devez-vous savoir ce deck ? Les cartes qui reviendraient '
      'après cette date sont ramenées avant et étalées sur les jours restants. '
      'La mémorisation n\'est pas modifiée : seules les dates bougent.';
  static String deadlineDone(int n) => n == 0
      ? 'Aucune carte à avancer : tout revient déjà avant cette date.'
      : '${_n(n, 'carte avancée', 'cartes avancées')} avant la date butoir.';
  static const catchUpTitle = 'Rattrapage de retard';
  static const catchUpHelp =
      'Ne touche qu\'aux dates : les cartes jamais vues restent intactes.';
  static const postponeAll = 'Tout reporter';
  static const spreadOut = 'Étaler le retard';
  static const daysLabel = 'Nombre de jours';
  static String postponed(int n) => n == 0
      ? 'Aucune carte en retard.'
      : '${_n(n, 'carte reportée', 'cartes reportées')}.';
  static String spread(int n) => n == 0
      ? 'Aucune carte en retard.'
      : '${_n(n, 'carte étalée', 'cartes étalées')} sur les jours à venir.';

  // ---------------------------------------------------------- types de notes
  static String typeName(NoteType t) => switch (t) {
        NoteType.cloze => 'Texte à trous',
        NoteType.basic => 'Question-réponse',
        NoteType.reversed => 'Réversible',
        NoteType.typed => 'Réponse saisie',
        NoteType.occlusion => 'Occlusion d\'image',
      };
  static String typeHelp(NoteType t) => switch (t) {
        NoteType.cloze => 'Masquez des mots dans un texte : une carte par trou.',
        NoteType.basic => 'Une question au recto, la réponse au verso.',
        NoteType.reversed => 'Deux cartes : recto → verso, puis verso → recto.',
        NoteType.typed => 'Vous tapez la réponse, elle est comparée à la bonne.',
        NoteType.occlusion => 'Masquez des zones d\'une image.',
      };
  static const occlusionNote = 'Occlusion d\'image';

  // --------------------------------------------------------------- éditeur
  static const newCard = 'Nouvelle carte';
  static const editCard = 'Modifier la carte';
  static const fieldText = 'Texte';
  static const fieldFront = 'Recto';
  static const fieldBack = 'Verso';
  static const fieldExtra = 'Complément (explication, source, moyen mnémotechnique)';
  static const fieldContext = 'Contexte';
  static const fieldTags = 'Étiquettes (séparées par des espaces)';
  static const addContext = 'Ajouter un contexte';
  static const removeContext = 'Retirer le contexte';
  static const deckLabel = 'Deck';
  static const chooseDeck = 'Choisissez un deck pour ranger la carte.';
  static const add = 'Ajouter';
  static const saveChanges = 'Enregistrer';
  static String added(int n) => '${_n(n, 'carte créée', 'cartes créées')} pendant cette séance';
  static String noteAdded(int cards) => '${_n(cards, 'carte ajoutée', 'cartes ajoutées')}.';
  static const noteSaved = 'Modifications enregistrées.';
  static const bold = 'Gras';
  static const italic = 'Italique';
  static const underline = 'Souligné';
  static const highlight = 'Surligné';
  static const cloze = 'Trou';
  static const clozePrev = 'Numéro de trou précédent';
  static const clozeNext = 'Numéro de trou suivant';
  static const clozeSelectFirst = 'Sélectionnez d\'abord le texte à masquer.';
  static const preview = 'Aperçu';
  static const previewQuestion = 'Question';
  static const previewAnswer = 'Réponse';
  static const previewEmpty = 'L\'aperçu apparaît ici.';
  static const duplicateTitle = 'Carte en double ?';
  static const duplicate = 'Une carte identique existe déjà dans ce deck. L\'ajouter quand même ?';
  static const addAnyway = 'Ajouter quand même';
  static const clozeExample = 'Le {{c1::cœur}} pompe le sang vers les {{c2::artères}}.';
  static const tapToSeeCloze = 'Exemple : sélectionnez un mot puis appuyez sur « Trou ».';
  static String issue(NoteIssue i) => switch (i) {
        NoteIssue.emptyFront => 'Le recto (ou le texte) est vide.',
        NoteIssue.emptyBack => 'Le verso est vide.',
        NoteIssue.noCloze =>
          'Il faut au moins un trou : sélectionnez un mot puis appuyez sur « Trou ».',
        NoteIssue.clozeNotClosed =>
          'Un trou n\'est pas refermé : vérifiez les accolades {{ }}.',
        NoteIssue.noImage => 'Choisissez d\'abord une image.',
        NoteIssue.noMask => 'Dessinez au moins une zone à masquer.',
      };
  static const shortcutsHint =
      'Ctrl+Entrée : ajouter · Ctrl+Maj+C : trou · Ctrl+B / I / U : mise en forme';

  // ------------------------------------------------------ cartes d'un deck
  static String deckHeader(String name, int notes, int cards) =>
      '$name · ${_n(notes, 'note', 'notes')} · ${_n(cards, 'carte', 'cartes')}';
  static const searchNotes = 'Rechercher dans le deck';
  static const noNotes = 'Ce deck ne contient pas encore de carte.';
  static const noNoteMatches = 'Aucune note ne correspond.';
  static const selectNote = 'Choisissez une note pour la voir.';
  static const pause = 'Mettre en pause';
  static const resume = 'Rétablir';
  static const paused = 'En pause';
  static const edit = 'Modifier';
  static const deleteNote = 'Supprimer la note';
  static String deleteNoteAsk(int cards) =>
      'Supprimer cette note et ${_n(cards, 'sa carte', 'ses cartes')} ? '
      'L\'historique de révision est effacé. Cette action est définitive.';
  static String deleteManyAsk(int n) =>
      'Supprimer ${_n(n, 'note', 'notes')} sélectionnée${n > 1 ? 's' : ''} ? '
      'Cette action est définitive.';
  static const moveNotes = 'Déplacer vers un autre deck';
  static const pickDeck = 'Choisir un deck';
  static const selectAll = 'Tout sélectionner';
  static const selectNone = 'Tout désélectionner';
  static String selected(int n) => _n(n, 'sélectionnée', 'sélectionnées');
  static const pauseSelected = 'Mettre en pause';
  static const resumeSelected = 'Rétablir';
  static String cardOrdinal(int ord) => 'carte ${ord + 1}';
  static String clozeOrdinal(int n) => 'trou $n';

  // ---------------------------------------------------------------- révision
  static const quit = 'Quitter';
  static const undo = 'Annuler la dernière réponse';
  static const addNote = 'Ajouter une note';
  static const bury = 'Enterrer la notion jusqu\'à demain';
  static const suspend = 'Mettre la carte de côté';
  static const deleteCard = 'Supprimer la carte';
  static const showAnswer = 'Afficher la réponse';
  static const hideAnswer = 'Cacher la réponse';
  static const showContext = 'Afficher le contexte';
  static const hideContext = 'Masquer le contexte';
  static const pillNew = 'Nouvelles';
  static const pillLearning = 'Apprentissage';
  static const pillReview = 'À revoir';
  static String gradeLabel(Grade g) => switch (g) {
        Grade.again => 'Encore',
        Grade.hard => 'Difficile',
        Grade.good => 'Bien',
        Grade.easy => 'Facile',
      };
  static const typeYourAnswer = 'Tapez votre réponse';
  static const typedRight = 'Bonne réponse';
  static const typedWrong = 'Ce n\'est pas la bonne réponse';
  static const expected = 'Réponse attendue';
  static String firstTime() => 'première fois';
  static String seenTimes(int reps, int lapses) =>
      'vue ${_n(reps, 'fois', 'fois')}${lapses > 0 ? ' · oubliée ${_n(lapses, 'fois', 'fois')}' : ''}';
  static String position(int done, int total) => '$done / $total';
  static const done = 'Terminé';
  static String doneSummary(int n) => n == 0
      ? 'Aucune carte révisée.'
      : '${_n(n, 'carte révisée', 'cartes révisées')}.';
  static String nextReview(String when, int n) =>
      'Prochaine révision : $when — ${_n(n, 'carte programmée', 'cartes programmées')}.';
  static const nothingScheduled = 'Aucune carte programmée pour les prochains jours.';
  static const backToDecks = 'Retour aux decks';
  static const sessionPanel = 'Session';
  static const cardPanel = 'Carte';
  static const nextPanel = 'Prochaine échéance';
  static const reviewed = 'Révisées';
  static const remaining = 'Restantes';
  static const minutes = 'Minutes';
  static const secondsPerCard = 'Secondes par carte';
  static const passes = 'Passages';
  static const lapsesLabel = 'Oublis';
  static const typeLabel = 'Type';
  static const shortcuts = 'Raccourcis';
  static const shortcutsLine =
      'Révéler : Entrée · Noter : 1 à 4 · Contexte : H · Mettre de côté : S · '
      'Enterrer : − · Annuler : Ctrl+Z · Supprimer : Ctrl+Suppr';
  static const leechNotice =
      'Cette carte a été oubliée trop souvent : elle est mise de côté. '
      'Réécrivez-la plutôt que de la répéter.';
  static const leechNoticeKept =
      'Cette carte a été oubliée trop souvent : pensez à la réécrire.';
  static const buried = 'Notion enterrée jusqu\'à demain.';
  static const suspendedNotice = 'Carte mise de côté.';
  static const cardDeleted = 'Carte supprimée.';
  static const deleteCardAsk =
      'Supprimer définitivement cette carte (et sa notion) ? '
      'L\'historique de révision est effacé.';
  static const undone = 'Réponse annulée.';
  static const nothingToUndo = 'Rien à annuler.';
  static const orderAsk = 'Dans quel ordre ?';
  static const orderShuffled = 'Mélangées';
  static const orderCourse = 'Dans l\'ordre du cours';
  static const orderUsual = 'Comme d\'habitude';
  static const unknownCardType = 'Ce type de carte ne peut pas encore s\'afficher ici.';

  // ------------------------------------------------------------- s'entraîner
  static const practiceNew = 'Nouvelle séance';
  static const practiceHistory = 'Historique';
  static const practiceMode = 'Mode';
  static const modeReview = 'Réviser';
  static const modeReviewDetail = 'Chaque carte est reprogrammée selon votre réponse.';
  static const modeTest = 'Se tester';
  static const modeTestDetail =
      'Je savais ou pas : une note sur 20 à la fin, rien n\'est reprogrammé.';
  static const practiceCount = 'Nombre de cartes tirées au hasard';
  static const countAll = 'Tout';
  static const countCustom = 'Autre nombre';
  static const practiceOrder = 'Ordre';
  static const orderMixed = 'Mélangé';
  static const orderInCourse = 'Ordre du cours';
  static const startReview = 'Réviser';
  static const startTest = 'Se tester';
  static const pickAtLeastOne = 'Cochez au moins un deck.';
  static const nothingToDraw = 'Les decks cochés ne contiennent aucune carte à tirer.';
  static const noPractice = 'Aucune séance enregistrée.';
  static const noPracticeDetail = 'Vos notes sur 20 apparaîtront ici après un « Se tester ».';
  static const didntKnow = 'Je ne savais pas';
  static const knew = 'Je savais';
  static String testProgress(int n, int total, int right) =>
      '$n / $total · ${_n(right, 'juste', 'justes')}';
  static String testScore(double s) =>
      '${s.toStringAsFixed(s == s.roundToDouble() ? 0 : 1).replaceAll('.', ',')} / 20';
  static String testRight(int right, int total, int percent) =>
      '$right juste${right > 1 ? 's' : ''} sur $total · $percent %';
  static const nothingReprogrammed = 'Rien n\'a été reprogrammé : cette séance ne change pas votre calendrier de révision.';
  static const redraw = 'Refaire un tirage';
  static const seeHistory = 'Voir l\'historique';
  static String appreciation(double s) {
    if (s >= 18) return 'Excellent';
    if (s >= 16) return 'Très bien';
    if (s >= 14) return 'Bien';
    if (s >= 12) return 'Assez bien';
    if (s >= 10) return 'Passable';
    if (s >= 7) return 'À consolider';
    return 'À retravailler';
  }
  static String duration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m == 0 ? '$s s' : '$m min ${s.toString().padLeft(2, '0')} s';
  }
  static const deletePractice = 'Supprimer cette séance';

  // --------------------------------------------------------------- réglages
  static const generalSettings = 'Réglages d\'étude';
  static String deckSettings(String name) => 'Réglages d\'étude · $name';
  static const ownSettings = 'Ce deck a ses propres réglages';
  static const followsGeneral =
      'Ce deck suit les réglages généraux (affichés ci-dessous, en lecture seule).';
  static const strictestWins =
      'Le plafond général s\'applique aussi : le plus strict l\'emporte.';
  static const onePerNote = 'Une seule carte par notion et par jour';
  static const onePerNoteDetail =
      'Un texte à six trous fabrique six cartes, mais une seule est servie '
      'par jour ; les autres reviennent les jours suivants.';
  static const studyOrder = 'Ordre de passage';
  static const newPerDay = 'Nouvelles cartes par jour';
  static const reviewsPerDay = 'Révisions par jour';
  static const noLimit = 'Sans plafond';
  static const retention = 'Exigence de mémorisation';
  static String retentionValue(double r) => '${(r * 100).round()} %';
  static const retentionLow = 'Chaîne large';
  static const retentionHigh = 'Chaîne serrée';
  static String milestones(List<int> days) =>
      'Si vous la retrouvez à chaque fois : ${days.map((d) => 'J+$d').join(', ')}. '
      'Une carte ratée retombe beaucoup plus tôt.';
  static const leechTitle = 'Cartes maudites';
  static const leechThreshold = 'Nombre d\'oublis avant d\'être jugée maudite';
  static const leechAction = 'Action';
  static const leechSuspend = 'Mettre de côté';
  static const leechNone = 'Ne rien faire';
  static const showPassCounter = 'Afficher le compteur de passages sur la carte';
  static const resetDefaults = 'Revenir aux valeurs par défaut';
  static String loadEstimate(int perDay, int? cap) {
    final base = '≈ $perDay révisions par jour une fois le rythme installé';
    if (cap == null) return base;
    return perDay > cap
        ? '$base, au-delà de votre plafond de $cap : le retard s\'accumulerait.'
        : '$base, sous votre plafond de $cap.';
  }
  static const settingsSaved = 'Réglages enregistrés.';

  static const _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
    'septembre', 'octobre', 'novembre', 'décembre',
  ];

  /// « aujourd'hui à 15:20 », « demain », « jeudi », « 12 mars »…
  /// [dayDiff] est le nombre de jours d'étude entre aujourd'hui et [at].
  static String relativeDay(DateTime at, int dayDiff) {
    if (dayDiff <= 0) {
      final h = at.hour.toString().padLeft(2, '0');
      final m = at.minute.toString().padLeft(2, '0');
      return 'aujourd\'hui à $h:$m';
    }
    if (dayDiff == 1) return 'demain';
    if (dayDiff < 7) return _weekdays[at.weekday - 1];
    return '${at.day} ${_months[at.month - 1]}';
  }

  static String _n(int n, String one, String many) => '$n ${n <= 1 ? one : many}';
}
