import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/qcm/grading.dart';
import '../../domain/qcm/question.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/status_colors.dart';
import '../flashcards/card_image.dart';
import '../flashcards/card_text.dart';
import '../flashcards/masked_image.dart';

/// Texte d'une question avec la mise en forme de Carabin (gras, italique…).
class QcmText extends StatelessWidget {
  const QcmText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyLarge ?? const TextStyle();
    return Text.rich(
      TextSpan(children: richSpans(text, base, theme.colorScheme)),
    );
  }
}

/// Lettre d'une proposition : A, B, C… (puis AA, AB… au-delà de 26).
String propositionLetter(int index) {
  const a = 0x41;
  if (index < 26) return String.fromCharCode(a + index);
  return '${String.fromCharCode(a + index ~/ 26 - 1)}'
      '${String.fromCharCode(a + index % 26)}';
}

/// Une question telle qu'on la pose : énoncé, images, zone de réponse. Avec
/// [reveal], elle montre la correction (bonnes réponses, éléments trouvés,
/// panel d'experts, explication).
///
/// Pour un QCM, la question doit être « propre » (sans proposition vide) :
/// les positions de [answer] sont celles de `question.propositions`, et
/// [order] dit dans quel ordre on les montre.
class QuestionView extends StatelessWidget {
  const QuestionView({
    super.key,
    required this.question,
    this.order = const [],
    this.answer,
    this.onChanged,
    this.reveal = false,
    this.scoring = Scoring.edn,
    this.onSelfEvaluate,
    this.trailing,
    this.heading,
  });

  final Question question;
  final List<int> order;
  final Answer? answer;

  /// Appelé à chaque changement de réponse ; nul = lecture seule.
  final ValueChanged<Answer?>? onChanged;
  final bool reveal;
  final Scoring scoring;

  /// Auto-évaluation d'un QROC sans éléments attendus (0, 0,5 ou 1).
  final ValueChanged<double>? onSelfEvaluate;

  /// Bouton à droite de l'en-tête (doute).
  final Widget? trailing;

