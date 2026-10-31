import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/names.dart';
import '../../data/qcm_models.dart';
import '../../data/qcm_repository.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import '../../ui/widgets.dart';
import 'exam_actions.dart';
import 'exam_card.dart';
import 'exam_editor_page.dart';
import 'passage_flows.dart';

enum _FilterKind { all, never, noSubject, subject }

class _Filter {
  const _Filter(this.kind, [this.subjectId]);
  const _Filter.all() : this(_FilterKind.all);

  final _FilterKind kind;
  final int? subjectId;

  @override
  bool operator ==(Object other) =>
      other is _Filter && other.kind == kind && other.subjectId == subjectId;

  @override
  int get hashCode => Object.hash(kind, subjectId);

  bool accepts(ExamSummary s) => switch (kind) {
    _FilterKind.all => true,
    _FilterKind.never => s.attempts == 0,
    _FilterKind.noSubject => s.exam.subjectId == null,
    _FilterKind.subject => s.exam.subjectId == subjectId,
  };
}

/// Accueil des QCM : séries à passer, annales et édition.
class QcmPage extends StatefulWidget {
  const QcmPage({super.key});

  @override
  State<QcmPage> createState() => _QcmPageState();
}

class _QcmPageState extends State<QcmPage> {
  /// 0 : Passer, 1 : Édition.
  int _tab = 0;
  bool _pastPapers = false;
  _Filter _filter = const _Filter.all();
  final _search = TextEditingController();

  /// Séries cochées en mode sélection (null = hors mode sélection).
  Set<int>? _selection;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  QcmRepository get _repo => context.read<QcmRepository>();

