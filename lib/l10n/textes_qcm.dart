import '../domain/qcm/exam.dart';
import '../domain/qcm/grading.dart';
import '../domain/qcm/question.dart';
import 'textes.dart';

/// Textes du module QCM.
abstract final class TxQcm {
  // ------------------------------------------------------------ navigation
  static const title = 'QCM';
  static const tabPass = 'Passer';
  static const tabHistory = 'Historique';
  static const tabEdit = 'Édition';
  static const subExams = 'Épreuves';
  static const subPastPapers = 'Annales';
  static const subPractice = 'Entraînements';
  static const nextExam = 'Prochaine épreuve';
  static const practice = 'S\'entraîner';
  static const newSeries = 'Série';
  static const newSeriesTitle = 'Nouvelle série';
  static const newSeriesLabel = 'Nom de la série';
  static const importExam = 'Ouvrir une épreuve reçue…';
  static const searchExam = 'Rechercher une épreuve';
  static const filterAll = 'Toutes les épreuves';
  static const filterNever = 'Jamais passées';
  static const noSubject = 'Sans matière';
  static const emptyTitle = 'Aucune épreuve pour l\'instant';
  static const emptyBody =
      'Écrivez une série de questions, ou ouvrez le fichier d\'une épreuve '
      'reçue d\'un camarade.';
  static const emptyPastPapers =
      'Aucune annale. Mettez une épreuve dans les annales depuis son menu, '
      'ou mettez « annale » dans son titre.';
  static const emptyFilter = 'Aucune épreuve ne correspond.';
  static const nothingYet = 'Rien pour l\'instant.';

  // ----------------------------------------------------------------- carte
  static const compose = 'Composer';
  static const nothingToCompose =
      'Cette série n\'a encore aucune question prête à poser.';
  static const edit = 'Éditer';
  static const nothingToPass = 'Aucune épreuve prête à être passée.';
  static String practiceTitle(int n) =>
      n == 1 ? 'Entraînement' : 'Entraînement · $n épreuves';
  static const handwritten = 'Écrite à la main';
  static const received = 'Reçue';
  static const noQuestions = 'Aucune question';
  static const lastNote = 'Dernière note';
  static const neverPassed = 'jamais passée';
  static const menuEdit = 'Éditer';
  static const menuSubject = 'Changer de matière';
  static const menuToPastPapers = 'Mettre dans les annales';
  static const menuFromPastPapers = 'Sortir des annales';
  static const menuAttach = 'Rattacher à un poly';
  static const menuDuplicate = 'Dupliquer';
  static const menuShare = 'Partager';
  static const menuSelect = 'Sélectionner plusieurs';
  static const menuDelete = 'Supprimer';
  static const pickSubject = 'Dans quelle matière ?';
  static const pickPoly = 'Rattacher à quel poly ?';
  static const searchPoly = 'Chercher un poly';
  static const detachPoly = 'Détacher du poly';
  static const duplicateSuffix = ' (copie)';

  static String questionCount(int n) =>
      n == 0 ? noQuestions : Tx.plural(n, 'question', 'questions');
  static String unfinished(int n) => '$n à finir';
  static String passedTimes(int n) =>
      n == 0 ? neverPassed : 'passée ${Tx.plural(n, 'fois', 'fois')}';
  static String lastNoteValue(double note) =>
      '$lastNote ${formatNumber(note)} / 20';

  // -------------------------------------------------------- sélection
  static const selectAll = 'Tout sélectionner';
  static const selectNone = 'Tout désélectionner';
  static const move = 'Déplacer';
  static const toPastPapers = 'Vers les annales';
  static const done = 'Terminé';
  static String selected(int n) => n == 0
      ? 'Aucune sélection'
      : Tx.plural(n, 'sélectionnée', 'sélectionnées');
  static String confirmDeleteExams(int n, String? title) => n == 1
      ? 'L\'épreuve « $title » et ses questions seront supprimées. Les copies '
            'déjà rendues sont conservées.'
      : '$n épreuves et leurs questions seront supprimées. Les copies déjà '
            'rendues sont conservées.';
  static const confirmDeleteTitle = 'Supprimer ?';

