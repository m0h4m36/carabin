import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/errors.dart';
import '../../data/qcm_models.dart';
import '../../data/qcm_repository.dart';
import '../../domain/qcm/exam.dart';
import '../../domain/qcm/grading.dart';
import '../../domain/qcm/plain_text.dart';
import '../../domain/qcm/question.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import '../../ui/status_colors.dart';
import '../../ui/widgets.dart';
import 'article_view.dart';
import 'case_form.dart';
import 'exam_actions.dart';
import 'question_form.dart';
import 'question_view.dart';

/// Largeur à partir de laquelle l'éditeur montre ses trois colonnes.
const double kEditorWideBreakpoint = 1180;

enum _QuestionAction { up, down, duplicate, delete }

enum _CaseAction { up, down, addQcm, addQroc, addTcs, addQzp, delete }

enum _HeaderAction {
  shuffle,
  duplicate,
  subject,
  items,
  poly,
  detach,
  share,
  delete,
}

/// Éditeur d'une série : liste des questions et des cas, formulaire d'écriture
/// et aperçu tel que l'étudiant le verra. Tout est enregistré au fil de la
/// saisie.
class ExamEditorPage extends StatefulWidget {
  const ExamEditorPage({super.key, required this.examId});

  final int examId;

  @override
  State<ExamEditorPage> createState() => _ExamEditorPageState();
}

class _ExamEditorPageState extends State<ExamEditorPage> {
  int? _questionId;
  int? _caseId;

  /// Onglet affiché quand l'écran est étroit : 0 liste, 1 édition, 2 aperçu.
  int _tab = 0;
  bool _reveal = false;
  Answer? _answer;
  int? _answerFor;

  QcmRepository get _repo => context.read<QcmRepository>();

  void _select({int? question, int? kase, bool openForm = false}) {
    setState(() {
      _questionId = question;
      _caseId = kase;
      _reveal = false;
      _answer = null;
      _answerFor = question;
      if (openForm) _tab = 1;
    });
  }

  Future<void> _addQuestion(QuestionKind kind, {int? caseId}) async {
    int? id;
    final ok = await guarded(context, () {
      id = _repo.addQuestion(
        widget.examId,
        Question.empty(kind),
        caseId: caseId,
      );
    });
    if (ok && id != null && mounted) _select(question: id, openForm: true);
  }

  Future<void> _addCase() async {
    final genre = await pickFromList<CaseGenre>(
      context,
      title: TxQcm.addCaseTitle,
      choices: [
        for (final g in CaseGenre.values)
          Choice(g, TxQcm.genreName(g), subtitle: TxQcm.genreHelp(g)),
      ],
    );
    if (genre == null || !mounted) return;
    int? id;
    final ok = await guarded(context, () {
      id = _repo.addCase(widget.examId, CaseInfo(genre: genre)).id;
    });
    if (ok && id != null && mounted) _select(kase: id, openForm: true);
  }

