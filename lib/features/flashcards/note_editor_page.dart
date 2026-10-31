import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/flashcard_models.dart';
import '../../data/flashcards_repository.dart';
import '../../domain/note_types.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_cartes.dart';
import '../../ui/dialogs.dart';
import 'card_text.dart';
import 'text_editing.dart';

/// Création et modification d'une note (et donc de ses cartes).
///
/// En création, le deck choisi et le type restent d'une carte à la suivante
/// et un compteur indique combien de cartes ont été créées.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    this.deckId,
    this.noteId,
    this.documentId,
    this.initialType,
  });

  /// Deck proposé à la création.
  final int? deckId;

  /// Note à modifier ; null pour en créer une.
  final int? noteId;

  /// Poly auquel rattacher la note (création depuis un poly).
  final int? documentId;
  final NoteType? initialType;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _FieldSlot {
  _FieldSlot(this.key) : controller = TextEditingController(), focus = FocusNode();
  final String key;
  final TextEditingController controller;
  final FocusNode focus;
  bool pinned = false;
  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  static const _creatable = [NoteType.cloze, NoteType.basic, NoteType.reversed, NoteType.typed];

  late final Map<String, _FieldSlot> _slots = {
    for (final k in const ['text', 'front', 'back', 'extra', 'context'])
      k: _FieldSlot(k),
  };
  final _tags = TextEditingController();
  bool _tagsPinned = false;
  NoteType _type = NoteType.cloze;
  int? _deckId;
  bool _showContext = false;
  int _clozeNumber = 1;
  int _previewOrd = 0;
  int _created = 0;
  int _cardsCreated = 0;
  String? _error;

  bool get _isEdit => widget.noteId != null;

  @override
  void initState() {
    super.initState();
    final repo = context.read<FlashcardsRepository>();
    _type = widget.initialType ?? NoteType.cloze;
    if (_isEdit) {
      final n = repo.note(widget.noteId!);
      _type = n.type;
      _deckId = n.deckId;
      for (final e in _slots.entries) {
        e.value.controller.text = n.fields.text(e.key);
      }
      _showContext = n.fields.context.isNotEmpty;
      _tags.text = n.tags.join(' ');
      _clozeNumber = nextClozeNumber(n.fields.text('text'));
    } else {
      final decks = repo.decks();
      _deckId = widget.deckId ?? (decks.length == 1 ? decks.first.id : null);
    }
    for (final s in _slots.values) {
      s.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final s in _slots.values) {
      s.dispose();
    }
    _tags.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _error = null);
  }

  NoteFields _collect() {
    final data = <String, dynamic>{};
    void put(String k) {
      final t = _slots[k]!.controller.text.trim();
      if (t.isNotEmpty) data[k] = t;
    }

    switch (_type) {
      case NoteType.cloze:
        put('text');
      case NoteType.basic || NoteType.reversed || NoteType.typed:
        put('front');
        put('back');
      case NoteType.occlusion:
        break;
    }
    put('extra');
    if (_showContext) put('context');
    return NoteFields(data);
  }

  List<String> _tagList() => [
        for (final t in _tags.text.split(RegExp(r'\s+')))
          if (t.isNotEmpty) t,
      ];

  // ----------------------------------------------------------- actions

  Future<void> _submit() async {
    final repo = context.read<FlashcardsRepository>();
    if (_deckId == null) {
      setState(() => _error = TxCards.chooseDeck);
      return;
    }
    final fields = _collect();
    final issue = validateNote(_type, fields);
    if (issue != null) {
      setState(() => _error = TxCards.issue(issue));
      return;
    }
    if (_isEdit) {
      final ok = await guarded(context, () => repo.updateNote(widget.noteId!, fields, tags: _tagList()));
      if (ok && mounted) {
        showInfo(context, TxCards.noteSaved);
        Navigator.of(context).pop();
      }
      return;
    }
    if (repo.hasDuplicate(_deckId!, _type, fields)) {
      final again = await confirm(
        context,
        title: TxCards.duplicateTitle,
        message: TxCards.duplicate,
        confirmLabel: TxCards.addAnyway,
      );
      if (!again || !mounted) return;
    }
    NoteRow? added;
    final ok = await guarded(context, () {
      added = repo.addNote(
        _deckId!,
        _type,
        fields,
        tags: _tagList(),
        documentId: widget.documentId,
      );
    });
    if (!ok || !mounted || added == null) return;
    setState(() {
      _created++;
      _cardsCreated += added!.cardCount;
      for (final s in _slots.values) {
        if (!s.pinned) s.controller.clear();
      }
      if (!_tagsPinned) _tags.clear();
      _clozeNumber = nextClozeNumber(_slots['text']!.controller.text);
      _previewOrd = 0;
      _error = null;
    });
    showInfo(context, TxCards.noteAdded(added!.cardCount));
    _focusFirst();
  }

  void _focusFirst() {
    final first = _type == NoteType.cloze ? 'text' : 'front';
    _slots[first]!.focus.requestFocus();
  }

  _FieldSlot? get _focused {
    for (final s in _slots.values) {
      if (s.focus.hasFocus) return s;
    }
    return null;
  }

  void _format(Format f, [_FieldSlot? slot]) {
    final s = slot ?? _focused;
    if (s == null) return;
    s.controller.value = toggleFormat(s.controller.value, f);
    s.focus.requestFocus();
  }

  void _cloze() {
    final s = _slots['text']!;
    final r = insertCloze(s.controller.value, _clozeNumber);
    if (r == null) {
      showInfo(context, TxCards.clozeSelectFirst);
      return;
    }
    s.controller.value = r;
    setState(() => _clozeNumber = nextClozeNumber(r.text));
    s.focus.requestFocus();
  }

  void _setType(NoteType t) {
    if (_isEdit || t == _type) return;
    setState(() {
      _type = t;
      _error = null;
      _previewOrd = 0;
    });
    _focusFirst();
  }

  Map<ShortcutActivator, VoidCallback> _bindings() {
    final map = <ShortcutActivator, VoidCallback>{};
    void both(LogicalKeyboardKey key, VoidCallback cb, {bool shift = false}) {
      map[SingleActivator(key, control: true, shift: shift)] = cb;
      map[SingleActivator(key, meta: true, shift: shift)] = cb;
    }

    both(LogicalKeyboardKey.enter, _submit);
    both(LogicalKeyboardKey.keyB, () => _format(Format.bold));
    both(LogicalKeyboardKey.keyI, () => _format(Format.italic));
    both(LogicalKeyboardKey.keyU, () => _format(Format.underline));
    if (_type == NoteType.cloze) {
      both(LogicalKeyboardKey.keyC, _cloze, shift: true);
    }
    for (var i = 0; i < _creatable.length; i++) {
      final key = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ][i];
      map[SingleActivator(key, alt: true)] = () => _setType(_creatable[i]);
    }
    return map;
  }

  // ------------------------------------------------------------- vue

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final repo = context.read<FlashcardsRepository>();
    final theme = Theme.of(context);
    final decks = repo.decks();
    final fields = _collect();
    final ords = validateNote(_type, fields) == null ? cardOrdinals(_type, fields) : const <int>[];
    final ord = ords.isEmpty ? 0 : (ords.contains(_previewOrd) ? _previewOrd : ords.first);

    return CallbackShortcuts(
      bindings: _bindings(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? TxCards.editCard : TxCards.newCard),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _submit,
                child: Text(_isEdit ? TxCards.saveChanges : TxCards.add),
              ),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (!_isEdit) ...[
                  _deckPicker(repo, decks),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in _creatable)
                        ChoiceChip(
                          label: Text(TxCards.typeName(t)),
                          selected: _type == t,
                          onSelected: (_) => _setType(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TxCards.typeHelp(_type),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Text(
                    TxCards.typeName(_type),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                ],
                ..._fieldWidgets(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tags,
                        decoration: const InputDecoration(
                          labelText: TxCards.fieldTags,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (!_isEdit)
                      _PinButton(
                        pinned: _tagsPinned,
                        onChanged: (v) => setState(() => _tagsPinned = v),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                _preview(fields, ords, ord),
                const SizedBox(height: 16),
                if (!_isEdit && _created > 0)
                  Text(
                    TxCards.added(_cardsCreated),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                Text(
                  TxCards.shortcutsHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _deckPicker(FlashcardsRepository repo, List<Deck> decks) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('deck-${_deckId ?? 'none'}-${decks.length}'),
            initialValue: decks.any((d) => d.id == _deckId) ? _deckId : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: TxCards.deckLabel,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final d in decks) DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (v) => setState(() {
              _deckId = v;
              _error = null;
            }),
          ),
        ),
        IconButton(
          tooltip: TxCards.newDeck,
          icon: const Icon(Icons.add),
          onPressed: () async {
            final name = await promptText(
              context,
              title: TxCards.newDeck,
              label: TxCards.deckName,
              confirmLabel: Tx.create,
            );
            if (name == null || !mounted) return;
            await guarded(context, () {
              final d = repo.createDeck(name);
              setState(() => _deckId = d.id);
            });
          },
        ),
      ],
    );
  }

  List<Widget> _fieldWidgets() {
    final out = <Widget>[];
    void rich(String key, String label, {int minLines = 3, bool cloze = false, bool optional = false}) {
      final slot = _slots[key]!;
      out.add(_RichField(
        label: label,
        slot: slot,
        minLines: minLines,
        showPin: !_isEdit,
        onFormat: (f) => _format(f, slot),
        onPin: (v) => setState(() => slot.pinned = v),
        cloze: cloze
            ? _ClozeControls(
                number: _clozeNumber,
                onPrev: () => setState(() => _clozeNumber = _clozeNumber > 1 ? _clozeNumber - 1 : 1),
                onNext: () => setState(() => _clozeNumber++),
                onInsert: _cloze,
              )
            : null,
      ));
      out.add(const SizedBox(height: 12));
    }

    switch (_type) {
      case NoteType.cloze:
        rich('text', TxCards.fieldText, minLines: 4, cloze: true);
      case NoteType.basic || NoteType.reversed || NoteType.typed:
        rich('front', TxCards.fieldFront);
        rich('back', TxCards.fieldBack);
      case NoteType.occlusion:
        break;
    }
    rich('extra', TxCards.fieldExtra, minLines: 2);
    if (_showContext) {
      rich('context', TxCards.fieldContext, minLines: 2);
    }
    out.add(Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() {
          _showContext = !_showContext;
          if (!_showContext) _slots['context']!.controller.clear();
        }),
        icon: Icon(_showContext ? Icons.remove : Icons.add),
        label: Text(_showContext ? TxCards.removeContext : TxCards.addContext),
      ),
    ));
    return out;
  }

  Widget _preview(NoteFields fields, List<int> ords, int ord) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget body;
    if (ords.isEmpty) {
      body = Text(
        TxCards.previewEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
      );
    } else {
      final face = renderFace(_type, fields, ord);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(TxCards.previewQuestion, style: theme.textTheme.labelMedium?.copyWith(color: scheme.outline)),
          const SizedBox(height: 6),
          FaceText(face.question, textAlign: TextAlign.start, style: theme.textTheme.bodyLarge),
          const Divider(height: 24),
          Text(TxCards.previewAnswer, style: theme.textTheme.labelMedium?.copyWith(color: scheme.outline)),
          const SizedBox(height: 6),
          FaceText(face.answer, textAlign: TextAlign.start, style: theme.textTheme.bodyLarge),
          if (face.extra.isNotEmpty) ...[
            const SizedBox(height: 8),
            RichFieldText(face.extra, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (ords.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final o in ords)
                  ChoiceChip(
                    label: Text(_type == NoteType.cloze
                        ? TxCards.clozeOrdinal(o)
                        : TxCards.cardOrdinal(o)),
                    selected: o == ord,
                    onSelected: (_) => setState(() => _previewOrd = o),
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TxCards.preview, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

class _ClozeControls {
  const _ClozeControls({
    required this.number,
    required this.onPrev,
    required this.onNext,
    required this.onInsert,
  });
  final int number;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onInsert;
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.pinned, required this.onChanged});
  final bool pinned;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: pinned ? 'Ne plus garder ce champ' : 'Garder ce champ pour la carte suivante',
        isSelected: pinned,
        icon: const Icon(Icons.push_pin_outlined),
        selectedIcon: const Icon(Icons.push_pin),
        onPressed: () => onChanged(!pinned),
      );
}

class _RichField extends StatelessWidget {
  const _RichField({
    required this.label,
    required this.slot,
    required this.minLines,
    required this.showPin,
    required this.onFormat,
    required this.onPin,
    this.cloze,
  });

  final String label;
  final _FieldSlot slot;
  final int minLines;
  final bool showPin;
  final ValueChanged<Format> onFormat;
  final ValueChanged<bool> onPin;
  final _ClozeControls? cloze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget fmt(IconData icon, String tip, Format f) => IconButton(
          tooltip: tip,
          icon: Icon(icon),
          onPressed: () => onFormat(f),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            fmt(Icons.format_bold, TxCards.bold, Format.bold),
            fmt(Icons.format_italic, TxCards.italic, Format.italic),
            fmt(Icons.format_underline, TxCards.underline, Format.underline),
            fmt(Icons.border_color_outlined, TxCards.highlight, Format.highlight),
            if (cloze != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: TxCards.clozePrev,
                icon: const Icon(Icons.remove),
                onPressed: cloze!.onPrev,
              ),
              Text('c${cloze!.number}', style: theme.textTheme.titleSmall),
              IconButton(
                tooltip: TxCards.clozeNext,
                icon: const Icon(Icons.add),
                onPressed: cloze!.onNext,
              ),
              FilledButton.tonalIcon(
                onPressed: cloze!.onInsert,
                icon: const Icon(Icons.data_object),
                label: const Text(TxCards.cloze),
              ),
            ],
            if (showPin)
              _PinButton(pinned: slot.pinned, onChanged: onPin),
          ],
        ),
        TextField(
          controller: slot.controller,
          focusNode: slot.focus,
          minLines: minLines,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