  // ---------------------------------------------------------------- éditeur
  static const editorBack = 'Retour aux séries';
  static const rename = 'Renommer la série';
  static const renameLabel = 'Titre';
  static const preview = 'Aperçu';
  static const shuffleOrder = 'Mélanger';
  static const shuffleConfirm =
      'Les questions seront remises dans un ordre au hasard (un cas reste '
      'entier). Continuer ?';
  static const duplicate = 'Dupliquer';
  static const items = 'Items';
  static const itemsHint = 'Numéros des items des EDN (ex. 12, 224)';
  static const itemsTitle = 'Items des EDN';
  static const addQcm = 'QCM';
  static const addQroc = 'QROC';
  static const addTcs = 'TCS';
  static const addQzp = 'QZP';
  static const addCase = 'Cas';
  static const addCaseTitle = 'Ajouter un cas';
  static const addToCase = 'Ajouter une question au dossier';
  static const listTitle = 'Questions';
  static const noBody = '(énoncé à écrire)';
  static const showCorrection = 'Voir la correction';
  static const caseSectionTitle = 'Cas clinique';
  static String caseQuestions(int n) =>
      n == 0 ? caseNoQuestion : Tx.plural(n, 'question', 'questions');
  static const noQuestionYet =
      'Aucune question. Ajoutez-en avec les boutons ci-dessus.';
  static const pickQuestion = 'Choisissez une question à modifier.';
  static const moveUp = 'Monter';
  static const moveDown = 'Descendre';
  static const deleteQuestion = 'Supprimer la question';
  static const deleteCase = 'Supprimer le cas';
  static const toFinish = 'à finir';
  static const ready = 'prête';
  static const topPreviewTitle = 'Tel que ce sera posé';
  static const validationTitle = 'À compléter';
  static const allGood = 'Cette question est prête.';
  static const tabQuestions = 'Questions';
  static const tabForm = 'Édition';
  static const tabPreview = 'Aperçu';
  static String readyCounter(int ready, int unfinished) =>
      '${Tx.plural(ready, 'prête', 'prêtes')} · $unfinished à finir';
  static String questionLabel(int n) => 'Question $n';
  static String confirmDeleteQuestion(int n) => 'Supprimer la question $n ?';
  static String confirmDeleteCase(String name, int n) => n == 0
      ? 'Supprimer « $name » ?'
      : 'Supprimer « $name » et ses ${Tx.plural(n, 'question', 'questions')} ?';
  static const confirmChangeKindTitle = 'Changer de type ?';
  static const changeKind = 'Changer de type';
  static const confirmChangeKind =
      'Changer de type efface les champs propres à l\'ancien type '
      '(propositions, zones…). Continuer ?';

  // ------------------------------------------------------------ formulaire
  static const kindQcm = 'QCM';
  static const kindQroc = 'QROC';
  static const kindTcs = 'TCS';
  static const kindQzp = 'QZP';
  static const limitedAnswers = 'Nombre de réponses attendu connu (QRP)';
  static const inCase = 'Dans un cas clinique';
  static const noCase = 'Non, question isolée';
  static const body = 'Énoncé';
  static const explanation =
      'Explication (pourquoi c\'est celle-là, et le piège des autres)';
  static const points = 'Points';
  static const images = 'Images';
  static const addImage = 'Ajouter une image';
  static const removeImage = 'Retirer l\'image';
  static const propositions = 'Propositions';
  static const propositionHint = 'Texte de la proposition';
  static const markCorrect = 'Bonne réponse';
  static const addProposition = 'Ajouter une proposition';
  static const removeProposition = 'Supprimer la proposition';
  static const criticalTooltipCorrect =
      'Indispensable : l\'oublier annule la question';
  static const criticalTooltipWrong =
      'Inacceptable : la cocher annule la question';
  static const critical = 'Critique';
  static const bold = 'Gras';
  static const italic = 'Italique';
  static const underline = 'Souligné';
  static const highlight = 'Surligné';
  static String shapeNote(ChoiceShape s, int correct) => switch (s) {
    ChoiceShape.qru => 'QRU : une seule bonne réponse.',
    ChoiceShape.qrm =>
      'QRM : $correct bonnes réponses (cochez-en une seule pour un QRU).',
    ChoiceShape.qrp =>
      correct == 0
          ? 'QRP : cochez les réponses attendues.'
          : 'QRP : le candidat devra cocher ${Tx.plural(correct, 'réponse', 'réponses')}.',
  };

