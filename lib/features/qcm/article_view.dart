import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../data/media_store.dart';
import '../../domain/qcm/exam.dart';
import '../../l10n/textes.dart';
import '../../l10n/textes_qcm.dart';

/// Article d'un cas de lecture critique : PDF joint et/ou texte collé.
class ArticleView extends StatelessWidget {
  const ArticleView({super.key, required this.info});

  final CaseInfo info;

  @override
  Widget build(BuildContext context) {
    final media = context.read<MediaStore>();
    final hasFile = info.articleFile.isNotEmpty;
    final hasText = info.articleText.trim().isNotEmpty;
    if (!hasFile && !hasText) {
      return const Center(child: Text(TxQcm.articleNone));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasFile)
          Expanded(
            flex: 3,
            child: media.exists(info.articleFile)
                ? PdfViewer.file(
                    media.file(info.articleFile).path,
                    params: PdfViewerParams(
                      errorBannerBuilder: (
                        context,
                        error,
                        stackTrace,
                        documentRef,
                      ) => const Center(child: Text(Tx.pdfError)),
                    ),
                  )
                : const Center(child: Text(TxQcm.articleFileMissing)),
          ),
        if (hasFile && hasText) const Divider(height: 1),
        if (hasText)
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(info.articleText),
            ),
          ),
      ],
    );
  }
}

/// L'article en plein écran.
class ArticlePage extends StatelessWidget {
  const ArticlePage({super.key, required this.info, required this.title});

  final CaseInfo info;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
    body: ArticleView(info: info),
  );
}
