import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/media_store.dart';
import '../../domain/qcm/question.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/pickers.dart';
import '../flashcards/card_image.dart';
import 'question_view.dart';
import 'rich_field.dart';
import 'zone_editor.dart';

/// Un cas proposé dans la liste « Dans un cas clinique ».
class CaseChoice {
  const CaseChoice(this.id, this.name);
  final int id;
  final String name;
}

/// Nombre saisi (virgule ou point), ou null s'il est illisible.
double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Formulaire d'écriture d'une question. Il garde sa propre copie de la
/// question et la renvoie à chaque modification : l'écran qui l'héberge
/// l'enregistre au fur et à mesure.
///
/// À créer avec une clé propre à la question, pour repartir de zéro quand on
/// en choisit une autre.
class QuestionForm extends StatefulWidget {
  const QuestionForm({
    super.key,
    required this.question,
    required this.onChanged,
    this.cases = const [],
    this.caseId,
    this.onCaseChanged,
  });

  final Question question;
  final ValueChanged<Question> onChanged;

  /// Cas dans lesquels on peut ranger la question.
  final List<CaseChoice> cases;
  final int? caseId;
  final ValueChanged<int?>? onCaseChanged;

  @override
  State<QuestionForm> createState() => _QuestionFormState();
}

class _QuestionFormState extends State<QuestionForm> {
  late Question _q = widget.question;

  /// Clés stables des lignes (pour que chaque champ garde son texte quand on
  /// en supprime une autre).
  late List<Key> _propKeys = _freshKeys(_choice?.propositions.length ?? 0);
  late List<Key> _elementKeys = _freshKeys(_qroc?.elements.length ?? 0);

  static List<Key> _freshKeys(int n) => [
    for (var i = 0; i < n; i++) UniqueKey(),
  ];

  ChoiceQuestion? get _choice =>
      _q is ChoiceQuestion ? _q as ChoiceQuestion : null;
  TcsQuestion get _tcs => _q as TcsQuestion;

  QzpQuestion get _qzp => _q as QzpQuestion;

  QrocQuestion? get _qroc => _q is QrocQuestion ? _q as QrocQuestion : null;

  void _set(Question q) {
    setState(() => _q = q);
    widget.onChanged(q);
  }

  // ------------------------------------------------------------------ type

  /// Vrai si changer de genre ferait perdre ce que l'utilisateur a écrit.
  bool _losesContent(QuestionKind target) {
    final q = _q;
    if (target == q.kind) return false;
    final bothChoice =
        q is ChoiceQuestion &&
        (target == QuestionKind.qcm || target == QuestionKind.qrp);
    if (bothChoice) return false;
    return switch (q) {
      ChoiceQuestion c => c.written.isNotEmpty,
      QrocQuestion c =>
        c.nature.trim().isNotEmpty ||
            c.model.trim().isNotEmpty ||
            c.elements.any((e) => e.pattern.trim().isNotEmpty) ||
            c.maxLines != null,
      TcsQuestion c =>
        c.hypothesis.trim().isNotEmpty ||
            c.newInfo.trim().isNotEmpty ||
            c.lowLabel.trim().isNotEmpty ||
            c.highLabel.trim().isNotEmpty ||
            c.panelTotal > 0,
      QzpQuestion c => c.image.isNotEmpty || c.zones.isNotEmpty,
    };
  }

  Future<void> _changeKind(QuestionKind target) async {
    if (target == _q.kind) return;
    if (_losesContent(target)) {
      final ok = await confirm(
        context,
        title: TxQcm.confirmChangeKindTitle,
        message: TxQcm.confirmChangeKind,
        confirmLabel: TxQcm.changeKind,
      );
      if (!ok || !mounted) return;
    }
    final converted = _q.convertTo(target);
    setState(() {
      _propKeys = _freshKeys(
        converted is ChoiceQuestion ? converted.propositions.length : 0,
      );
      _elementKeys = _freshKeys(
        converted is QrocQuestion ? converted.elements.length : 0,
      );
    });
    _set(converted);
  }