  static const qrocNature = 'Nature de la réponse attendue';
  static const qrocNatureHint = 'Un texte';
  static const qrocMaxLines = 'Longueur maximale';
  static const qrocNoLimit = 'Aucune';
  static String qrocLines(int n) => Tx.plural(n, 'ligne', 'lignes');
  static const qrocModel = 'Réponse modèle (montrée à la correction)';
  static const qrocElements = 'Éléments attendus';
  static const qrocElementsHelp =
      'Chaque élément rapporte ses points. « ; » sépare ce qu\'il faut tous '
      'trouver, « | » des synonymes acceptés. Sans élément attendu, '
      'l\'étudiant s\'évalue lui-même face à la réponse modèle.';
  static const qrocElement = 'Élément attendu';
  static const qrocElementHint = 'ex. infarctus|IDM ; troponine';
  static const addElement = 'Ajouter un élément';
  static const removeElement = 'Supprimer l\'élément';

  static const tcsHypothesis = 'Si vous pensez à…';
  static const tcsNewInfo = '…et que vous trouvez…';
  static const tcsLow = 'Bas de l\'échelle (−2)';
  static const tcsHigh = 'Haut de l\'échelle (+2)';
  static const tcsLowDefault = 'L\'hypothèse est infirmée';
  static const tcsHighDefault = 'L\'hypothèse est confirmée';
  static const tcsPanel = 'Réponses du panel d\'experts';
  static const tcsPanelHelp =
      'Indiquez combien d\'experts ont choisi chaque niveau. Le niveau le '
      'plus choisi vaut 1 point, les autres au prorata.';
  static const tcsTherefore = 'Alors cette hypothèse est…';
  static String tcsLevel(int level) => level > 0
      ? '+$level'
      : level < 0
      ? '−${-level}'
      : '0';
  static String tcsExperts(int n) => Tx.plural(n, 'expert', 'experts');
  static const addExpert = 'Ajouter un expert';
  static const removeExpert = 'Retirer un expert';

  static const qzpImage = 'Image';
  static const qzpPickImage = 'Choisir l\'image à pointer';
  static const qzpChangeImage = 'Changer l\'image';
  static const qzpDrawHelp =
      'Tracez avec le doigt ou la souris les zones où il faut cliquer. '
      'Touchez une zone pour la sélectionner.';
  static const qzpDeleteZone = 'Supprimer la zone';
  static const qzpClearZones = 'Tout effacer';
  static String qzpZones(int n) => Tx.plural(n, 'zone', 'zones');
  static const qzpTapHelp = 'Touchez l\'image à l\'endroit voulu.';
  static const qzpYourPoint = 'Votre point';
  static const qzpChangeConfirm =
      'Les zones déjà tracées seront effacées avec l\'ancienne image. '
      'Continuer ?';

  static const tcsContext = 'Situation clinique (facultatif)';
  static const pointsInvalid = 'Un nombre entre 0,01 et 1000';
  static const pointsHint = 'ex. 1 ou 0,5';
  static const imageCaption = 'Image jointe à l\'énoncé';
  static const pickCaseLabel = 'Cas';
  static const imageAdded = 'Image ajoutée.';
  static const elementPoints = 'Points';

  // ------------------------------------------------------------------- cas
  static const caseGenre = 'Genre';
  static const caseTitle = 'Titre du cas';
  static const caseTitleHint = 'Facultatif';
  static const caseContext = 'Contexte, commun à toutes les questions du cas';
  static const caseArticle = 'Article';
  static const caseArticleText = 'Texte de l\'article';
  static const caseArticleHelp =
      'Joignez l\'article en PDF ou collez son texte. Il reste consultable '
      'pendant toutes les questions.';
  static const caseAttachPdf = 'Joindre un PDF';
  static const caseChangePdf = 'Changer le PDF';
  static const caseRemovePdf = 'Retirer le PDF';
  static const caseOpenArticle = 'Ouvrir l\'article';
  static const caseHideArticle = 'Replier l\'article';
  static const caseShowArticle = 'Afficher l\'article';
  static const articleNone = 'Aucun article pour ce cas.';
  static const articleFileMissing =
      'Le fichier de l\'article est introuvable sur cet appareil.';
  static const caseNoQuestion = 'Aucune question dans ce cas.';
  static String genreName(CaseGenre g) => switch (g) {
    CaseGenre.progressive => 'Dossier progressif',
    CaseGenre.kfp => 'KFP',
    CaseGenre.lca => 'Lecture critique d\'article',
  };
  static String genreHelp(CaseGenre g) => switch (g) {
    CaseGenre.progressive =>
      'Un cas qui évolue : chaque question apporte la suite. Il n\'est jamais '
          'coupé ni mélangé, et une question ne se rouvre plus une fois la '
          'suite vue.',
    CaseGenre.kfp => 'Un cas court : les décisions clés.',
    CaseGenre.lca => 'Un article et plusieurs questions à son sujet.',
  };
  static String caseName(CaseInfo info, int index) =>
      info.title.trim().isNotEmpty
      ? info.title.trim()
      : '${genreName(info.genre)} $index';
  static String articleBanner(int n, int total) =>
      'Lecture critique d\'article · question $n sur $total';

