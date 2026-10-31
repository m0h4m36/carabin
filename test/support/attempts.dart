import 'package:carabin/data/qcm_models.dart';
import 'package:carabin/domain/qcm/exam.dart';

/// Brouillons de copies pour les tests.
class AttemptDraftForTest {
  static AttemptDraft simple({required int examId, String title = 'Copie'}) =>
      AttemptDraft(
        title: title,
        examId: examId,
        settings: const PassageSettings(),
        startedAt: DateTime.utc(2026, 1, 1),
        duration: Duration.zero,
        answers: const [],
      );
}
