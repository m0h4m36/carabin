import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../data/workspace.dart';
import '../../l10n/textes.dart';
import '../../ui/dialogs.dart';
import 'reading_dots.dart';

/// Lecture d'un document en plein écran (PDF, image ou texte).
class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({super.key, required this.docId});
  final int docId;

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  final PdfViewerController _pdf = PdfViewerController();
  int _page = 1;
  int? _pages;

  /// Contenu d'un fichier texte, lu une seule fois (sinon chaque
  /// redessinage de l'écran relirait le fichier).
  String? _text;
  String? _textPath;

  static const _maxTextBytes = 2 * 1024 * 1024;

  /// Lit un petit fichier texte ; null si illisible ou trop gros.
  String? _readText(File file) {
    if (_textPath == file.path) return _text;
    _textPath = file.path;
    try {
      if (file.lengthSync() > _maxTextBytes) return _text = null;
      return _text = file.readAsStringSync();
    } on Object {
      return _text = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CoursesRepository>().markOpened(widget.docId);
    });
  }

  Future<void> _askPage() async {
    final text = await promptText(
      context,
      title: Tx.page,
      label: Tx.page,
      initial: '$_page',
    );
    final n = int.tryParse(text?.trim() ?? '');
    if (n == null || !_pdf.isReady) return;
    final max = _pdf.pages.length;
    await _pdf.goToPage(pageNumber: n.clamp(1, max));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppDatabase>();
    final courses = context.read<CoursesRepository>();
    final ws = context.read<Workspace>();
    final doc = courses.document(widget.docId);
    if (doc == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    final file = File(ws.absolute(doc.relPath));
    final isPdf = doc.kind == DocKind.pdf;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (isPdf && file.existsSync()) ...[
            IconButton(
              tooltip: Tx.zoomOut,
              onPressed: _pdf.isReady ? _pdf.zoomDown : null,
              icon: const Icon(Icons.zoom_out),
            ),
            TextButton(
              onPressed: _askPage,
              child: Text('$_page / ${_pages ?? doc.pageCount ?? '–'}'),
            ),
            IconButton(
              tooltip: Tx.zoomIn,
              onPressed: _pdf.isReady ? _pdf.zoomUp : null,
              icon: const Icon(Icons.zoom_in),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body(context, doc, file)),
          const Divider(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    Tx.readThrough,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ReadingDots(
                        doc: doc,
                        onToggle: (i, v) => courses.setRead(doc.id, i, v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Doc doc, File file) {
    if (!file.existsSync()) return const _Message(Tx.fileMissing);
    switch (doc.kind) {
      case DocKind.pdf:
        return PdfViewer.file(
          file.path,
          controller: _pdf,
          params: PdfViewerParams(
            errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                const _Message(Tx.pdfError),
            onViewerReady: (document, controller) {
              if (!mounted) return;
              final n = document.pages.length;
              setState(() => _pages = n);
              if (doc.pageCount != n) {
                context.read<CoursesRepository>().setPageCount(doc.id, n);
              }
            },
            onPageChanged: (n) {
              if (n != null && mounted) setState(() => _page = n);
            },
          ),
        );
      case DocKind.image:
        return InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image.file(
              file,
              errorBuilder: (_, _, _) => const _Message(Tx.previewUnavailable),
            ),
          ),
        );
      case DocKind.text:
        final text = _readText(file);
        if (text == null) return const _Message(Tx.previewUnavailable);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(text),
        );
      case DocKind.word:
      case DocKind.other:
        return const _Message(Tx.previewUnavailable);
    }
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
