import 'dart:convert';

/// Ordre de passage des cartes.
enum StudyOrder { shuffled, course }

/// Que faire d'une carte « maudite » (trop souvent oubliée).
enum LeechAction { suspend, none }

/// Réglages d'étude (généraux ou propres à un paquet).
class StudyOptions {
  const StudyOptions({
    this.onePerNotePerDay = true,
    this.order = StudyOrder.shuffled,
    this.newPerDay = 20,
    this.reviewsPerDay = 200,
    this.retention = 0.9,
    this.leechThreshold = 8,
    this.leechAction = LeechAction.suspend,
    this.showPassCounter = true,
  });

  /// Une seule carte par notion et par jour.
  final bool onePerNotePerDay;
  final StudyOrder order;

  /// Plafond de nouvelles cartes par jour ; null = sans plafond.
  final int? newPerDay;

  /// Plafond de révisions par jour ; null = sans plafond.
  final int? reviewsPerDay;

  /// Exigence de mémorisation (0,70 à 0,97).
  final double retention;
  final int leechThreshold;
  final LeechAction leechAction;
  final bool showPassCounter;

  static const minRetention = 0.70;
  static const maxRetention = 0.97;

  StudyOptions copyWith({
    bool? onePerNotePerDay,
    StudyOrder? order,
    Object? newPerDay = _keep,
    Object? reviewsPerDay = _keep,
    double? retention,
    int? leechThreshold,
    LeechAction? leechAction,
    bool? showPassCounter,
  }) => StudyOptions(
    onePerNotePerDay: onePerNotePerDay ?? this.onePerNotePerDay,
    order: order ?? this.order,
    newPerDay: identical(newPerDay, _keep) ? this.newPerDay : newPerDay as int?,
    reviewsPerDay: identical(reviewsPerDay, _keep)
        ? this.reviewsPerDay
        : reviewsPerDay as int?,
    retention: retention ?? this.retention,
    leechThreshold: leechThreshold ?? this.leechThreshold,
    leechAction: leechAction ?? this.leechAction,
    showPassCounter: showPassCounter ?? this.showPassCounter,
  );

  static const _keep = Object();

  Map<String, dynamic> toMap() => {
    'onePerNotePerDay': onePerNotePerDay,
    'order': order.name,
    'newPerDay': newPerDay,
    'reviewsPerDay': reviewsPerDay,
    'retention': retention,
    'leechThreshold': leechThreshold,
    'leechAction': leechAction.name,
    'showPassCounter': showPassCounter,
  };

  String toJson() => jsonEncode(toMap());

  /// Relit des réglages ; toute valeur absente ou invalide reprend sa valeur
  /// par défaut (jamais d'exception sur des données abîmées).
  factory StudyOptions.fromJson(String? json) {
    const d = StudyOptions();
    if (json == null || json.isEmpty) return d;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(json) as Map).cast<String, dynamic>();
    } on Object {
      return d;
    }
    int? intOrNull(String k, int? fallback) {
      if (!m.containsKey(k)) return fallback;
      final v = m[k];
      if (v == null) return null;
      return v is num && v >= 0 ? v.toInt() : fallback;
    }

    final r = m['retention'];
    return StudyOptions(
      onePerNotePerDay: m['onePerNotePerDay'] is bool
          ? m['onePerNotePerDay'] as bool
          : d.onePerNotePerDay,
      order: StudyOrder.values.firstWhere(
        (o) => o.name == m['order'],
        orElse: () => d.order,
      ),
      newPerDay: intOrNull('newPerDay', d.newPerDay),
      reviewsPerDay: intOrNull('reviewsPerDay', d.reviewsPerDay),
      retention: r is num
          ? r.toDouble().clamp(minRetention, maxRetention)
          : d.retention,
      leechThreshold:
          m['leechThreshold'] is int && (m['leechThreshold'] as int) > 0
          ? m['leechThreshold'] as int
          : d.leechThreshold,
      leechAction: LeechAction.values.firstWhere(
        (a) => a.name == m['leechAction'],
        orElse: () => d.leechAction,
      ),
      showPassCounter: m['showPassCounter'] is bool
          ? m['showPassCounter'] as bool
          : d.showPassCounter,
    );
  }
}
