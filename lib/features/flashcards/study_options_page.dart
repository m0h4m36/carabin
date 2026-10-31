import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/flashcards_repository.dart';
import '../../domain/scheduling.dart';
import '../../domain/study_options.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';

/// Réglages d'étude : généraux (`deckId` null) ou propres à un deck.
class StudyOptionsPage extends StatelessWidget {
  const StudyOptionsPage({super.key, this.deckId});
  final int? deckId;

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final repo = context.read<FlashcardsRepository>();
    final id = deckId;
    final deckName = id == null ? null : repo.deck(id).name;
    final own = id == null ? null : repo.deckOptions(id);
    final general = repo.globalOptions();
    final editable = id == null || own != null;
    final shown = id == null ? general : (own ?? general);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          deckName == null
              ? TxCards.generalSettings
              : TxCards.deckSettings(deckName),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (id != null) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(TxCards.ownSettings),
                  subtitle: own == null
                      ? const Text(TxCards.followsGeneral)
                      : const Text(TxCards.strictestWins),
                  value: own != null,
                  onChanged: (on) =>
                      repo.setDeckOptions(id, on ? general : null),
                ),
                const Divider(),
              ],
              OptionsForm(
                // la clé force la reconstruction quand on passe d'un jeu de réglages à l'autre
                key: ValueKey('${id ?? 'general'}-${own != null}'),
                options: shown,
                enabled: editable,
                scheduling: repo.scheduling,
                onChanged: (o) {
                  if (id == null) {
                    repo.setGlobalOptions(o);
                  } else {
                    repo.setDeckOptions(id, o);
                  }
                },
              ),
              if (editable) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        title: TxCards.resetDefaults,
                        message: TxCards.resetDefaults,
                        confirmLabel: Tx.validate,
                      );
                      if (!ok) return;
                      const d = StudyOptions();
                      if (id == null) {
                        repo.setGlobalOptions(d);
                      } else {
                        repo.setDeckOptions(id, d);
                      }
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text(TxCards.resetDefaults),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Formulaire des réglages d'étude ; chaque modification est signalée aussitôt.
class OptionsForm extends StatefulWidget {
  const OptionsForm({
    super.key,
    required this.options,
    required this.onChanged,
    required this.scheduling,
    this.enabled = true,
  });

  final StudyOptions options;
  final ValueChanged<StudyOptions> onChanged;
  final SchedulingService scheduling;
  final bool enabled;

  @override
  State<OptionsForm> createState() => _OptionsFormState();
}

class _OptionsFormState extends State<OptionsForm> {
  late StudyOptions _o = widget.options;
  late final _new = TextEditingController(
    text: '${widget.options.newPerDay ?? ''}',
  );
  late final _reviews = TextEditingController(
    text: '${widget.options.reviewsPerDay ?? ''}',
  );
  late final _leech = TextEditingController(
    text: '${widget.options.leechThreshold}',
  );

  @override
  void dispose() {
    _new.dispose();
    _reviews.dispose();
    _leech.dispose();
    super.dispose();
  }

  void _set(StudyOptions o) {
    setState(() => _o = o);
    widget.onChanged(o);
  }

  Widget _cap({
    required String label,
    required int? value,
    required TextEditingController controller,
    required ValueChanged<int?> onChanged,
  }) {
    final unlimited = value == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              enabled: widget.enabled && !unlimited,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (t) {
                final n = int.tryParse(t.trim());
                if (n != null && n >= 0) onChanged(n);
              },
            ),
          ),
          const SizedBox(width: 8),
          Checkbox(
            value: unlimited,
            onChanged: widget.enabled
                ? (v) {
                    if (v == true) {
                      onChanged(null);
                    } else {
                      final d = label == TxCards.newPerDay ? 20 : 200;
                      controller.text = '$d';
                      onChanged(d);
                    }
                  }
                : null,
          ),
          const Text(TxCards.noLimit),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.enabled;
    final milestones = widget.scheduling.milestones(_o.retention);
    final reviewDays = widget.scheduling.reviewDaysWithin(_o.retention);
    final load = _o.newPerDay == null ? null : _o.newPerDay! * reviewDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(TxCards.onePerNote),
          subtitle: const Text(TxCards.onePerNoteDetail),
          value: _o.onePerNotePerDay,
          onChanged: enabled
              ? (v) => _set(_o.copyWith(onePerNotePerDay: v))
              : null,
        ),
        const SizedBox(height: 8),
        Text(TxCards.studyOrder, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<StudyOrder>(
          segments: const [
            ButtonSegment(
              value: StudyOrder.shuffled,
              label: Text(TxCards.orderShuffled),
            ),
            ButtonSegment(
              value: StudyOrder.course,
              label: Text(TxCards.orderCourse),
            ),
          ],
          selected: {_o.order},
          onSelectionChanged: enabled
              ? (s) => _set(_o.copyWith(order: s.first))
              : null,
        ),
        const SizedBox(height: 16),
        _cap(
          label: TxCards.newPerDay,
          value: _o.newPerDay,
          controller: _new,
          onChanged: (v) => _set(_o.copyWith(newPerDay: v)),
        ),
        _cap(
          label: TxCards.reviewsPerDay,
          value: _o.reviewsPerDay,
          controller: _reviews,
          onChanged: (v) => _set(_o.copyWith(reviewsPerDay: v)),
        ),
        if (load != null) ...[
          const SizedBox(height: 4),
          Text(
            TxCards.loadEstimate(load, _o.reviewsPerDay),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _o.reviewsPerDay != null && load > _o.reviewsPerDay!
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(TxCards.retention, style: theme.textTheme.titleSmall),
            ),
            Text(
              TxCards.retentionValue(_o.retention),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
        Slider(
          value: _o.retention,
          min: StudyOptions.minRetention,
          max: StudyOptions.maxRetention,
          divisions: 27,
          label: TxCards.retentionValue(_o.retention),
          onChanged: enabled
              ? (v) => _set(
                  _o.copyWith(retention: double.parse(v.toStringAsFixed(2))),
                )
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              TxCards.retentionLow,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            Text(
              TxCards.retentionHigh,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          TxCards.milestones(milestones),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(TxCards.leechTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text(TxCards.leechThreshold)),
            SizedBox(
              width: 70,
              child: TextField(
                controller: _leech,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (t) {
                  final n = int.tryParse(t.trim());
                  if (n != null && n > 0) _set(_o.copyWith(leechThreshold: n));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<LeechAction>(
          segments: const [
            ButtonSegment(
              value: LeechAction.suspend,
              label: Text(TxCards.leechSuspend),
            ),
            ButtonSegment(
              value: LeechAction.none,
              label: Text(TxCards.leechNone),
            ),
          ],
          selected: {_o.leechAction},
          onSelectionChanged: enabled
              ? (s) => _set(_o.copyWith(leechAction: s.first))
              : null,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(TxCards.showPassCounter),
          value: _o.showPassCounter,
          onChanged: enabled
              ? (v) => _set(_o.copyWith(showPassCounter: v))
              : null,
        ),
      ],
    );
  }
}