  // -------------------------------------------------------------- question
  static String kindBadge(Question q) => switch (q) {
    ChoiceQuestion c => switch (c.shape) {
      ChoiceShape.qru => 'QRU',
      ChoiceShape.qrm => 'QRM',
      ChoiceShape.qrp => 'QRP',
    },
    QrocQuestion() => 'QROC',
    TcsQuestion() => 'TCS',
    QzpQuestion() => 'QZP',
  };

  static String kindHint(Question q) => switch (q) {
    ChoiceQuestion c => switch (c.shape) {
      ChoiceShape.qru => 'Une seule réponse',
      ChoiceShape.qrm => 'Plusieurs réponses possibles',
      ChoiceShape.qrp =>
        'Cochez ${Tx.plural(c.correctCount, 'réponse', 'réponses')}',
    },
    QrocQuestion() => 'Réponse courte',
    TcsQuestion() => 'Choisissez un niveau',
    QzpQuestion() => 'Touchez l\'image',
  };

  static String scoringHint(Question q, Scoring s) => switch (q) {
    ChoiceQuestion c => switch (c.shape) {
      ChoiceShape.qru => 'Tout ou rien',
      ChoiceShape.qrm =>
        s == Scoring.edn
            ? 'Barème EDN : 1 · 0,5 · 0,2 · 0'
            : 'Une part par proposition',
      ChoiceShape.qrp => 'Bonnes réponses cochées sur attendues',
    },
    QrocQuestion c => c.autoGraded ? 'Éléments attendus' : 'À vous d\'évaluer',
    TcsQuestion() => 'Au prorata du panel',
    QzpQuestion() => 'Tout ou rien',
  };

  static String pointsLabel(double points) =>
      points == 1 ? '1 point' : '${formatNumber(points)} points';

  static String issueMessage(QuestionIssue i) => switch (i) {
    QuestionIssue.emptyBody => 'Écrivez l\'énoncé.',
    QuestionIssue.tooFewPropositions => 'Ajoutez au moins deux propositions.',
    QuestionIssue.noCorrectProposition => 'Cochez au moins une bonne réponse.',
    QuestionIssue.qrocNothingToCompare =>
      'Écrivez une réponse modèle ou des éléments attendus.',
    QuestionIssue.tcsHypothesis => 'Écrivez l\'hypothèse.',
    QuestionIssue.tcsNewInfo => 'Écrivez l\'information nouvelle.',
    QuestionIssue.tcsPanel => 'Indiquez les réponses du panel d\'experts.',
    QuestionIssue.qzpImage => 'Choisissez une image.',
    QuestionIssue.qzpZone => 'Dessinez au moins une zone-réponse.',
  };

  // ------------------------------------------------------- partage et import
  static const shareDone = 'Épreuve enregistrée';
  static String shared(String fileName) => 'Épreuve enregistrée : $fileName';
  static String sharedMissing(int n) =>
      '${Tx.plural(n, 'image manque', 'images manquent')} sur cet appareil et '
      'ne sont pas dans le fichier.';
  static const importTooBig =
      'Ce fichier est trop volumineux pour une épreuve.';
  static const importReplaceTitle = 'Cette épreuve existe déjà';
  static String importReplaceMessage(String title) =>
      'Vous avez déjà « $title » (même épreuve). Vous pouvez remplacer son '
      'contenu — vos copies sont gardées — ou garder les deux.';
  static const importReplace = 'Remplacer';
  static const importKeepBoth = 'Garder les deux';
  static const importReportTitle = 'Épreuve reçue';
  static String importReportLine(String title, int questions, bool replaced) =>
      replaced
      ? '« $title » remplacée : ${Tx.plural(questions, 'question', 'questions')}.'
      : '« $title » ajoutée : ${Tx.plural(questions, 'question', 'questions')}.';
  static String importSubject(bool linked) => linked
      ? 'Rangée dans la matière du même nom.'
      : 'Sans matière : à ranger.';
  static String importMedia(int n) =>
      '${Tx.plural(n, 'image ou article repris', 'images ou articles repris')} '
      'du fichier.';
  static String importMediaMissing(int n) =>
      '${Tx.plural(n, 'image absente', 'images absentes')} du fichier : les '
      'questions concernées s\'afficheront sans.';
  static String importMediaRejected(int n) =>
      '${Tx.plural(n, 'fichier refusé', 'fichiers refusés')} (format non pris '
      'en charge).';
  static const importOpen = 'Ouvrir l\'épreuve';
  static const pickFile = 'Choisir un fichier';
  static const noPoly = 'Aucun poly rattaché';
  static String polyAttached(String title) => 'Poly : $title';
  static const itemsNone = 'Aucun item';
  static String itemsValue(String items) => 'Items : $items';
  static const seriesDuplicated = 'Série dupliquée.';

