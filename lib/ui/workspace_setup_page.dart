import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/workspace.dart';
import '../l10n/textes.dart';

/// Premier lancement : choix du dossier de travail.
class WorkspaceSetupPage extends StatefulWidget {
  const WorkspaceSetupPage({
    super.key,
    required this.documentsDir,
    required this.onChosen,
    this.message,
  });

  /// Dossier « Documents » de l'utilisateur (emplacement par défaut).
  final String documentsDir;

  /// Appelé avec le dossier choisi ; doit lever une exception si l'ouverture
  /// échoue.
  final Future<void> Function(String root) onChosen;

  /// Message d'accueil particulier (par exemple : dossier non retrouvé).
  final String? message;

  @override
  State<WorkspaceSetupPage> createState() => _WorkspaceSetupPageState();
}

class _WorkspaceSetupPageState extends State<WorkspaceSetupPage> {
  bool _busy = false;
  String? _error;

  bool get _canPickFolder => !(Platform.isAndroid || Platform.isIOS);

  /// Dossier par défaut : « Documents/Carabin », ou « Carabin (2) »… si ce
  /// nom est déjà pris par un dossier qui n'est pas un dossier Carabin.
  String _defaultTarget() {
    final base = Workspace.defaultRoot(widget.documentsDir);
    var candidate = base;
    var n = 2;
    while (Directory(candidate).existsSync() &&
        !Workspace.looksLikeWorkspace(candidate) &&
        !Workspace.isEmptyOrMissing(candidate)) {
      candidate = '$base ($n)';
      n++;
    }
    return candidate;
  }

  Future<void> _open(String root) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onChosen(root);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = Tx.setupFailed;
        });
      }
    }
  }

  Future<void> _pickExisting() async {
    final chosen = await FilePicker.getDirectoryPath();
    if (chosen == null) return;
    if (!Workspace.looksLikeWorkspace(chosen) &&
        !Workspace.isEmptyOrMissing(chosen)) {
      setState(() => _error = Tx.setupNotWorkspace);
      return;
    }
    await _open(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _defaultTarget();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Tx.appName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  Text(Tx.setupTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (widget.message != null) ...[
                    Text(
                      widget.message!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(Tx.setupIntro, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Text(
                    '${Tx.setupWillCreate}\n${p.normalize(target)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_busy)
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text(Tx.setupBusy),
                      ],
                    )
                  else ...[
                    FilledButton(
                      onPressed: () => _open(target),
                      child: const Text(Tx.setupCreateDefault),
                    ),
                    if (_canPickFolder) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _pickExisting,
                        child: const Text(Tx.setupOpenExisting),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