  /// Texte au-dessus du badge (« Question 3 »…).
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = question;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          question: q,
          scoring: scoring,
          trailing: trailing,
          heading: heading,
        ),
        const SizedBox(height: 12),
        QcmText(q.body),
        if (q.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final name in q.images) CardImage(name)],
          ),
        ],
        const SizedBox(height: 16),
        switch (q) {
          ChoiceQuestion c => _ChoiceView(
            question: c,
            order: order,
            ticked: answer is ChoiceAnswer
                ? (answer! as ChoiceAnswer).ticked
                : const {},
            onChanged: onChanged == null
                ? null
                : (s) => onChanged!(s.isEmpty ? null : ChoiceAnswer(s)),
            reveal: reveal,
          ),
          QrocQuestion c => _QrocView(
            question: c,
            answer: answer is TextAnswer ? answer! as TextAnswer : null,
            onChanged: onChanged,
            reveal: reveal,
            onSelfEvaluate: onSelfEvaluate,
          ),
          TcsQuestion c => _TcsView(
            question: c,
            level: answer is TcsAnswer ? (answer! as TcsAnswer).level : null,
            onChanged: onChanged == null
                ? null
                : (l) => onChanged!(TcsAnswer(l)),
            reveal: reveal,
          ),
          QzpQuestion c => _QzpView(
            question: c,
            point: answer is PointAnswer ? answer! as PointAnswer : null,
            onChanged: onChanged == null ? null : (p) => onChanged!(p),
            reveal: reveal,
          ),
        },
        if (reveal && q.explanation.trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          _Explanation(q.explanation),
        ],
        SizedBox(height: theme.visualDensity.vertical < 0 ? 8 : 12),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.question,
    required this.scoring,
    this.trailing,
    this.heading,
  });

  final Question question;
  final Scoring scoring;
  final Widget? trailing;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (heading != null)
                Text(heading!, style: theme.textTheme.titleMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  TxQcm.kindBadge(question),
                  key: const ValueKey('kind-badge'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${TxQcm.kindHint(question)} · '
                '${TxQcm.scoringHint(question, scoring)} · '
                '${TxQcm.pointsLabel(question.points)}',
                style: muted,
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TxQcm.explanationTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          QcmText(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ QCM

class _ChoiceView extends StatelessWidget {
  const _ChoiceView({
    required this.question,
    required this.order,
    required this.ticked,
    required this.onChanged,
    required this.reveal,
  });

  final ChoiceQuestion question;
  final List<int> order;
  final Set<int> ticked;
  final ValueChanged<Set<int>>? onChanged;
  final bool reveal;

  List<int> get _order {
    final n = question.propositions.length;
    final ok =
        order.length == n &&
        order.toSet().length == n &&
        order.every((i) => i >= 0 && i < n);
    return ok ? order : List<int>.generate(n, (i) => i);
  }

  void _tap(int index) {
    final cb = onChanged;
    if (cb == null || reveal) return;
    switch (question.shape) {
      case ChoiceShape.qru:
        cb(ticked.contains(index) ? <int>{} : {index});
      case ChoiceShape.qrm:
        cb(
          ticked.contains(index)
              ? ({...ticked}..remove(index))
              : {...ticked, index},
        );
      case ChoiceShape.qrp:
        if (ticked.contains(index)) {
          cb({...ticked}..remove(index));
        } else if (ticked.length < question.correctCount) {
          cb({...ticked, index});
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _order;
    final full =
        question.shape == ChoiceShape.qrp &&
        ticked.length >= question.correctCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var pos = 0; pos < idx.length; pos++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PropositionTile(
              letter: propositionLetter(pos),
              proposition: question.propositions[idx[pos]],
              ticked: ticked.contains(idx[pos]),
              single: question.shape == ChoiceShape.qru,
              reveal: reveal,
              enabled:
                  onChanged != null &&
                  !reveal &&
                  !(full && !ticked.contains(idx[pos])),
              onTap: () => _tap(idx[pos]),
            ),
          ),
      ],
    );
  }
}

class _PropositionTile extends StatelessWidget {
  const _PropositionTile({
    required this.letter,
    required this.proposition,
    required this.ticked,
    required this.single,
    required this.reveal,
    required this.enabled,
    required this.onTap,
  });

  final String letter;
  final Proposition proposition;
  final bool ticked;
  final bool single;
  final bool reveal;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);

    Color border = scheme.outlineVariant;
    Color? fill;
    Color letterBg = scheme.surfaceContainerHighest;
    Color letterFg = scheme.onSurfaceVariant;
    IconData? icon;
    Color? iconColor;
    String? tag;
    final p = proposition;

    if (reveal) {
      if (p.correct && ticked) {
        border = status.right;
        fill = status.right.withValues(alpha: 0.10);
        icon = Icons.check_circle;
        iconColor = status.right;
      } else if (!p.correct && ticked) {
        border = status.wrong;
        fill = status.wrong.withValues(alpha: 0.10);
        icon = Icons.cancel;
        iconColor = status.wrong;
      } else if (p.correct) {
        border = status.partial;
        icon = Icons.radio_button_unchecked;
        iconColor = status.partial;
        tag = TxQcm.missedAnswer;
      }
    } else if (ticked) {
      border = scheme.primary;
      fill = scheme.primaryContainer.withValues(alpha: 0.35);
      letterBg = scheme.primary;
      letterFg = scheme.onPrimary;
    }

    final critical = reveal && p.critical
        ? (p.correct ? TxQcm.indispensable : TxQcm.unacceptable)
        : null;

    return Semantics(
      button: true,
      enabled: enabled,
      checked: ticked,
      inMutuallyExclusiveGroup: single,
      label: '$letter. ${p.text}',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || reveal || ticked ? 1 : 0.5,
        child: Material(
          color: fill ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: border, width: ticked || reveal ? 1.6 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: letterBg,
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: letterFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          QcmText(p.text, style: theme.textTheme.bodyMedium),
                          if (tag != null || critical != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                [?tag, ?critical].join(' · '),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: iconColor ?? scheme.outline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: iconColor, size: 22),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- QROC

class _MaxLinesFormatter extends TextInputFormatter {
  const _MaxLinesFormatter(this.maxLines);
  final int maxLines;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lines = '\n'.allMatches(newValue.text).length + 1;
    return lines > maxLines ? oldValue : newValue;
  }
}

class _QrocView extends StatefulWidget {
  const _QrocView({
    required this.question,
    required this.answer,
    required this.onChanged,
    required this.reveal,
    required this.onSelfEvaluate,
  });

  final QrocQuestion question;
  final TextAnswer? answer;
  final ValueChanged<Answer?>? onChanged;
  final bool reveal;
  final ValueChanged<double>? onSelfEvaluate;

  @override
  State<_QrocView> createState() => _QrocViewState();
}

class _QrocViewState extends State<_QrocView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.answer?.text ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final status = StatusColors.of(context);
    final nature = q.nature.trim().isEmpty ? TxQcm.qrocNatureHint : q.nature;
    if (!widget.reveal) {
      final lines = q.maxLines;
      return TextField(
        key: const ValueKey('qroc-field'),
        controller: _controller,
        enabled: widget.onChanged != null,
        minLines: lines != null && lines < 3 ? lines : 3,
        maxLines: lines ?? 8,
        keyboardType: TextInputType.multiline,
        inputFormatters: [if (lines != null) _MaxLinesFormatter(lines)],
        decoration: InputDecoration(
          labelText: nature,
          hintText: TxQcm.qrocHint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (t) =>
            widget.onChanged?.call(t.trim().isEmpty ? null : TextAnswer(t)),
      );
    }

    final given = widget.answer;
    final hits = given == null ? const <bool>[] : qrocHits(q, given.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledBox(
          label: TxQcm.yourAnswer,
          child: Text(
            given == null || given.text.trim().isEmpty ? '—' : given.text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (q.autoGraded) ...[
          const SizedBox(height: 12),
          Text(TxQcm.expectedFound, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (var i = 0; i < q.usableElements.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    i < hits.length && hits[i]
                        ? Icons.check_circle
                        : Icons.cancel_outlined,
                    size: 20,
                    color: i < hits.length && hits[i]
                        ? status.right
                        : status.wrong,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_displayPattern(q.usableElements[i]))),
                  Text(
                    TxQcm.pointsLabel(q.usableElements[i].points),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
        if (q.model.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _LabeledBox(
            label: TxQcm.modelAnswer,
            child: QcmText(q.model, style: theme.textTheme.bodyMedium),
          ),
        ],
        if (!q.autoGraded && given != null) ...[
          const SizedBox(height: 12),
          Text(TxQcm.selfEvaluate, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value, color) in [
                (TxQcm.selfRight, 1.0, status.right),
                (TxQcm.selfPartial, 0.5, status.partial),
                (TxQcm.selfWrong, 0.0, status.wrong),
              ])
                ChoiceChip(
                  key: ValueKey('self-$value'),
                  label: Text(label),
                  selected: given.self == value,
                  selectedColor: color.withValues(alpha: 0.25),
                  onSelected: widget.onSelfEvaluate == null
                      ? null
                      : (_) => widget.onSelfEvaluate!(value),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _displayPattern(ExpectedElement e) => e.pattern
      .replaceAll(RegExp(r'\s*;\s*'), ' ; ')
      .replaceAll(RegExp(r'\s*\|\s*'), ' | ')
      .trim();
}

class _LabeledBox extends StatelessWidget {
  const _LabeledBox({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ TCS

class _TcsView extends StatelessWidget {
  const _TcsView({
    required this.question,
    required this.level,
    required this.onChanged,
    required this.reveal,
  });

  final TcsQuestion question;
  final int? level;
  final ValueChanged<int>? onChanged;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final q = question;
    final top = q.panelMax;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledBox(
          label: TxQcm.tcsHypothesis,
          child: QcmText(q.hypothesis, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 8),
        _LabeledBox(
          label: TxQcm.tcsNewInfo,
          child: QcmText(q.newInfo, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 16),
        Text(TxQcm.tcsTherefore, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tcsLevels; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == tcsLevels - 1 ? 0 : 6),
                  child: Column(
                    children: [
                      _LevelButton(
                        label: TxQcm.tcsLevel(i - 2),
                        selected: level == i - 2,
                        best: reveal && top > 0 && q.panel[i] == top,
                        enabled: onChanged != null && !reveal,
                        onTap: () => onChanged?.call(i - 2),
                        status: status,
                        reveal: reveal,
                      ),
                      if (reveal) ...[
                        const SizedBox(height: 6),
                        _PanelBar(
                          count: q.panel[i],
                          max: top,
                          color: q.panel[i] == top && top > 0
                              ? status.right
                              : scheme.outline,
                        ),
                        Text(
                          '${q.panel[i]}',
                          style: theme.textTheme.labelMedium,
                          semanticsLabel:
                              '${TxQcm.tcsLevel(i - 2)} : ${TxQcm.tcsExperts(q.panel[i])}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                q.lowLabel.trim().isEmpty ? TxQcm.tcsLowDefault : q.lowLabel,
                style: muted,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                q.highLabel.trim().isEmpty ? TxQcm.tcsHighDefault : q.highLabel,
                style: muted,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (reveal) ...[
          const SizedBox(height: 8),
          Text(TxQcm.panelTitle, style: muted),
        ],
      ],
    );
  }
}

class _LevelButton extends StatelessWidget {
  const _LevelButton({
    required this.label,
    required this.selected,
    required this.best,
    required this.enabled,
    required this.onTap,
    required this.status,
    required this.reveal,
  });

  final String label;
  final bool selected;
  final bool best;
  final bool enabled;
  final VoidCallback onTap;
  final StatusColors status;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var border = scheme.outlineVariant;
    Color? fill;
    var fg = scheme.onSurface;
    if (reveal) {
      if (selected) {
        border = best ? status.right : status.wrong;
        fill = border.withValues(alpha: 0.12);
      } else if (best) {
        border = status.right;
      }
    } else if (selected) {
      border = scheme.primary;
      fill = scheme.primary;
      fg = scheme.onPrimary;
    }
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fill ?? Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: selected || best ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelBar extends StatelessWidget {
  const _PanelBar({
    required this.count,
    required this.max,
    required this.color,
  });
  final int count;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : count / max;
    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: ratio.clamp(0.04, 1.0),
          widthFactor: 0.5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ QZP

class _QzpView extends StatelessWidget {
  const _QzpView({
    required this.question,
    required this.point,
    required this.onChanged,
    required this.reveal,
  });

  final QzpQuestion question;
  final PointAnswer? point;
  final ValueChanged<PointAnswer>? onChanged;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final q = question;
    if (q.image.isEmpty) return const SizedBox.shrink();
    final hit =
        point != null && q.zones.any((z) => z.contains(point!.x, point!.y));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: MaskedImage(
            name: q.image,
            maxHeight: 420,
            overlay: (context, size) => GestureDetector(
              key: const ValueKey('qzp-surface'),
              behavior: HitTestBehavior.opaque,
              onTapDown: onChanged == null || reveal
                  ? null
                  : (d) => onChanged!(
                      PointAnswer(
                        (d.localPosition.dx / size.width).clamp(0.0, 1.0),
                        (d.localPosition.dy / size.height).clamp(0.0, 1.0),
                      ),
                    ),
              child: CustomPaint(
                size: size,
                painter: _PointPainter(
                  zones: reveal ? q.zones : const [],
                  zoneColor: status.right,
                  point: point,
                  pointColor: reveal
                      ? (hit ? status.right : status.wrong)
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          reveal ? (point == null ? '' : TxQcm.qzpYourPoint) : TxQcm.qzpTapHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PointPainter extends CustomPainter {
  _PointPainter({
    required this.zones,
    required this.zoneColor,
    required this.point,
    required this.pointColor,
  });

  final List<Zone> zones;
  final Color zoneColor;
  final PointAnswer? point;
  final Color pointColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final z in zones) {
      final r = Rect.fromLTWH(
        z.left * size.width,
        z.top * size.height,
        z.width * size.width,
        z.height * size.height,
      );
      canvas.drawRect(r, Paint()..color = zoneColor.withValues(alpha: 0.18));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = zoneColor,
      );
    }
    final p = point;
    if (p != null) {
      final c = Offset(p.x * size.width, p.y * size.height);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = pointColor;
      canvas.drawCircle(
        c,
        11,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
      canvas.drawCircle(c, 11, ring);
      canvas.drawLine(c - const Offset(16, 0), c + const Offset(16, 0), ring);
      canvas.drawLine(c - const Offset(0, 16), c + const Offset(0, 16), ring);
    }
  }

  @override
  bool shouldRepaint(_PointPainter old) =>
      old.point?.x != point?.x ||
      old.point?.y != point?.y ||
      old.zones != zones ||
      old.pointColor != pointColor;
}
