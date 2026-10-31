import '../data/errors.dart';

/// Textes de l'import et de l'export de cartes.
abstract final class TxExchange {
  static const unsupportedFile =
      'Ce type de fichier n\'est pas pris en charge (images : PNG, JPEG, GIF, '
      'WebP ou BMP).';

  static String problem(ImportProblem p) => switch (p) {
    ImportProblem.unreadable =>
      'Ce fichier n\'a pas pu être lu : ce n\'est pas un paquet que '
          'Carabin connaît.',
    ImportProblem.corrupt =>
      'Ce fichier semble abîmé ou incomplet. Exportez-le de nouveau depuis '
          'son application d\'origine.',
    ImportProblem.empty => 'Ce paquet ne contient aucune carte.',
    ImportProblem.ankiNeedsOlderFormat =>
      'Ce paquet Anki n\'a pas pu être lu. Dans Anki, exportez-le de '
          'nouveau en cochant « Compatible avec les anciennes versions '
          'd\'Anki », puis réessayez.',
    ImportProblem.newerFormat =>
      'Ce fichier a été fabriqué par une version plus récente de Carabin. '
          'Mettez l\'application à jour pour l\'ouvrir.',
    ImportProblem.noColumns =>
      'Aucune colonne exploitable n\'a été trouvée dans ce fichier.',
  };
}