  Widget _typeRow(BuildContext context) {
    final kind = _q.kind;
    final isChoice = _q is ChoiceQuestion;
    Widget chip(String label, bool selected, QuestionKind target, Key key) =>
        ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          onSelected: (_) => _changeKind(target),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(
              TxQcm.kindQcm,
              isChoice,
              kind == QuestionKind.qrp ? QuestionKind.qrp : QuestionKind.qcm,
              const ValueKey('kind-qcm'),
            ),
            chip(
              TxQcm.kindQroc,
              kind == QuestionKind.qroc,
              QuestionKind.qroc,
              const ValueKey('kind-qroc'),
            ),
            chip(
              TxQcm.kindTcs,
              kind == QuestionKind.tcs,
              QuestionKind.tcs,
              const ValueKey('kind-tcs'),
            ),
            chip(
              TxQcm.kindQzp,
              kind == QuestionKind.qzp,
              QuestionKind.qzp,
              const ValueKey('kind-qzp'),
            ),
          ],
        ),
        if (isChoice)
          SwitchListTile(
            key: const ValueKey('qrp-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text(TxQcm.limitedAnswers),
            value: kind == QuestionKind.qrp,
            onChanged: (v) => _set((_q as ChoiceQuestion).copyWith(pointed: v)),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------- cas

  Widget _caseRow() {
    if (widget.cases.isEmpty || widget.onCaseChanged == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      // Recréé quand le cas change (la valeur initiale n'est lue qu'une fois).
      child: KeyedSubtree(
        key: ValueKey('case-selection-${widget.caseId}'),
        child: DropdownButtonFormField<int?>(
          key: const ValueKey('case-dropdown'),
          initialValue: widget.cases.any((c) => c.id == widget.caseId)
              ? widget.caseId
              : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: TxQcm.inCase),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text(TxQcm.noCase),
            ),
            for (final c in widget.cases)
              DropdownMenuItem<int?>(
                value: c.id,
                child: Text(c.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: widget.onCaseChanged,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- images

  Future<String?> _pickImage() async {
    final media = context.read<MediaStore>();
    try {
      final path = await Pickers.image();
      if (path == null) return null;
      return media.addFile(path);
    } on Object catch (e) {
      if (mounted) showError(context, e);
      return null;
    }
  }

  Future<void> _addImage() async {
    final name = await _pickImage();
    if (name == null || !mounted) return;
    if (_q.images.contains(name)) return;
    _set(_q.withCommon(images: [..._q.images, name]));
  }

  void _removeImage(String name) =>
      _set(_q.withCommon(images: [..._q.images.where((i) => i != name)]));

  Widget _imagesBlock(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TxQcm.images, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final name in _q.images)
              Column(
                key: ValueKey('image-$name'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  CardImage(name, maxHeight: 96),
                  TextButton.icon(
                    onPressed: () => _removeImage(name),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text(TxQcm.removeImage),
                  ),
                ],
              ),
            if (_q.images.length < maxImagesPerQuestion)
              OutlinedButton.icon(
                key: const ValueKey('add-image'),
                onPressed: _addImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text(TxQcm.addImage),
              ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------- propositions

  void _editProposition(int i, Proposition Function(Proposition p) change) {
    final c = _choice!;
    if (i >= c.propositions.length) return;
    final list = [...c.propositions]..[i] = change(c.propositions[i]);
    _set(c.copyWith(propositions: list));
  }

  void _addProposition() {
    final c = _choice!;
    if (c.propositions.length >= maxPropositions) return;
    setState(() => _propKeys = [..._propKeys, UniqueKey()]);
    _set(c.copyWith(propositions: [...c.propositions, const Proposition()]));
  }

  void _removeProposition(int i) {
    final c = _choice!;
    if (c.propositions.length <= 2) return;
    setState(() => _propKeys = [..._propKeys]..removeAt(i));
    _set(c.copyWith(propositions: [...c.propositions]..removeAt(i)));
  }

  Widget _choiceBlock(BuildContext context, ChoiceQuestion c) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TxQcm.propositions, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          TxQcm.shapeNote(c.shape, c.correctCount),
          key: const ValueKey('shape-note'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < c.propositions.length; i++)
          Padding(
            key: _propKeys[i],
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  height: 48,
                  child: Center(
                    child: Text(
                      propositionLetter(i),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
                Tooltip(
                  message: TxQcm.markCorrect,
                  child: Checkbox(
                    key: ValueKey('correct-$i'),
                    value: c.propositions[i].correct,
                    onChanged: (v) => _editProposition(
                      i,
                      (p) => p.copyWith(correct: v ?? false),
                    ),
                  ),
                ),
                Expanded(
                  child: LineField(
                    key: ValueKey('proposition-field-${_propKeys[i]}'),
                    fieldKey: ValueKey('proposition-$i'),
                    initial: c.propositions[i].text,
                    hint: TxQcm.propositionHint,
                    maxLength: 4000,
                    multiline: true,
                    onChanged: (t) =>
                        _editProposition(i, (p) => p.copyWith(text: t)),
                  ),
                ),
                IconButton(
                  key: ValueKey('critical-$i'),
                  tooltip: c.propositions[i].correct
                      ? TxQcm.criticalTooltipCorrect
                      : TxQcm.criticalTooltipWrong,
                  isSelected: c.propositions[i].critical,
                  icon: const Icon(Icons.error_outline),
                  selectedIcon: Icon(
                    Icons.error,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _editProposition(
                    i,
                    (p) => p.copyWith(critical: !p.critical),
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-proposition-$i'),
                  tooltip: TxQcm.removeProposition,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: c.propositions.length <= 2
                      ? null
                      : () => _removeProposition(i),
                ),
              ],
            ),
          ),
        if (c.propositions.length < maxPropositions)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('add-proposition'),
              onPressed: _addProposition,
              icon: const Icon(Icons.add),
              label: const Text(TxQcm.addProposition),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ QROC

  static const _lineChoices = [1, 2, 3, 5, 10, 20];

  void _editElement(int i, ExpectedElement Function(ExpectedElement e) change) {
    final c = _qroc!;
    if (i >= c.elements.length) return;
    _set(c.copyWith(elements: [...c.elements]..[i] = change(c.elements[i])));
  }

  void _addElement() {
    final c = _qroc!;
    if (c.elements.length >= maxElements) return;
    setState(() => _elementKeys = [..._elementKeys, UniqueKey()]);
    _set(c.copyWith(elements: [...c.elements, const ExpectedElement()]));
  }

  void _removeElement(int i) {
    final c = _qroc!;
    setState(() => _elementKeys = [..._elementKeys]..removeAt(i));
    _set(c.copyWith(elements: [...c.elements]..removeAt(i)));
  }

  Widget _qrocBlock(BuildContext context, QrocQuestion c) {
    final theme = Theme.of(context);
    final lines = {..._lineChoices, ?c.maxLines}.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LineField(
          key: const ValueKey('qroc-nature-field'),
          fieldKey: const ValueKey('qroc-nature'),
          initial: c.nature,
          label: TxQcm.qrocNature,
          hint: TxQcm.qrocNatureHint,
          maxLength: 200,
          onChanged: (t) => _set(_qroc!.copyWith(nature: t)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          key: const ValueKey('qroc-lines'),
          initialValue: c.maxLines,
          decoration: const InputDecoration(labelText: TxQcm.qrocMaxLines),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text(TxQcm.qrocNoLimit),
            ),
            for (final n in lines)
              DropdownMenuItem<int?>(value: n, child: Text(TxQcm.qrocLines(n))),
          ],
          onChanged: (v) => _set(_qroc!.copyWith(maxLines: v)),
        ),
        const SizedBox(height: 16),
        QcmRichField(
          key: const ValueKey('qroc-model-field'),
          fieldKey: const ValueKey('qroc-model'),
          label: TxQcm.qrocModel,
          initial: c.model,
          minLines: 2,
          onChanged: (t) => _set(_qroc!.copyWith(model: t)),
        ),
        const SizedBox(height: 16),
        Text(TxQcm.qrocElements, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          TxQcm.qrocElementsHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < c.elements.length; i++)
          Padding(
            key: _elementKeys[i],
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LineField(
                    key: ValueKey('element-field-${_elementKeys[i]}'),
                    fieldKey: ValueKey('element-$i'),
                    initial: c.elements[i].pattern,
                    hint: TxQcm.qrocElementHint,
                    maxLength: 2000,
                    onChanged: (t) =>
                        _editElement(i, (e) => e.copyWith(pattern: t)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: NumberField(
                    key: ValueKey('element-points-field-${_elementKeys[i]}'),
                    fieldKey: ValueKey('element-points-$i'),
                    initial: c.elements[i].points,
                    label: TxQcm.elementPoints,
                    onValid: (v) =>
                        _editElement(i, (e) => e.copyWith(points: v)),
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-element-$i'),
                  tooltip: TxQcm.removeElement,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeElement(i),
                ),
              ],
            ),
          ),
        if (c.elements.length < maxElements)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('add-element'),
              onPressed: _addElement,
              icon: const Icon(Icons.add),
              label: const Text(TxQcm.addElement),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------- TCS

  Widget _tcsBlock(BuildContext context, TcsQuestion c) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LineField(
          key: const ValueKey('tcs-hypothesis-field'),
          fieldKey: const ValueKey('tcs-hypothesis'),
          initial: c.hypothesis,
          label: TxQcm.tcsHypothesis,
          maxLength: 2000,
          multiline: true,
          onChanged: (t) => _set(_tcs.copyWith(hypothesis: t)),
        ),
        const SizedBox(height: 12),
        LineField(
          key: const ValueKey('tcs-new-info-field'),
          fieldKey: const ValueKey('tcs-new-info'),
          initial: c.newInfo,
          label: TxQcm.tcsNewInfo,
          maxLength: 2000,
          multiline: true,
          onChanged: (t) => _set(_tcs.copyWith(newInfo: t)),
        ),
        const SizedBox(height: 12),
        LineField(
          key: const ValueKey('tcs-low-field'),
          fieldKey: const ValueKey('tcs-low'),
          initial: c.lowLabel,
          label: TxQcm.tcsLow,
          hint: TxQcm.tcsLowDefault,
          maxLength: 200,
          onChanged: (t) => _set(_tcs.copyWith(lowLabel: t)),
        ),
        const SizedBox(height: 12),
        LineField(
          key: const ValueKey('tcs-high-field'),
          fieldKey: const ValueKey('tcs-high'),
          initial: c.highLabel,
          label: TxQcm.tcsHigh,
          hint: TxQcm.tcsHighDefault,
          maxLength: 200,
          onChanged: (t) => _set(_tcs.copyWith(highLabel: t)),
        ),
        const SizedBox(height: 16),
        Text(TxQcm.tcsPanel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          TxQcm.tcsPanelHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (var level = -2; level <= 2; level++)
          _PanelRow(
            key: ValueKey('panel-row-$level'),
            level: level,
            count: c.panel[level + 2],
            onChanged: (n) {
              final panel = [..._tcs.panel]..[level + 2] = n;
              _set(_tcs.copyWith(panel: panel));
            },
          ),
        const SizedBox(height: 4),
        Text(
          TxQcm.tcsExperts(c.panelTotal),
          key: const ValueKey('panel-total'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- QZP

  Future<void> _pickZoneImage(QzpQuestion c) async {
    if (c.image.isNotEmpty && c.zones.isNotEmpty) {
      final ok = await confirm(
        context,
        title: TxQcm.qzpChangeImage,
        message: TxQcm.qzpChangeConfirm,
        confirmLabel: TxQcm.qzpChangeImage,
      );
      if (!ok || !mounted) return;
    }
    final name = await _pickImage();
    if (name == null || !mounted) return;
    _set(_qzp.copyWith(image: name, zones: const []));
  }

  Widget _qzpBlock(BuildContext context, QzpQuestion c) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TxQcm.qzpImage, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (c.image.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('qzp-pick'),
              onPressed: () => _pickZoneImage(c),
              icon: const Icon(Icons.image_outlined),
              label: const Text(TxQcm.qzpPickImage),
            ),
          )
        else ...[
          ZoneEditor(
            image: c.image,
            zones: c.zones,
            onChanged: (zones) => _set(_qzp.copyWith(zones: zones)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('qzp-change'),
              onPressed: () => _pickZoneImage(c),
              icon: const Icon(Icons.swap_horiz),
              label: const Text(TxQcm.qzpChangeImage),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- Formulaire

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _typeRow(context),
        _caseRow(),
        const SizedBox(height: 16),
        QcmRichField(
          key: const ValueKey('body-field'),
          fieldKey: const ValueKey('body'),
          label: q is TcsQuestion ? TxQcm.tcsContext : TxQcm.body,
          initial: q.body,
          onChanged: (t) => _set(_q.withCommon(body: t)),
        ),
        const SizedBox(height: 16),
        _imagesBlock(context),
        const SizedBox(height: 20),
        switch (q) {
          ChoiceQuestion c => _choiceBlock(context, c),
          QrocQuestion c => _qrocBlock(context, c),
          TcsQuestion c => _tcsBlock(context, c),
          QzpQuestion c => _qzpBlock(context, c),
        },
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 160,
            child: NumberField(
              key: const ValueKey('points-field'),
              fieldKey: const ValueKey('points'),
              initial: q.points,
              label: TxQcm.points,
              hint: TxQcm.pointsHint,
              onValid: (v) => _set(_q.withCommon(points: v)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        QcmRichField(
          key: const ValueKey('explanation-field'),
          fieldKey: const ValueKey('explanation'),
          label: TxQcm.explanation,
          initial: q.explanation,
          minLines: 3,
          onChanged: (t) => _set(_q.withCommon(explanation: t)),
        ),
        SizedBox(height: theme.visualDensity.vertical < 0 ? 16 : 24),
      ],
    );
  }
}

/// Champ de texte simple qui garde son propre texte.
class LineField extends StatefulWidget {
  const LineField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.label,
    this.hint,
    this.maxLength,
    this.multiline = false,
    this.fieldKey,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final int? maxLength;
  final bool multiline;
  final Key? fieldKey;

  @override
  State<LineField> createState() => _LineFieldState();
}

class _LineFieldState extends State<LineField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: _controller,
    minLines: 1,
    maxLines: widget.multiline ? 6 : 1,
    keyboardType: widget.multiline ? TextInputType.multiline : null,
    maxLength: widget.maxLength,
    buildCounter: (
      _, {
      required currentLength,
      required isFocused,
      maxLength,
    }) => null,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      border: const OutlineInputBorder(),
    ),
    onChanged: widget.onChanged,
  );
}

/// Champ numérique : n'envoie que les valeurs valides (entre 0,01 et 1000) et
/// signale les autres.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.initial,
    required this.onValid,
    this.label,
    this.hint,
    this.fieldKey,
  });

  final double initial;
  final ValueChanged<double> onValid;
  final String? label;
  final String? hint;
  final Key? fieldKey;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatNumber(widget.initial),
  );
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    final v = parseNumber(text);
    final ok = v != null && v.isFinite && v > 0 && v <= 1000;
    setState(() => _invalid = !ok);
    if (ok) widget.onValid(v);
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: _controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      border: const OutlineInputBorder(),
      errorText: _invalid ? TxQcm.pointsInvalid : null,
      errorMaxLines: 2,
    ),
    onChanged: _changed,
  );
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    super.key,
    required this.level,
    required this.count,
    required this.onChanged,
  });

  final int level;
  final int count;
  final ValueChanged<int> onChanged;

  static const _max = 999;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            TxQcm.tcsLevel(level),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          key: ValueKey('panel-minus-$level'),
          tooltip: TxQcm.removeExpert,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: count <= 0 ? null : () => onChanged(count - 1),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$count',
            key: ValueKey('panel-count-$level'),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          key: ValueKey('panel-plus-$level'),
          tooltip: TxQcm.addExpert,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: count >= _max ? null : () => onChanged(count + 1),
        ),
      ],
    );
  }
}
