import 'dart:async';
import 'dart:isolate';

/// Lance un travail long hors du fil de l'interface. Les tests remplacent
/// [run] par une exécution directe.
abstract final class Background {
  static Future<T> Function<T>(FutureOr<T> Function() job) run = _isolate;

  static Future<T> _isolate<T>(FutureOr<T> Function() job) => Isolate.run(job);
}