  void _push(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  void _openEditor(int examId) => _push(ExamEditorPage(examId: examId));

  Future<void> _newSeries(int? subjectId) async {
    final id = await createSeriesFlow(
      context,
      subjectId: subjectId,
      pastPaper: _pastPapers,
    );
    if (id == null || !mounted) return;
    _openEditor(id);
  }

  Future<void> _import() async {
    final id = await importExamFlow(context);
    if (id == null || !mounted) return;
    final exam = _repo.exam(id);
    setState(() {
      _pastPapers = exam.isPastPaper;
      _filter = const _Filter.all();
      _search.clear();
    });
  }

  Future<void> _act(ExamSummary s, ExamAction a) async {
    final exam = s.exam;
    switch (a) {
      case ExamAction.edit:
        _openEditor(exam.id);
      case ExamAction.subject:
        await chooseSubjectForExams(context, [exam.id]);
      case ExamAction.pastPaper:
        await guarded(
          context,
          () => _repo.setPastPaper([exam.id], !exam.pastPaper),
        );
      case ExamAction.attach:
        await chooseCourseForExam(context, exam.id);
      case ExamAction.detach:
        await detachCourseFromExam(context, exam.id);
      case ExamAction.duplicate:
        await duplicateExamFlow(context, exam);
      case ExamAction.share:
        await shareExamFlow(context, exam.id);
      case ExamAction.select:
        setState(() => _selection = {exam.id});
      case ExamAction.delete:
        await deleteExamsFlow(context, [exam]);
    }
  }

  /// Passer une série : réglages puis passage.
  Future<void> _compose(ExamSummary s) => startExamPassage(context, s);

  /// S'entraîner sur les séries cochées.
  Future<void> _practice(List<ExamSummary> all, Set<int> selection) async {
    final chosen = [
      for (final s in all)
        if (selection.contains(s.exam.id)) s,
    ];
    final started = await startPractice(context, chosen);
    if (started && mounted) setState(() => _selection = null);
  }

  void _toggle(int id) {
    final sel = _selection;
    if (sel == null) return;
    setState(() {
      final next = {...sel};
      if (!next.remove(id)) next.add(id);
      _selection = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final courses = context.read<CoursesRepository>();
    final all = _repo.exams();
    final subjects = {for (final (s, _, _) in courses.allSubjects()) s.id: s};

    // Les séries de l'onglet (Séries ou Annales), puis le filtre et la
    // recherche.
    final inSection = [
      for (final s in all)
        if (s.exam.isPastPaper == _pastPapers) s,
    ];
    final q = normalize(_search.text.trim());
    bool matches(ExamSummary s) {
      if (q.isEmpty) return true;
      final subject = subjects[s.exam.subjectId]?.name ?? '';
      return normalize(s.exam.title).contains(q) ||
          normalize(subject).contains(q);
    }

    // Matières présentes dans cette section, pour le filtre.
    final subjectCounts = <int, int>{};
    var noSubjectCount = 0;
    var neverCount = 0;
    for (final s in inSection) {
      final id = s.exam.subjectId;
      if (id == null || !subjects.containsKey(id)) {
        noSubjectCount++;
      } else {
        subjectCounts[id] = (subjectCounts[id] ?? 0) + 1;
      }
      if (s.attempts == 0) neverCount++;
    }
    var filter = _filter;
    final stale =
        (filter.kind == _FilterKind.subject &&
            !subjectCounts.containsKey(filter.subjectId)) ||
        (filter.kind == _FilterKind.noSubject && noSubjectCount == 0);
    if (stale) filter = const _Filter.all();

    final visible = [
      for (final s in inSection)
        if (filter.accepts(s) && matches(s)) s,
    ];

    final selection = _selection;
    final selecting = selection != null;

    Widget filterEntry(_Filter f, String label, int count, {Color? color}) {
      final on = filter == f;
      return ListTile(
        key: ValueKey('filter-${f.kind.name}-${f.subjectId ?? ''}'),
        dense: false,
        selected: on,
        leading: color == null ? null : ColorDot(color),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text('$count'),
        onTap: () => setState(() => _filter = f),
      );
    }

    final subjectEntries = [
      for (final e in subjectCounts.entries) (subjects[e.key]!, e.value),
    ]..sort((a, b) => normalize(a.$1.name).compareTo(normalize(b.$1.name)));

    final entries = <Widget>[
      filterEntry(const _Filter.all(), TxQcm.filterAll, inSection.length),
      filterEntry(
        const _Filter(_FilterKind.never),
        TxQcm.filterNever,
        neverCount,
      ),
      for (final (s, n) in subjectEntries)
        filterEntry(
          _Filter(_FilterKind.subject, s.id),
          s.name,
          n,
          color: colorOf(s.color),
        ),
      if (noSubjectCount > 0)
        filterEntry(
          const _Filter(_FilterKind.noSubject),
          TxQcm.noSubject,
          noSubjectCount,
        ),
    ];

    Widget list() {
      if (visible.isEmpty) {
        return EmptyState(
          icon: Icons.quiz_outlined,
          title: inSection.isEmpty
              ? (_pastPapers ? TxQcm.emptyPastPapers : TxQcm.emptyTitle)
              : TxQcm.emptyFilter,
          message: inSection.isEmpty && !_pastPapers ? TxQcm.emptyBody : null,
        );
      }
      return ListView.separated(
        key: const ValueKey('exam-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = visible[i];
          final subject = subjects[s.exam.subjectId];
          final docId = s.exam.documentId;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ExamCard(
                summary: s,
                subjectName: subject?.name,
                subjectColor: subject == null ? null : colorOf(subject.color),
                polyTitle: docId == null
                    ? null
                    : courses.document(docId)?.title,
                selecting: selecting,
                selected: selection?.contains(s.exam.id) ?? false,
                onOpen: () {
                  if (selecting) {
                    _toggle(s.exam.id);
                  } else if (_tab == 1) {
                    _openEditor(s.exam.id);
                  } else if (s.ready > 0) {
                    _compose(s);
                  } else {
                    showInfo(context, TxQcm.nothingToCompose);
                  }
                },
                primaryLabel: _tab == 0 ? TxQcm.compose : null,
                onPrimary: _tab == 0 ? () => _compose(s) : null,
                onAction: (a) => _act(s, a),
              ),
            ),
          );
        },
      );
    }

    final sectionBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            key: const ValueKey('section-exams'),
            label: const Text(TxQcm.subExams),
            selected: !_pastPapers,
            onSelected: (_) => setState(() => _pastPapers = false),
          ),
          ChoiceChip(
            key: const ValueKey('section-past'),
            label: const Text(TxQcm.subPastPapers),
            selected: _pastPapers,
            onSelected: (_) => setState(() => _pastPapers = true),
          ),
        ],
      ),
    );

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        key: const ValueKey('exam-search'),
        controller: _search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: TxQcm.searchExam,
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );

    final Widget body;
    if (all.isEmpty) {
      body = EmptyState(
        icon: Icons.quiz_outlined,
        title: TxQcm.emptyTitle,
        message: TxQcm.emptyBody,
        action: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey('empty-new-series'),
              onPressed: () => _newSeries(null),
              icon: const Icon(Icons.add),
              label: const Text(TxQcm.newSeries),
            ),
            OutlinedButton.icon(
              key: const ValueKey('empty-import'),
              onPressed: _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text(TxQcm.importExam),
            ),
          ],
        ),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 820) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 240,
                  child: ListView(
                    key: const ValueKey('filter-rail'),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: entries,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      sectionBar,
                      searchField,
                      Expanded(child: list()),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionBar,
              searchField,
              SizedBox(
                height: 48,
                child: ListView(
                  key: const ValueKey('filter-chips'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final e in <(_Filter, String)>[
                      (const _Filter.all(), TxQcm.filterAll),
                      (const _Filter(_FilterKind.never), TxQcm.filterNever),
                      for (final (s, _) in subjectEntries)
                        (_Filter(_FilterKind.subject, s.id), s.name),
                      if (noSubjectCount > 0)
                        (const _Filter(_FilterKind.noSubject), TxQcm.noSubject),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey(
                            'chip-${e.$1.kind.name}-${e.$1.subjectId ?? ''}',
                          ),
                          label: Text(e.$2),
                          selected: filter == e.$1,
                          onSelected: (_) => setState(() => _filter = e.$1),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: list()),
            ],
          );
        },
      );
    }

    final currentSubject = filter.kind == _FilterKind.subject
        ? filter.subjectId
        : null;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Sur téléphone, « Ouvrir une épreuve reçue » devient une icône.
              final compact = constraints.maxWidth < 620;
              return PageHeader(
                title: TxQcm.title,
                actions: [
                  if (!selecting) ...[
                    if (compact)
                      IconButton(
                        key: const ValueKey('import-exam'),
                        tooltip: TxQcm.importExam,
                        onPressed: _import,
                        icon: const Icon(Icons.file_open_outlined),
                      )
                    else
                      OutlinedButton.icon(
                        key: const ValueKey('import-exam'),
                        onPressed: _import,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text(TxQcm.importExam),
                      ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const ValueKey('new-series'),
                      onPressed: () => _newSeries(currentSubject),
                      icon: const Icon(Icons.add),
                      label: const Text(TxQcm.newSeries),
                    ),
                  ],
                ],
              );
            },
          ),
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<int>(
                    key: const ValueKey('qcm-tabs'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                    ),
                    segments: const [
                      ButtonSegment(value: 0, label: Text(TxQcm.tabPass)),
                      ButtonSegment(value: 1, label: Text(TxQcm.tabEdit)),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() {
                      _tab = s.first;
                      _selection = null;
                    }),
                  ),
                  if (_tab == 0 && !selecting) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('practice'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => setState(() => _selection = <int>{}),
                      icon: const Icon(Icons.fitness_center_outlined),
                      label: const Text(TxQcm.practice),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('next-exam'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => startNextExam(context),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(TxQcm.nextExam),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: selecting
          ? _SelectionBar(
              count: selection.length,
              allSelected:
                  visible.isNotEmpty &&
                  visible.every((s) => selection.contains(s.exam.id)),
              pastPapers: _pastPapers,
              onToggleAll: () => setState(() {
                final everyone = visible.every(
                  (s) => selection.contains(s.exam.id),
                );
                _selection = everyone
                    ? <int>{}
                    : {for (final s in visible) s.exam.id};
              }),
              onMove: selection.isEmpty
                  ? null
                  : () => chooseSubjectForExams(context, selection.toList()),
              onPastPapers: selection.isEmpty
                  ? null
                  : () => guarded(
                      context,
                      () => _repo.setPastPaper(selection, !_pastPapers),
                    ),
              onDelete: selection.isEmpty
                  ? null
                  : () async {
                      final rows = [
                        for (final s in all)
                          if (selection.contains(s.exam.id)) s.exam,
                      ];
                      final done = await deleteExamsFlow(context, rows);
                      if (done && mounted) setState(() => _selection = null);
                    },
              onDone: () => setState(() => _selection = null),
              onPractice: selection.isEmpty
                  ? null
                  : () => _practice(all, selection),
            )
          : null,
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.pastPapers,
    required this.onToggleAll,
    required this.onMove,
    required this.onPastPapers,
    required this.onDelete,
    required this.onDone,
    required this.onPractice,
  });

  final int count;
  final bool allSelected;
  final bool pastPapers;
  final VoidCallback onToggleAll;
  final VoidCallback? onMove;
  final VoidCallback? onPastPapers;
  final VoidCallback? onDelete;
  final VoidCallback onDone;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                TxQcm.selected(count),
                key: const ValueKey('selection-count'),
                style: theme.textTheme.titleSmall,
              ),
              TextButton(
                key: const ValueKey('selection-all'),
                onPressed: onToggleAll,
                child: Text(allSelected ? TxQcm.selectNone : TxQcm.selectAll),
              ),
              TextButton(
                key: const ValueKey('selection-move'),
                onPressed: onMove,
                child: const Text(TxQcm.move),
              ),
              TextButton(
                key: const ValueKey('selection-past'),
                onPressed: onPastPapers,
                child: Text(
                  pastPapers ? TxQcm.menuFromPastPapers : TxQcm.toPastPapers,
                ),
              ),
              TextButton(
                key: const ValueKey('selection-delete'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: onDelete,
                child: const Text(TxQcm.menuDelete),
              ),
              TextButton(
                key: const ValueKey('selection-done'),
                onPressed: onDone,
                child: const Text(TxQcm.done),
              ),
              FilledButton.icon(
                key: const ValueKey('selection-practice'),
                onPressed: onPractice,
                icon: const Icon(Icons.fitness_center_outlined),
                label: const Text(TxQcm.practice),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