  Future<void> _deleteQuestion(QuestionRow row, int number) async {
    final ok = await confirm(
      context,
      title: TxQcm.deleteQuestion,
      message: TxQcm.confirmDeleteQuestion(number),
      confirmLabel: TxQcm.menuDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await guarded(context, () => _repo.deleteQuestion(row.id));
    if (done && _questionId == row.id && mounted) _select();
  }

  Future<void> _deleteCase(CaseUnit unit, String name) async {
    final ok = await confirm(
      context,
      title: TxQcm.deleteCase,
      message: TxQcm.confirmDeleteCase(name, unit.questions.length),
      confirmLabel: TxQcm.menuDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final selectedInside =
        _caseId == unit.kase.id ||
        unit.questions.any((q) => q.id == _questionId);
    final done = await guarded(context, () => _repo.deleteCase(unit.kase.id));
    if (done && selectedInside && mounted) _select();
  }

  Future<void> _duplicateQuestion(QuestionRow row) async {
    int? id;
    final ok = await guarded(context, () {
      id = _repo.duplicateQuestion(row.id);
    });
    if (ok && id != null && mounted) _select(question: id, openForm: true);
  }

  Future<void> _shuffle() async {
    final ok = await confirm(
      context,
      title: TxQcm.shuffleOrder,
      message: TxQcm.shuffleConfirm,
      confirmLabel: TxQcm.shuffleOrder,
    );
    if (!ok || !mounted) return;
    await guarded(context, () => _repo.shuffleUnits(widget.examId, Random()));
  }

  Future<void> _headerAction(_HeaderAction a, ExamRow exam) async {
    switch (a) {
      case _HeaderAction.shuffle:
        await _shuffle();
      case _HeaderAction.duplicate:
        await duplicateExamFlow(context, exam);
      case _HeaderAction.subject:
        await chooseSubjectForExams(context, [exam.id]);
      case _HeaderAction.items:
        await editItemsFlow(context, exam);
      case _HeaderAction.poly:
        await chooseCourseForExam(context, exam.id);
      case _HeaderAction.detach:
        await detachCourseFromExam(context, exam.id);
      case _HeaderAction.share:
        await shareExamFlow(context, exam.id);
      case _HeaderAction.delete:
        final done = await deleteExamsFlow(context, [exam]);
        if (done && mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final ExamContent content;
    try {
      content = _repo.content(widget.examId);
    } on NotFoundError {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    final exam = content.exam;
    final courses = context.read<CoursesRepository>();

    // Numéros des questions et noms des cas, dans l'ordre de la série.
    final numbers = <int, int>{};
    final caseNames = <int, String>{};
    final caseInfos = <int, CaseInfo>{};
    var n = 0;
    var caseIndex = 0;
    for (final u in content.units) {
      if (u is CaseUnit) {
        caseIndex++;
        caseNames[u.kase.id] = TxQcm.caseName(u.kase.info, caseIndex);
        caseInfos[u.kase.id] = u.kase.info;
      }
      for (final q in u.questions) {
        numbers[q.id] = ++n;
      }
    }
    QuestionRow? selectedQuestion;
    for (final q in content.questions) {
      if (q.id == _questionId) selectedQuestion = q;
    }
    CaseUnit? selectedCase;
    for (final u in content.units) {
      if (u is CaseUnit && u.kase.id == _caseId) selectedCase = u;
    }

    String? subjectName;
    Color? subjectColor;
    if (exam.subjectId != null) {
      for (final (s, _, _) in courses.allSubjects()) {
        if (s.id == exam.subjectId) {
          subjectName = s.name;
          subjectColor = colorOf(s.color);
        }
      }
    }
    final polyTitle = exam.documentId == null
        ? null
        : courses.document(exam.documentId!)?.title;

    final ready = content.readyCount;
    final total = content.questions.length;

    final list = _ListPane(
      content: content,
      numbers: numbers,
      caseNames: caseNames,
      selectedQuestion: selectedQuestion?.id,
      selectedCase: selectedCase?.kase.id,
      onAdd: (kind) => _addQuestion(kind),
      onAddCase: _addCase,
      onSelectQuestion: (id) => _select(question: id, openForm: true),
      onSelectCase: (id) => _select(kase: id, openForm: true),
      onQuestionAction: (row, a) async {
        switch (a) {
          case _QuestionAction.up:
            await guarded(context, () => _repo.moveQuestion(row.id, -1));
          case _QuestionAction.down:
            await guarded(context, () => _repo.moveQuestion(row.id, 1));
          case _QuestionAction.duplicate:
            await _duplicateQuestion(row);
          case _QuestionAction.delete:
            await _deleteQuestion(row, numbers[row.id] ?? 0);
        }
      },
      onCaseAction: (unit, a) async {
        switch (a) {
          case _CaseAction.up:
            await guarded(context, () => _repo.moveCase(unit.kase.id, -1));
          case _CaseAction.down:
            await guarded(context, () => _repo.moveCase(unit.kase.id, 1));
          case _CaseAction.addQcm:
            await _addQuestion(QuestionKind.qcm, caseId: unit.kase.id);
          case _CaseAction.addQroc:
            await _addQuestion(QuestionKind.qroc, caseId: unit.kase.id);
          case _CaseAction.addTcs:
            await _addQuestion(QuestionKind.tcs, caseId: unit.kase.id);
          case _CaseAction.addQzp:
            await _addQuestion(QuestionKind.qzp, caseId: unit.kase.id);
          case _CaseAction.delete:
            await _deleteCase(unit, caseNames[unit.kase.id] ?? '');
        }
      },
    );

    final Widget form;
    if (selectedQuestion != null) {
      final row = selectedQuestion;
      form = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: QuestionForm(
          key: ValueKey('form-question-${row.id}'),
          question: row.question,
          cases: [
            for (final e in caseNames.entries) CaseChoice(e.key, e.value),
          ],
          caseId: row.caseId,
          onCaseChanged: (id) =>
              guarded(context, () => _repo.setQuestionCase(row.id, id)),
          onChanged: (q) =>
              guarded(context, () => _repo.updateQuestion(row.id, q)),
        ),
      );
    } else if (selectedCase != null) {
      final unit = selectedCase;
      form = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: CaseForm(
          key: ValueKey('form-case-${unit.kase.id}'),
          info: unit.kase.info,
          defaultTitle: caseNames[unit.kase.id] ?? '',
          onChanged: (info) =>
              guarded(context, () => _repo.updateCase(unit.kase.id, info)),
        ),
      );
    } else {
      form = const EmptyState(icon: Icons.edit_note, title: TxQcm.pickQuestion);
    }

    final Widget preview;
    if (selectedQuestion != null) {
      final row = selectedQuestion;
      final info = row.caseId == null ? null : caseInfos[row.caseId];
      preview = _PreviewPane(
        key: ValueKey('preview-${row.id}'),
        row: row,
        number: numbers[row.id] ?? 0,
        caseInfo: info,
        caseName: row.caseId == null ? null : caseNames[row.caseId],
        reveal: _reveal,
        answer: _answerFor == row.id ? _answer : null,
        onReveal: (v) => setState(() => _reveal = v),
        onAnswer: (a) => setState(() {
          _answer = a;
          _answerFor = row.id;
        }),
      );
    } else if (selectedCase != null) {
      final unit = selectedCase;
      preview = _CasePreview(
        info: unit.kase.info,
        name: caseNames[unit.kase.id] ?? '',
        questions: unit.questions.length,
      );
    } else {
      preview = const EmptyState(
        icon: Icons.visibility_outlined,
        title: TxQcm.topPreviewTitle,
        message: TxQcm.pickQuestion,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: exam.title,
              crumbs: [
                Crumb(TxQcm.editorBack, () => Navigator.of(context).maybePop()),
              ],
              actions: [
                IconButton(
                  key: const ValueKey('rename-exam'),
                  tooltip: TxQcm.rename,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => renameExamFlow(context, exam),
                ),
                PopupMenuButton<_HeaderAction>(
                  key: const ValueKey('exam-menu'),
                  tooltip: Tx.more,
                  onSelected: (a) => _headerAction(a, exam),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _HeaderAction.shuffle,
                      child: Text(TxQcm.shuffleOrder),
                    ),
                    const PopupMenuItem(
                      value: _HeaderAction.subject,
                      child: Text(TxQcm.menuSubject),
                    ),
                    const PopupMenuItem(
                      value: _HeaderAction.items,
                      child: Text(TxQcm.itemsTitle),
                    ),
                    const PopupMenuItem(
                      value: _HeaderAction.poly,
                      child: Text(TxQcm.menuAttach),
                    ),
                    if (exam.documentId != null)
                      const PopupMenuItem(
                        value: _HeaderAction.detach,
                        child: Text(TxQcm.detachPoly),
                      ),
                    const PopupMenuItem(
                      value: _HeaderAction.duplicate,
                      child: Text(TxQcm.menuDuplicate),
                    ),
                    const PopupMenuItem(
                      value: _HeaderAction.share,
                      child: Text(TxQcm.menuShare),
                    ),
                    const PopupMenuItem(
                      value: _HeaderAction.delete,
                      child: Text(TxQcm.menuDelete),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    key: const ValueKey('subject-chip'),
                    avatar: subjectColor == null
                        ? null
                        : ColorDot(subjectColor),
                    label: Text(subjectName ?? TxQcm.noSubject),
                    onPressed: () => chooseSubjectForExams(context, [exam.id]),
                  ),
                  ActionChip(
                    key: const ValueKey('items-chip'),
                    label: Text(
                      exam.items.trim().isEmpty
                          ? TxQcm.itemsNone
                          : TxQcm.itemsValue(exam.items.trim()),
                    ),
                    onPressed: () => editItemsFlow(context, exam),
                  ),
                  ActionChip(
                    key: const ValueKey('poly-chip'),
                    avatar: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(
                      exam.documentId == null
                          ? TxQcm.noPoly
                          : TxQcm.polyAttached(polyTitle ?? '…'),
                    ),
                    onPressed: () => chooseCourseForExam(context, exam.id),
                  ),
                  Text(
                    total == 0
                        ? TxQcm.noQuestions
                        : TxQcm.readyCounter(ready, total - ready),
                    key: const ValueKey('ready-counter'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= kEditorWideBreakpoint) {
                    return Row(
                      children: [
                        SizedBox(width: 330, child: list),
                        const VerticalDivider(width: 1),
                        Expanded(child: form),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 420, child: preview),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SegmentedButton<int>(
                          key: const ValueKey('editor-tabs'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: 0,
                              label: Text(TxQcm.tabQuestions),
                            ),
                            ButtonSegment(value: 1, label: Text(TxQcm.tabForm)),
                            ButtonSegment(
                              value: 2,
                              label: Text(TxQcm.tabPreview),
                            ),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (s) =>
                              setState(() => _tab = s.first),
                        ),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _tab,
                          children: [list, form, preview],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- liste

class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.content,
    required this.numbers,
    required this.caseNames,
    required this.selectedQuestion,
    required this.selectedCase,
    required this.onAdd,
    required this.onAddCase,
    required this.onSelectQuestion,
    required this.onSelectCase,
    required this.onQuestionAction,
    required this.onCaseAction,
  });

  final ExamContent content;
  final Map<int, int> numbers;
  final Map<int, String> caseNames;
  final int? selectedQuestion;
  final int? selectedCase;
  final ValueChanged<QuestionKind> onAdd;
  final VoidCallback onAddCase;
  final ValueChanged<int> onSelectQuestion;
  final ValueChanged<int> onSelectCase;
  final void Function(QuestionRow, _QuestionAction) onQuestionAction;
  final void Function(CaseUnit, _CaseAction) onCaseAction;

  @override
  Widget build(BuildContext context) {
    final units = content.units;
    final tiles = <Widget>[];
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      switch (u) {
        case SingleUnit(:final question):
          tiles.add(
            _QuestionTile(
              row: question,
              number: numbers[question.id] ?? 0,
              selected: question.id == selectedQuestion,
              canUp: i > 0,
              canDown: i < units.length - 1,
              onTap: () => onSelectQuestion(question.id),
              onAction: (a) => onQuestionAction(question, a),
            ),
          );
        case CaseUnit():
          tiles.add(
            _CaseTile(
              unit: u,
              name: caseNames[u.kase.id] ?? '',
              selected: u.kase.id == selectedCase,
              canUp: i > 0,
              canDown: i < units.length - 1,
              onTap: () => onSelectCase(u.kase.id),
              onAction: (a) => onCaseAction(u, a),
            ),
          );
          for (var j = 0; j < u.questions.length; j++) {
            final q = u.questions[j];
            tiles.add(
              _QuestionTile(
                row: q,
                number: numbers[q.id] ?? 0,
                selected: q.id == selectedQuestion,
                indented: true,
                canUp: j > 0,
                canDown: j < u.questions.length - 1,
                onTap: () => onSelectQuestion(q.id),
                onAction: (a) => onQuestionAction(q, a),
              ),
            );
          }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AddButton(
                key: const ValueKey('add-qcm'),
                label: TxQcm.addQcm,
                onPressed: () => onAdd(QuestionKind.qcm),
              ),
              _AddButton(
                key: const ValueKey('add-qroc'),
                label: TxQcm.addQroc,
                onPressed: () => onAdd(QuestionKind.qroc),
              ),
              _AddButton(
                key: const ValueKey('add-tcs'),
                label: TxQcm.addTcs,
                onPressed: () => onAdd(QuestionKind.tcs),
              ),
              _AddButton(
                key: const ValueKey('add-qzp'),
                label: TxQcm.addQzp,
                onPressed: () => onAdd(QuestionKind.qzp),
              ),
              _AddButton(
                key: const ValueKey('add-case'),
                label: TxQcm.addCase,
                icon: Icons.folder_open_outlined,
                onPressed: onAddCase,
              ),
            ],
          ),
        ),
        Expanded(
          child: tiles.isEmpty
              ? const EmptyState(
                  icon: Icons.quiz_outlined,
                  title: TxQcm.noQuestionYet,
                )
              : ListView(
                  key: const ValueKey('question-list'),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: tiles,
                ),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

/// Début de l'énoncé, ou ce qui en tient lieu.
String questionTitle(Question q) {
  final s = snippet(q.body);
  if (s.isNotEmpty) return s;
  if (q is TcsQuestion) {
    final h = snippet(q.hypothesis);
    if (h.isNotEmpty) return h;
  }
  return TxQcm.noBody;
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.row,
    required this.number,
    required this.selected,
    required this.canUp,
    required this.canDown,
    required this.onTap,
    required this.onAction,
    this.indented = false,
  });

  final QuestionRow row;
  final int number;
  final bool selected;
  final bool indented;
  final bool canUp;
  final bool canDown;
  final VoidCallback onTap;
  final ValueChanged<_QuestionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final q = row.question;
    final ready = q.isReady;
    return Padding(
      padding: EdgeInsets.only(left: indented ? 20 : 0),
      child: ListTile(
        key: ValueKey('question-${row.id}'),
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.4,
        ),
        minVerticalPadding: 8,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          foregroundColor: theme.colorScheme.onSurface,
          child: Text('$number'),
        ),
        title: Text(
          questionTitle(q),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(TxQcm.kindBadge(q), style: theme.textTheme.labelMedium),
            const SizedBox(width: 8),
            Icon(
              ready ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: ready ? status.right : status.partial,
            ),
            const SizedBox(width: 4),
            Text(
              ready ? TxQcm.ready : TxQcm.toFinish,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ready ? status.right : status.partial,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<_QuestionAction>(
          key: ValueKey('question-menu-${row.id}'),
          tooltip: Tx.more,
          onSelected: onAction,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _QuestionAction.up,
              enabled: canUp,
              child: const Text(TxQcm.moveUp),
            ),
            PopupMenuItem(
              value: _QuestionAction.down,
              enabled: canDown,
              child: const Text(TxQcm.moveDown),
            ),
            const PopupMenuItem(
              value: _QuestionAction.duplicate,
              child: Text(TxQcm.duplicate),
            ),
            const PopupMenuItem(
              value: _QuestionAction.delete,
              child: Text(TxQcm.deleteQuestion),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  const _CaseTile({
    required this.unit,
    required this.name,
    required this.selected,
    required this.canUp,
    required this.canDown,
    required this.onTap,
    required this.onAction,
  });

  final CaseUnit unit;
  final String name;
  final bool selected;
  final bool canUp;
  final bool canDown;
  final VoidCallback onTap;
  final ValueChanged<_CaseAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        key: ValueKey('case-${unit.kase.id}'),
        selected: selected,
        leading: const Icon(Icons.folder_open_outlined),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${TxQcm.genreName(unit.kase.info.genre)} · '
          '${TxQcm.caseQuestions(unit.questions.length)}',
        ),
        trailing: PopupMenuButton<_CaseAction>(
          key: ValueKey('case-menu-${unit.kase.id}'),
          tooltip: Tx.more,
          onSelected: onAction,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _CaseAction.up,
              enabled: canUp,
              child: const Text(TxQcm.moveUp),
            ),
            PopupMenuItem(
              value: _CaseAction.down,
              enabled: canDown,
              child: const Text(TxQcm.moveDown),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _CaseAction.addQcm,
              child: Text('${TxQcm.addToCase} · ${TxQcm.addQcm}'),
            ),
            const PopupMenuItem(
              value: _CaseAction.addQroc,
              child: Text('${TxQcm.addToCase} · ${TxQcm.addQroc}'),
            ),
            const PopupMenuItem(
              value: _CaseAction.addTcs,
              child: Text('${TxQcm.addToCase} · ${TxQcm.addTcs}'),
            ),
            const PopupMenuItem(
              value: _CaseAction.addQzp,
              child: Text('${TxQcm.addToCase} · ${TxQcm.addQzp}'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _CaseAction.delete,
              child: Text(TxQcm.deleteCase),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ------------------------------------------------------------------ aperçu

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    super.key,
    required this.row,
    required this.number,
    required this.caseInfo,
    required this.caseName,
    required this.reveal,
    required this.answer,
    required this.onReveal,
    required this.onAnswer,
  });

  final QuestionRow row;
  final int number;
  final CaseInfo? caseInfo;
  final String? caseName;
  final bool reveal;
  final Answer? answer;
  final ValueChanged<bool> onReveal;
  final ValueChanged<Answer?> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    var q = row.question;
    if (q is ChoiceQuestion) q = q.cleaned();
    final issues = row.question.issues;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(TxQcm.topPreviewTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (issues.isEmpty)
          Row(
            key: const ValueKey('all-good'),
            children: [
              Icon(Icons.check_circle_outline, color: status.right, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text(TxQcm.allGood)),
            ],
          )
        else
          Card(
            key: const ValueKey('issues'),
            margin: EdgeInsets.zero,
            color: status.partial.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: status.partial,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TxQcm.validationTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final i in issues) Text('• ${TxQcm.issueMessage(i)}'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (caseInfo != null) ...[
          _CaseCard(info: caseInfo!, name: caseName ?? ''),
          const SizedBox(height: 12),
        ],
        const Divider(),
        SwitchListTile(
          key: const ValueKey('reveal-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text(TxQcm.showCorrection),
          value: reveal,
          onChanged: onReveal,
        ),
        const SizedBox(height: 8),
        QuestionView(
          question: q,
          heading: TxQcm.questionLabel(number),
          answer: answer,
          reveal: reveal,
          onChanged: reveal ? null : onAnswer,
        ),
      ],
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.info, required this.name});

  final CaseInfo info;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('case-card'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleSmall),
            if (info.context.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              QcmText(info.context),
            ],
            if (info.genre == CaseGenre.lca && info.hasArticle) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('case-card-article'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ArticlePage(info: info, title: name),
                  ),
                ),
                icon: const Icon(Icons.article_outlined),
                label: const Text(TxQcm.caseOpenArticle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CasePreview extends StatelessWidget {
  const _CasePreview({
    required this.info,
    required this.name,
    required this.questions,
  });

  final CaseInfo info;
  final String name;
  final int questions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(TxQcm.topPreviewTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _CaseCard(info: info, name: name),
        const SizedBox(height: 12),
        Text(
          TxQcm.caseQuestions(questions),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
