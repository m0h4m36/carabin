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
import 'reading_dots.dart';
import 'subject_page.dart' show kindIcon;

enum _DocAction { open, rename, move, archive, deleteForever }

/// Un thème : ses documents et leur état de lecture.
class TopicPage extends StatelessWidget {
  const TopicPage({super.key, required this.topicId});
  final int topicId;

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final c = context.read<CoursesRepository>();
    final Trail trail;
    try {
      trail = c.trailOfTopic(topicId);
    } on NotFoundError {
      return goneScaffold(context);
    }
    final docs = c.documents(topicId);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: trail.topic.name,
            crumbs: [
              Crumb(Tx.coursesTitle, () => popToRoute(context, '/')),
              Crumb(
                trail.year.name,
                () => popToRoute(context, 'year:${trail.year.id}'),
              ),
              Crumb(
                trail.subject.name,
                () => popToRoute(context, 'subject:${trail.subject.id}'),
              ),
            ],
            actions: [
              FilledButton.icon(
                onPressed: () => importIntoTopic(context, c, topicId),
                icon: const Icon(Icons.upload_file),
                label: const Text(Tx.importFiles),
              ),
            ],
          ),
          Expanded(
            child: docs.isEmpty
                ? EmptyState(
                    icon: Icons.upload_file_outlined,
                    title: Tx.importTopicEmpty,
                    action: FilledButton.icon(
                      onPressed: () => importIntoTopic(context, c, topicId),
                      icon: const Icon(Icons.upload_file),
                      label: const Text(Tx.importFiles),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    buildDefaultDragHandles: false,
                    itemCount: docs.length,
                    onReorderItem: (from, to) {
                      final ids = [for (final d in docs) d.id];
                                      ids.insert(to, ids.removeAt(from));
                      c.reorderDocuments(ids);
                    },
                    itemBuilder: (context, i) => _DocTile(
                      key: ValueKey('doc-${docs[i].id}'),
                      doc: docs[i],
                      index: i,
                      accent: colorOf(trail.subject.color),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    super.key,
    required this.doc,
    required this.index,
    required this.accent,
  });
  final Doc doc;
  final int index;
  final Color accent;

  String _subtitle() {
    final parts = <String>[
      doc.kind.name.toUpperCase(),
      if (doc.pageCount != null) Tx.plural(doc.pageCount!, 'page', 'pages'),
      _size(doc.sizeBytes),
    ];
    return parts.join(' · ');
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }

  Future<void> _action(
    BuildContext context,
    CoursesRepository c,
    _DocAction a,
  ) async {
    switch (a) {
      case _DocAction.open:
        openDocument(context, doc.id);
      case _DocAction.rename:
        final name = await promptText(
          context,
          title: Tx.rename,
          label: Tx.name,
          initial: doc.title,
        );
        if (name == null || !context.mounted) return;
        await guarded(context, () => c.renameDocument(doc.id, name));
      case _DocAction.move:
        final choices = [
          for (final t in c.allTrails())
            if (t.topic.id != doc.topicId)
              Choice<int>(
                t.topic.id,
                t.topic.name,
                subtitle:
                    '${t.year.name} › ${t.semester.name} › ${t.subject.name}',
                color: colorOf(t.subject.color),
              ),
        ];
        final target = await pickFromList<int>(
          context,
          title: Tx.moveDocTitle,
          choices: choices,
        );
        if (target == null || !context.mounted) return;
        await guarded(context, () => c.moveDocument(doc.id, target));
      case _DocAction.archive:
        final ok = await confirm(
          context,
          title: Tx.confirmDeleteTitle(doc.title),
          message: Tx.confirmArchiveDocBody,
          confirmLabel: Tx.archiveDoc,
        );
        if (!ok || !context.mounted) return;
        await guarded(context, () => c.archiveDocument(doc.id));
      case _DocAction.deleteForever:
        final first = await confirm(
          context,
          title: Tx.confirmDeleteTitle(doc.title),
          message: Tx.confirmDeleteForeverBody,
          confirmLabel: Tx.deleteForever,
          destructive: true,
        );
        if (!first || !context.mounted) return;
        final second = await confirm(
          context,
          title: Tx.deleteForever,
          message: Tx.confirmDeleteForeverAgain,
          confirmLabel: Tx.deleteForever,
          destructive: true,
        );
        if (!second || !context.mounted) return;
        await guarded(context, () => c.deleteDocumentPermanently(doc.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<CoursesRepository>();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.only(left: 4, right: 4),
              leading: ReorderableDragStartListener(
                index: index,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(kindIcon(doc.kind), color: accent),
                ),
              ),
              title: Text(doc.title),
              subtitle: Text(_subtitle()),
              onTap: () => openDocument(context, doc.id),
              trailing: PopupMenuButton<_DocAction>(
                tooltip: Tx.more,
                onSelected: (a) => _action(context, c, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _DocAction.open, child: Text(Tx.openDocument)),
                  PopupMenuItem(value: _DocAction.rename, child: Text(Tx.rename)),
                  PopupMenuItem(value: _DocAction.move, child: Text(Tx.moveTo)),
                  PopupMenuItem(value: _DocAction.archive, child: Text(Tx.archiveDoc)),
                  PopupMenuItem(
                    value: _DocAction.deleteForever,
                    child: Text(Tx.deleteForever),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ReadingDots(
                        doc: doc,
                        onToggle: (i, v) => c.setRead(doc.id, i, v),
                      ),
                    ),
                  ),
                  Text(
                    doc.readCount == 0
                        ? Tx.neverReread
                        : Tx.plural(doc.readCount, 'lecture', 'lectures'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
