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
import 'courses_page.dart';
import 'import_flow.dart';
import 'nav.dart';
import 'topic_page.dart';

enum _TopicAction { rename, move, delete }

/// Une matière : ses thèmes, et pour chacun un aperçu de ses polys.
class SubjectPage extends StatelessWidget {
  const SubjectPage({super.key, required this.subjectId});
  final int subjectId;

  Future<void> _newTopic(BuildContext context, CoursesRepository c) async {
    final name = await promptText(
      context,
      title: Tx.newTopic,
      label: Tx.topicName,
      confirmLabel: Tx.create,
    );
    if (name == null || !context.mounted) return;
    await guarded(context, () => c.createTopic(subjectId, name));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final c = context.read<CoursesRepository>();
    final Subject subject;
    final Semester semester;
    final Year year;
    try {
      subject = c.subject(subjectId);
      final all = c.allSubjects().where((e) => e.$1.id == subjectId).first;
      semester = all.$2;
      year = all.$3;
    } on NotFoundError {
      return goneScaffold(context);
    } on StateError {
      return goneScaffold(context);
    }
    final topics = c.topics(subjectId);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: subject.name,
            crumbs: [
              Crumb(Tx.coursesTitle, () => popToRoute(context, '/')),
              Crumb(year.name, () => popToRoute(context, 'year:${year.id}')),
              Crumb(semester.name),
            ],
            actions: [
              FilledButton.tonalIcon(
                onPressed: () => _newTopic(context, c),
                icon: const Icon(Icons.add),
                label: const Text(Tx.newTopic),
              ),
            ],
          ),
          Expanded(
            child: topics.isEmpty
                ? EmptyState(
                    icon: Icons.folder_open_outlined,
                    title: Tx.noTopics,
                    action: FilledButton.icon(
                      onPressed: () => _newTopic(context, c),
                      icon: const Icon(Icons.add),
                      label: const Text(Tx.newTopic),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    buildDefaultDragHandles: false,
                    itemCount: topics.length,
                    onReorderItem: (from, to) {
                      final ids = [for (final t in topics) t.id];
                      ids.insert(to, ids.removeAt(from));
                      c.reorder(CourseLevel.topic, ids);
                    },
                    itemBuilder: (context, i) => Padding(
                      key: ValueKey('topic-${topics[i].id}'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TopicCard(
                        topic: topics[i],
                        index: i,
                        subject: subject,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.index,
    required this.subject,
  });
  final Topic topic;
  final int index;
  final Subject subject;

  Future<void> _action(
    BuildContext context,
    CoursesRepository c,
    _TopicAction a,
  ) async {
    switch (a) {
      case _TopicAction.rename:
        final name = await promptText(
          context,
          title: Tx.rename,
          label: Tx.topicName,
          initial: topic.name,
        );
        if (name == null || !context.mounted) return;
        await guarded(
          context,
          () => c.rename(CourseLevel.topic, topic.id, name),
        );
      case _TopicAction.move:
        final choices = [
          for (final (m, s, y) in c.allSubjects())
            if (m.id != topic.subjectId)
              Choice<int>(
                m.id,
                m.name,
                subtitle: '${y.name} › ${s.name}',
                color: colorOf(m.color),
              ),
        ];
        final target = await pickFromList<int>(
          context,
          title: Tx.moveTopicTitle,
          choices: choices,
        );
        if (target == null || !context.mounted) return;
        await guarded(context, () => c.moveTopic(topic.id, target));
      case _TopicAction.delete:
        final ok = await confirm(
          context,
          title: Tx.confirmDeleteTitle(topic.name),
          message: Tx.confirmDeleteLevelBody,
          confirmLabel: Tx.delete,
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        await guarded(context, () => c.delete(CourseLevel.topic, topic.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<CoursesRepository>();
    final theme = Theme.of(context);
    final docs = c.documents(topic.id);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => pushNamedPage(
              context,
              'topic:${topic.id}',
              (_) => TopicPage(topicId: topic.id),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  Expanded(
                    child: Text(topic.name, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    Tx.plural(docs.length, 'document', 'documents'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: Tx.importFiles,
                    onPressed: () => importIntoTopic(context, c, topic.id),
                    icon: const Icon(Icons.upload_file),
                  ),
                  PopupMenuButton<_TopicAction>(
                    tooltip: Tx.more,
                    onSelected: (a) => _action(context, c, a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _TopicAction.rename,
                        child: Text(Tx.rename),
                      ),
                      PopupMenuItem(
                        value: _TopicAction.move,
                        child: Text(Tx.moveTo),
                      ),
                      PopupMenuItem(
                        value: _TopicAction.delete,
                        child: Text(Tx.delete),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (docs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                Tx.importTopicEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final d in docs) ...[
              const Divider(),
              ListTile(
                dense: true,
                leading: Icon(kindIcon(d.kind)),
                title: Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${d.readCount}/${Doc.maxReads}'),
                onTap: () => openDocument(context, d.id),
              ),
            ],
        ],
      ),
    );
  }
}

IconData kindIcon(DocKind k) => switch (k) {
  DocKind.pdf => Icons.picture_as_pdf_outlined,
  DocKind.word => Icons.description_outlined,
  DocKind.image => Icons.image_outlined,
  DocKind.text => Icons.notes,
  DocKind.other => Icons.insert_drive_file_outlined,
};
