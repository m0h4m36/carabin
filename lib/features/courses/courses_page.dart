import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../l10n/textes.dart';
import '../../ui/dialogs.dart';
import '../../ui/widgets.dart';
import 'document_viewer_page.dart';
import 'nav.dart';
import 'year_page.dart';

/// Onglet « Cours » : sa propre pile de pages, pour garder la barre de
/// navigation visible pendant qu'on descend dans la hiérarchie.
class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      onPopWithResult: (_) => _navKey.currentState?.maybePop(),
      child: Navigator(
        key: _navKey,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const CoursesHome(),
        ),
      ),
    );
  }
}

/// Ouvre un document en plein écran (au-dessus de la barre de navigation).
void openDocument(BuildContext context, int docId) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => DocumentViewerPage(docId: docId),
    ),
  );
}

class CoursesHome extends StatefulWidget {
  const CoursesHome({super.key});

  @override
  State<CoursesHome> createState() => _CoursesHomeState();
}

class _CoursesHomeState extends State<CoursesHome> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newYear(CoursesRepository courses) async {
    final name = await promptText(
      context,
      title: Tx.newYear,
      label: Tx.yearName,
      confirmLabel: Tx.create,
    );
    if (name == null || !mounted) return;
    final created = await guarded(context, () => courses.createYear(name));
    if (created && mounted) {
      final year = courses.years().last;
      pushNamedPage(
        context,
        'year:${year.id}',
        (_) => YearPage(yearId: year.id),
      );
    }
  }

  Future<void> _sync(CoursesRepository courses) async {
    try {
      final report = courses.syncFolder();
      if (mounted) {
        showInfo(context, Tx.syncReport(report.added, report.missing));
      }
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final courses = context.read<CoursesRepository>();
    final years = courses.years();
    final query = _search.text.trim();

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: Tx.coursesTitle,
            actions: [
              IconButton(
                tooltip: Tx.syncFolder,
                onPressed: () => _sync(courses),
                icon: const Icon(Icons.sync),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _newYear(courses),
                icon: const Icon(Icons.add),
                label: const Text(Tx.newYear),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: Tx.searchDocs,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: Tx.close,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: query.isNotEmpty
                ? _Results(hits: courses.searchDocuments(query))
                : years.isEmpty
                    ? EmptyState(
                        icon: Icons.menu_book_outlined,
                        title: Tx.coursesEmptyTitle,
                        message: Tx.coursesEmptyBody,
                        action: FilledButton.icon(
                          onPressed: () => _newYear(courses),
                          icon: const Icon(Icons.add),
                          label: const Text(Tx.newYear),
                        ),
                      )
                    : _YearsList(years: years, courses: courses),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.hits});
  final List<DocHit> hits;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return const Center(child: Text(Tx.noResults));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: hits.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final hit = hits[i];
        final t = hit.trail;
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(hit.doc.title),
          subtitle: t == null
              ? null
              : Text(
                  '${t.year.name} › ${t.semester.name} › ${t.subject.name} › ${t.topic.name}',
                ),
          onTap: () => openDocument(context, hit.doc.id),
        );
      },
    );
  }
}

class _YearsList extends StatelessWidget {
  const _YearsList({required this.years, required this.courses});
  final List<Year> years;
  final CoursesRepository courses;

  @override
  Widget build(BuildContext context) {
    final recents = courses.recents(limit: 5);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(Tx.recents, style: theme.textTheme.titleMedium),
          ),
          for (final d in recents)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(d.title),
              onTap: () => openDocument(context, d.id),
            ),
          const Divider(),
          const SizedBox(height: 8),
        ],
        for (final y in years)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(y.name, style: theme.textTheme.titleMedium),
            trailing: const Icon(Icons.chevron_right),
            minVerticalPadding: 12,
            onTap: () => pushNamedPage(
              context,
              'year:${y.id}',
              (_) => YearPage(yearId: y.id),
            ),
          ),
      ],
    );
  }
}