  // ------------------------------------------------------------ réglages
  static const setupTitle = 'Réglages du passage';
  static const setupStart = 'Commencer';
  static const setupPart = 'Ne passer qu\'une partie des questions';
  static const setupPartCount = 'Nombre de questions';
  static const setupRandom = 'Tirées au hasard';
  static const setupCorrection = 'Correction';
  static const correctionEnd = 'À la fin';
  static const correctionEach = 'Après chaque question';
  static const setupBack = 'Pouvoir revenir sur une question validée';
  static const setupTimer = 'Minuteur';
  static const setupTimerMinutes = 'Durée en minutes';
  static const setupScoring = 'Barème';
  static const scoringEdn = 'EDN';
  static const scoringPoints = 'Points';
  static const scoringEdnHelp =
      'Comme à l\'examen : les QRM perdent des points selon les erreurs et '
      'une réponse inacceptable annule la question.';
  static const scoringPointsHelp =
      'Chaque question vaut son nombre de points, sans annulation.';
  static const setupShuffle = 'Mélanger l\'ordre des propositions';
  static const setupInvalidNumber = 'Entrez un nombre entier';
  static String setupAvailable(int n) => n == 0
      ? 'Aucune question prête'
      : Tx.plural(n, 'question prête', 'questions prêtes');
  static String setupWillAsk(int n) =>
      'Vous aurez ${Tx.plural(n, 'question', 'questions')}.';

