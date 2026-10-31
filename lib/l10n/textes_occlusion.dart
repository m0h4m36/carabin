import '../domain/note_types.dart';
import 'textes.dart';

/// Textes de l'occlusion d'image et des images dans les cartes.
abstract final class TxOcclusion {
  static const insertImage = 'Insérer une image';
  static const imageUnreadable = 'Cette image n\'a pas pu être lue.';
  static const imageMissing = 'Image introuvable';
  static const closeViewer = 'Fermer';

  static const chooseImage = 'Choisir une image';
  static const changeImage = 'Changer d\'image';
  static const chooseImageHelp =
      'Choisissez un schéma, une coupe ou une photo, puis tracez des '
      'rectangles sur les légendes à cacher.';
  static const toolDraw = 'Tracer';
  static const toolMove = 'Déplacer';
  static const toolDrawHelp =
      'Tracez un rectangle sur la zone à cacher. Touchez un rectangle pour le '
      'sélectionner.';
  static const toolMoveHelp =
      'Faites défiler et zoomez sur l\'image sans rien tracer.';
  static const zoomIn = 'Agrandir l\'image';
  static const zoomOut = 'Réduire l\'image';
  static const undoMask = 'Annuler le dernier masque';
  static const deleteMask = 'Supprimer le masque sélectionné';
  static const clearMasks = 'Tout effacer';

  static const modeHideAll = 'Tout caché';
  static const modeHideOne = 'Un seul caché';
  static const modeGroup = 'Groupement';

  static String modeName(OcclusionMode m) => switch (m) {
    OcclusionMode.hideAll => modeHideAll,
    OcclusionMode.hideOne => modeHideOne,
    OcclusionMode.group => modeGroup,
  };

  static String modeHelp(OcclusionMode m) => switch (m) {
    OcclusionMode.hideAll =>
      'Une seule carte : toutes les zones sont cachées en même temps.',
    OcclusionMode.hideOne =>
      'Une carte par zone : la zone interrogée est cachée, les autres '
          'restent visibles.',
    OcclusionMode.group =>
      'Une carte par groupe : les zones d\'un même groupe sont cachées '
          'ensemble, les autres restent visibles.',
  };

  static String group(int n) => 'Groupe $n';
  static String assignToGroup(int n) =>
      'Ranger la zone choisie dans le groupe $n';
  static const groupPrev = 'Groupe précédent';
  static const groupNext = 'Groupe suivant';

  static String counters(int zones, int groups, int cards) =>
      '${Tx.plural(zones, 'zone', 'zones')} · '
      '${Tx.plural(groups, 'groupe', 'groupes')} · '
      '${Tx.plural(cards, 'carte à fabriquer', 'cartes à fabriquer')}';

  static String addCards(int n) =>
      n <= 0 ? 'Ajouter' : 'Ajouter ${Tx.plural(n, 'carte', 'cartes')}';
  static const hintShortcuts =
      'Ctrl+Z annule le dernier masque · G / Maj+G changent de groupe';
  static const occlusionNoPreview =
      'Ajoutez une image et des zones pour voir l\'aperçu.';
}
