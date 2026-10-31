import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/errors.dart';
import '../../data/models.dart';
import '../../l10n/textes.dart';
import '../../ui/dialogs.dart';
import '../../ui/palette.dart';
import '../../ui/widgets.dart';
import 'nav.dart';
import 'subject_page.dart';

enum _Action { rename, delete }

/// Une année : ses semestres et, dans chacun, ses matières.
class YearPage extends StatelessWidget {
  const YearPage({super.key, required this.yearId});
  final int yearId;

  Future<void> _newSemester(BuildContext context, CoursesRepository c) async {
    final name = await promptText(
      context,
      title: Tx.newSemester,
      label: Tx.semesterName,
      confirmLabel: Tx.create,
    );
    if (name == null || !context.mounted) return;
    await guarded(context, () => c.createSemester(yearId, name));
  }

  Future<void> _yearAction(
    BuildContext context,
    CoursesRepository c,
    Year year,
    _Action a,
  ) async {
    switch (a) {
      case _Action.rename:
        final name = await promptText(
          context,
          title: Tx.rename,
          label: Tx.yearName,
          initial: year.name,
        );
        if (name == null || !context.mounted) return;
        await guarded(context, () => c.rename(CourseLevel.year, year.id, name));
      case _Action.delete:
        final ok = await confirm(
          context,
          title: Tx.confirmDeleteTitle(year.name),
          message: Tx.confirmDeleteLevelBody,
          confirmLabel: Tx.delete,
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        await guarded(context, () => c.delete(CourseLevel.year, year.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final c = context.read<CoursesRepository>();
    final Year year;
    try {
      year = c.year(yearId);
    } on NotFoundError {
      return goneScaffold(context);
    }
    final semesters = c.semesters(yearId);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: year.name,
            crumbs: [Crumb(Tx.coursesTitle, () => popToRoute(context, '/'))],
            actions: [
              PopupMenuButton<_Action>(
                tooltip: Tx.more,
                onSelected: (a) => _yearAction(context, c, year, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Action.rename, child: Text(Tx.rename)),
                  PopupMenuItem(value: _Action.delete, child: Text(Tx.delete)),
                ],
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                if (semesters.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      Tx.noSemesters,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                for (final s in semesters)
                  _SemesterSection(semester: s, year: year),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _newSemester(context, c),
                    icon: const Icon(Icons.add),
                    label: const Text(Tx.newSemester),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SemesterSection extends StatelessWidget {
  const _SemesterSection({required this.semester, required this.year});
  final Semester semester;
  final Year year;

  Future<void> _newSubject(BuildContext context, CoursesRepository c) async {
    final result = await promptSubject(context, title: Tx.newSubject);
    if (result == null || !context.mounted) return;
    await guarded(
      context,
      () => c.createSubject(semester.id, result.name, color: result.color),
    );
  }

  Future<void> _action(
    BuildContext context,
    CoursesRepository c,
    _Action a,
  ) async {
    switch (a) {
      case _Action.rename:
        final name = await promptText(
          context,
          title: Tx.rename,
          label: Tx.semesterName,
          initial: semester.name,
        );
        if (name == null || !context.mounted) return;
        await guarded(
          context,
          () => c.rename(CourseLevel.semester, semester.id, name),
        );
      case _Action.delete:
        final ok = await confirm(
          context,
          title: Tx.confirmDeleteTitle(semester.name),
          message: Tx.confirmDeleteLevelBody,
          confirmLabel: Tx.delete,
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        await guarded(
          context,
          () => c.delete(CourseLevel.semester, semester.id),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<CoursesRepository>();
    final theme = Theme.of(context);
    final subjects = c.subjects(semester.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(semester.name, style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => _newSubject(context, c),
                icon: const Icon(Icons.add),
                label: const Text(Tx.newSubject),
              ),
              PopupMenuButton<_Action>(
                tooltip: Tx.more,
                onSelected: (a) => _action(context, c, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Action.rename, child: Text(Tx.rename)),
                  PopupMenuItem(value: _Action.delete, child: Text(Tx.delete)),
                ],
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),
          if (subjects.isEmpty)
            Text(
              Tx.noSubjects,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final m in subjects)
                  SizedBox(
                    width: 280,
                    child: SubjectCard(
                      subject: m,
                      year: year,
                      semester: semester,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _SubjectAction { rename, color, exam, delete }

class SubjectCard extends StatelessWidget {
  const SubjectCard({
    super.key,
    required this.subject,
    required this.year,
    required this.semester,
  });
  final Subject subject;
  final Year year;
  final Semester semester;

  Future<void> _action(
    BuildContext context,
    CoursesRepository c,
    _SubjectAction a,
  ) async {
    switch (a) {
      case _SubjectAction.rename:
        final r = await promptSubject(
          context,
          title: Tx.rename,
          initialName: subject.name,
          initialColor: subject.color,
          confirmLabel: Tx.save,
        );
        if (r == null || !context.mounted) return;
        await guarded(context, () {
          if (r.name.trim() != subject.name) {
            c.rename(CourseLevel.subject, subject.id, r.name);
          }
          if (r.color != subject.color) c.setSubjectColor(subject.id, r.color);
        });
      case _SubjectAction.color:
        final color = await pickColor(context, initial: subject.color);
        if (color == null || !context.mounted) return;
        await guarded(context, () => c.setSubjectColor(subject.id, color));
      case _SubjectAction.exam:
        final now = DateTime.now();
        final initial = DateTime.tryParse(subject.examDate ?? '') ?? now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 8),
          helpText: Tx.examDate,
        );
        if (picked == null || !context.mounted) return;
        await guarded(
          context,
          () => c.setExamDate(subject.id, isoDateOf(picked)),
        );
      case _SubjectAction.delete:
        final ok = await confirm(
          context,
          title: Tx.confirmDeleteTitle(subject.name),
          message: Tx.confirmDeleteLevelBody,
          confirmLabel: Tx.delete,
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        await guarded(context, () => c.delete(CourseLevel.subject, subject.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<CoursesRepository>();
    final theme = Theme.of(context);
    final (topics, docs) = c.subjectCounts(subject.id);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => pushNamedPage(
          context,
          'subject:${subject.id}',
          (_) => SubjectPage(subjectId: subject.id),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              ColorDot(colorOf(subject.color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Tx.subjectSummary(topics, docs),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (subject.examDate != null)
                      Text(
                        '${Tx.examDate} : ${subject.examDate}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<_SubjectAction>(
                tooltip: Tx.more,
                onSelected: (a) => _action(context, c, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _SubjectAction.rename,
                    child: Text(Tx.rename),
                  ),
                  PopupMenuItem(
                    value: _SubjectAction.color,
                    child: Text(Tx.colorTitle),
                  ),
                  PopupMenuItem(
                    value: _SubjectAction.exam,
                    child: Text(Tx.examDate),
                  ),
                  PopupMenuItem(
                    value: _SubjectAction.delete,
                    child: Text(Tx.delete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date au format AAAA-MM-JJ (celui stocké en base).
String isoDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
