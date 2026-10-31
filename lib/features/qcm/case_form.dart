import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/media_store.dart';
import '../../domain/qcm/exam.dart';
import '../../l10n/textes_qcm.dart';
import '../../ui/dialogs.dart';
import '../../ui/pickers.dart';
import 'article_view.dart';
import 'question_form.dart';
import 'rich_field.dart';

/// Formulaire d'un cas clinique : genre, titre, contexte, article.
///
/// Comme [QuestionForm], il garde sa propre copie et renvoie le cas à chaque
/// modification ; à créer avec une clé propre au cas.
class CaseForm extends StatefulWidget {
  const CaseForm({
    super.key,
    required this.info,
    required this.onChanged,
    required this.defaultTitle,
  });

  final CaseInfo info;
  final ValueChanged<CaseInfo> onChanged;

  /// Nom qu'aura le cas si son titre reste vide.
  final String defaultTitle;

  @override
  State<CaseForm> createState() => _CaseFormState();
}

class _CaseFormState extends State<CaseForm> {
  late CaseInfo _info = widget.info;

  void _set(CaseInfo info) {
    setState(() => _info = info);
    widget.onChanged(info);
  }

  Future<void> _attachPdf() async {
    final media = context.read<MediaStore>();
    try {
      final path = await Pickers.file(const ['pdf']);
      if (path == null) return;
      final name = media.addArticle(path);
      if (!mounted) return;
      _set(_info.copyWith(articleFile: name));
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _openArticle() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ArticlePage(info: _info, title: widget.defaultTitle),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TxQcm.caseGenre, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in CaseGenre.values)
              ChoiceChip(
                key: ValueKey('genre-${g.name}'),
                label: Text(TxQcm.genreName(g)),
                selected: info.genre == g,
                onSelected: (_) => _set(info.copyWith(genre: g)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          TxQcm.genreHelp(info.genre),
          key: const ValueKey('genre-help'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        LineField(
          key: const ValueKey('case-title-field'),
          fieldKey: const ValueKey('case-title'),
          initial: info.title,
          label: TxQcm.caseTitle,
          hint: widget.defaultTitle.isEmpty
              ? TxQcm.caseTitleHint
              : widget.defaultTitle,
          maxLength: 300,
          onChanged: (t) => _set(_info.copyWith(title: t)),
        ),
        const SizedBox(height: 16),
        QcmRichField(
          key: const ValueKey('case-context-field'),
          fieldKey: const ValueKey('case-context'),
          label: TxQcm.caseContext,
          initial: info.context,
          minLines: 5,
          onChanged: (t) => _set(_info.copyWith(context: t)),
        ),
        if (info.genre == CaseGenre.lca) ...[
          const SizedBox(height: 20),
          Text(TxQcm.caseArticle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            TxQcm.caseArticleHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('attach-pdf'),
                onPressed: _attachPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  info.articleFile.isEmpty
                      ? TxQcm.caseAttachPdf
                      : TxQcm.caseChangePdf,
                ),
              ),
              if (info.articleFile.isNotEmpty)
                TextButton.icon(
                  key: const ValueKey('remove-pdf'),
                  onPressed: () => _set(_info.copyWith(articleFile: '')),
                  icon: const Icon(Icons.close),
                  label: const Text(TxQcm.caseRemovePdf),
                ),
              if (info.hasArticle)
                TextButton.icon(
                  key: const ValueKey('open-article'),
                  onPressed: _openArticle,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text(TxQcm.caseOpenArticle),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LineField(
            key: const ValueKey('case-article-text-field'),
            fieldKey: const ValueKey('case-article-text'),
            initial: info.articleText,
            label: TxQcm.caseArticleText,
            multiline: true,
            maxLength: 400000,
            onChanged: (t) => _set(_info.copyWith(articleText: t)),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