  // -------------------------------------------------------------- passage
  static const validate = 'Valider';
  static const skip = 'Passer';
  static const nextQuestion = 'Question suivante';
  static const seeNext = 'Suivant';
  static const finish = 'Voir les résultats';
  static const handIn = 'Rendre la copie';
  static const handInTitle = 'Rendre la copie ?';
  static const doubt = 'Marquer un doute';
  static const removeDoubt = 'Retirer le doute';
  static const zoom = 'Taille du texte';
  static const leaveTitle = 'Abandonner ce passage ?';
  static const leaveMessage =
      'La copie ne sera pas enregistrée et les réponses données seront '
      'perdues.';
  static const leaveConfirm = 'Abandonner';
  static const timeUp = 'Temps écoulé';
  static const progress = 'Questions';
  static const endOfQuestionsTitle = 'Il reste des questions passées';
  static const legendDone = 'Validée';
  static const legendSkipped = 'Passée';
  static const legendTodo = 'À faire';
  static const legendDoubt = 'Doute';
  static const lockedTooltip =
      'Cette question ne peut plus être rouverte (la suite du dossier a été '
      'vue ou le retour est désactivé).';
  static const resumeSkipped = 'Reprendre les questions passées';
  static const savedFailed = 'La copie n\'a pas pu être enregistrée.';
  static String timerLabel(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  static String dotLabel(int n, String state, bool doubt) =>
      'Question $n, $state${doubt ? ', doute' : ''}';
  static String handInUnanswered(int n) => n == 1
      ? 'Il reste 1 question sans réponse. Rendre la copie quand même ?'
      : 'Il reste $n questions sans réponse. Rendre la copie quand même ?';
  static String skippedLeft(int n) => n == 1
      ? 'Il reste 1 question passée. La reprendre, ou rendre la copie ?'
      : 'Il reste $n questions passées. Les reprendre, ou rendre la copie ?';
  static String position(int n, int total) => 'Question $n sur $total';
  static String zoomPercent(int p) => '$p %';
  static String treated(int n, int total) => 'Traitées $n / $total';

  // ----------------------------------------------------------------- copie
  static const copyAll = 'Toutes';
  static const copyReview = 'À reprendre';
  static const copyRight = 'Justes';
  static const copyPartial = 'Partielles';
  static const copyWrong = 'Fausses';
  static const copySkipped = 'Passées';
  static const copyPending = 'À évaluer';
  static const copyNote = 'Note sur 20';
  static const copyDuration = 'Durée';
  static const copyTimedOut =
      'Temps écoulé : la copie a été rendue telle quelle.';
  static const copyRedoMissed = 'Refaire mes ratées';
  static const copyReplay = 'Repasser l\'épreuve';
  static const copyReplayPractice = 'Repasser ces questions';
  static const copyAnother = 'Une autre épreuve';
  static const copyDelete = 'Supprimer la copie';
  static const copyDeleteTitle = 'Supprimer cette copie ?';
  static const copyDeleteMessage =
      'La copie et ses résultats seront effacés de l\'historique. L\'épreuve '
      'elle-même n\'est pas touchée.';
  static const copyNothingToRedo =
      'Rien à refaire : toutes les réponses sont justes.';
  static const copyNothingToReview =
      'Rien à reprendre : toutes les réponses sont justes.';
  static const copyNoAnother =
      'Aucune autre épreuve prête à être passée pour le moment.';
  static const copyPractice = 'Entraînement';
  static const copyExam = 'Épreuve';
  static const copyOpenQuestion = 'Voir la question';
  static const copyCaseContext = 'Contexte du cas';
  static const copyUnavailable = 'Cette copie n\'existe plus.';
  static String copyPendingNote(int n) => n == 1
      ? '1 question attend votre auto-évaluation : la note est provisoire.'
      : '$n questions attendent votre auto-évaluation : la note est '
            'provisoire.';
  static String copyPartOf(double part) =>
      'Entraînement · ${(part * 100).round()} % de l\'épreuve';
  static String copyQuestionLine(int n, Verdict v, double score, double max) =>
      'Question $n : ${verdictName(v)}, ${scoreOf(score, max)}';
  static String scoreOf(double score, double max) =>
      '${formatNumber(score)} / ${formatNumber(max)}';
  static String pointsOutOf(double score, double max) =>
      '${formatPoints(score)} / ${formatPoints(max)} points';
  static String redoCount(int n) => n == 1 ? '1 question' : '$n questions';

  static String durationLabel(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
    if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} s';
    return '$s s';
  }

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// « 12 mars 2026 à 15:20 ».
  static String dateTime(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '${at.day} ${_months[at.month - 1]} ${at.year} à $h:$m';
  }

  // ------------------------------------------------------------ correction
  static const yourAnswer = 'Votre réponse';
  static const modelAnswer = 'Réponse modèle';
  static const expectedFound = 'Éléments trouvés';
  static const missedAnswer = 'Oubliée';
  static const indispensable = 'Indispensable';
  static const unacceptable = 'Inacceptable';
  static const explanationTitle = 'Explication';
  static const selfEvaluate =
      'Comparez avec la réponse modèle puis évaluez-vous';
  static const selfRight = 'Juste';
  static const selfPartial = 'Partielle';
  static const selfWrong = 'Fausse';
  static const qrocHint = 'Écrivez votre réponse';
  static const panelTitle = 'Réponses du panel';
  static String verdictName(Verdict v) => switch (v) {
    Verdict.right => 'Juste',
    Verdict.partial => 'Partielle',
    Verdict.wrong => 'Fausse',
    Verdict.skipped => 'Passée',
    Verdict.pending => 'À évaluer',
  };

  /// 1,5 ou 12 ou 0,33 : deux décimales au plus, virgule française.
  static String formatNumber(double v) {
    final rounded = (v * 100).round() / 100;
    var s = rounded.toStringAsFixed(2);
    if (s.endsWith('00')) {
      s = s.substring(0, s.length - 3);
    } else if (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s.replaceAll('.', ',');
  }

  /// Toujours deux décimales (« 2,00 »), pour les notes en points.
  static String formatPoints(double v) =>
      ((v * 100).round() / 100).toStringAsFixed(2).replaceAll('.', ',');
}

/// Raccourci : 1,5 → « 1,5 ».
String formatNumber(double v) => TxQcm.formatNumber(v);
