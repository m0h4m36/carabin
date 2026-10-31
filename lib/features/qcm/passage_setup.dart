import 'package:flutter/material.dart';

import '../../domain/qcm/exam.dart';
import '../../domain/qcm/grading.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_qcm.dart';

/// Demande les réglages d'un passage. Renvoie null si l'étudiant annule.
///
/// [available] est le nombre de questions prêtes ; [initial] porte les
/// derniers réglages utilisés.
Future<PassageSettings?> showPassageSetup(
  BuildContext context, {
  required String title,
  required int available,
  required PassageSettings initial,
}) => showDialog<PassageSettings>(
  context: context,
  builder: (_) =>
      PassageSetupDialog(title: title, available: available, initial: initial),
);

class PassageSetupDialog extends StatefulWidget {
  const PassageSetupDialog({
    super.key,
    required this.title,
    required this.available,
    required this.initial,
  });

  final String title;
  final int available;
  final PassageSettings initial;

  @override
  State<PassageSetupDialog> createState() => _PassageSetupDialogState();
}

class _PassageSetupDialogState extends State<PassageSetupDialog> {
  late PassageSettings _s = widget.initial.copyWith(
    partCount: widget.initial.partCount.clamp(1, _maxPart),
  );
  late final TextEditingController _count = TextEditingController(
    text: '${_s.partCount}',
  );
  late final TextEditingController _timer = TextEditingController(
    text: '${_s.timerMinutes ?? 60}',
  );
  bool _countInvalid = false;
  bool _timerInvalid = false;

  int get _maxPart => widget.available < 1 ? 1 : widget.available;

  @override
  void dispose() {
    _count.dispose();
    _timer.dispose();
    super.dispose();
  }

  /// Nombre de questions qu'on posera avec ces réglages.
  int get _willAsk => _s.part
      ? (_s.partCount > widget.available ? widget.available : _s.partCount)
      : widget.available;

  bool get _valid =>
      widget.available > 0 &&
      !(_s.part && _countInvalid) &&
      !(_s.timerMinutes != null && _timerInvalid);

  void _countChanged(String text) {
    final v = int.tryParse(text.trim());
    final ok = v != null && v >= 1 && v <= 10000;
    setState(() {
      _countInvalid = !ok;
      if (ok) _s = _s.copyWith(partCount: v);
    });
  }

  void _timerChanged(String text) {
    final v = int.tryParse(text.trim());
    final ok = v != null && v >= 1 && v <= 24 * 60;
    setState(() {
      _timerInvalid = !ok;
      if (ok) _s = _s.copyWith(timerMinutes: v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                TxQcm.setupAvailable(widget.available),
                key: const ValueKey('setup-available'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(TxQcm.setupTitle, style: muted),
              SwitchListTile(
                key: const ValueKey('setup-part'),
                contentPadding: EdgeInsets.zero,
                title: const Text(TxQcm.setupPart),
                value: _s.part,
                onChanged: widget.available == 0
                    ? null
                    : (v) => setState(() => _s = _s.copyWith(part: v)),
              ),
              if (_s.part) ...[
                TextField(
                  key: const ValueKey('setup-count'),
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: TxQcm.setupPartCount,
                    border: const OutlineInputBorder(),
                    errorText: _countInvalid ? TxQcm.setupInvalidNumber : null,
                  ),
                  onChanged: _countChanged,
                ),
                SwitchListTile(
                  key: const ValueKey('setup-random'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(TxQcm.setupRandom),
                  value: _s.random,
                  onChanged: (v) => setState(() => _s = _s.copyWith(random: v)),
                ),
              ],
              if (widget.available > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    TxQcm.setupWillAsk(_willAsk),
                    key: const ValueKey('setup-will-ask'),
                    style: muted,
                  ),
                ),
              const Divider(),
              const SizedBox(height: 4),
              Text(TxQcm.setupCorrection, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<Correction>(
                key: const ValueKey('setup-correction'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                ),
                segments: const [
                  ButtonSegment(
                    value: Correction.end,
                    label: Text(TxQcm.correctionEnd),
                  ),
                  ButtonSegment(
                    value: Correction.each,
                    label: Text(TxQcm.correctionEach),
                  ),
                ],
                selected: {_s.correction},
                onSelectionChanged: (v) =>
                    setState(() => _s = _s.copyWith(correction: v.first)),
              ),
              SwitchListTile(
                key: const ValueKey('setup-back'),
                contentPadding: EdgeInsets.zero,
                title: const Text(TxQcm.setupBack),
                value: _s.backAllowed,
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(backAllowed: v)),
              ),
              SwitchListTile(
                key: const ValueKey('setup-shuffle'),
                contentPadding: EdgeInsets.zero,
                title: const Text(TxQcm.setupShuffle),
                value: _s.shuffleProps,
                onChanged: (v) =>
                    setState(() => _s = _s.copyWith(shuffleProps: v)),
              ),
              SwitchListTile(
                key: const ValueKey('setup-timer'),
                contentPadding: EdgeInsets.zero,
                title: const Text(TxQcm.setupTimer),
                value: _s.timerMinutes != null,
                onChanged: (v) => setState(() {
                  if (v) {
                    _timerInvalid = false;
                    _timer.text = '${int.tryParse(_timer.text) ?? 60}';
                    _s = _s.copyWith(
                      timerMinutes: int.tryParse(_timer.text) ?? 60,
                    );
                  } else {
                    _s = _s.copyWith(timerMinutes: null);
                  }
                }),
              ),
              if (_s.timerMinutes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: const ValueKey('setup-minutes'),
                    controller: _timer,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: TxQcm.setupTimerMinutes,
                      border: const OutlineInputBorder(),
                      errorText: _timerInvalid
                          ? TxQcm.setupInvalidNumber
                          : null,
                    ),
                    onChanged: _timerChanged,
                  ),
                ),
              const Divider(),
              const SizedBox(height: 4),
              Text(TxQcm.setupScoring, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<Scoring>(
                key: const ValueKey('setup-scoring'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                ),
                segments: const [
                  ButtonSegment(
                    value: Scoring.edn,
                    label: Text(TxQcm.scoringEdn),
                  ),
                  ButtonSegment(
                    value: Scoring.points,
                    label: Text(TxQcm.scoringPoints),
                  ),
                ],
                selected: {_s.scoring},
                onSelectionChanged: (v) =>
                    setState(() => _s = _s.copyWith(scoring: v.first)),
              ),
              const SizedBox(height: 4),
              Text(
                _s.scoring == Scoring.edn
                    ? TxQcm.scoringEdnHelp
                    : TxQcm.scoringPointsHelp,
                style: muted,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(Tx.cancel),
        ),
        FilledButton(
          key: const ValueKey('setup-start'),
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  _s.copyWith(
                    partCount: _s.partCount > widget.available
                        ? _maxPart
                        : _s.partCount,
                  ),
                )
              : null,
          child: const Text(TxQcm.setupStart),
        ),
      ],
    );
  }
}
