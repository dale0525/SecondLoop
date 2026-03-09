import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/backend/knowledge_index_models.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';

class KnowledgeIndexSettingsCard extends StatefulWidget {
  const KnowledgeIndexSettingsCard({super.key});

  @override
  State<KnowledgeIndexSettingsCard> createState() =>
      _KnowledgeIndexSettingsCardState();
}

class _KnowledgeIndexSettingsCardState
    extends State<KnowledgeIndexSettingsCard> {
  KnowledgeIndexStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _uiError;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_reload(forceLoading: _loading));
  }

  KnowledgeBackend? get _knowledgeBackend {
    final backend = AppBackendScope.maybeOf(context);
    if (backend == null) return null;
    return maybeKnowledgeBackendFor(backend);
  }

  Uint8List? get _sessionKey {
    final scope = SessionScope.maybeOf(context);
    if (scope == null) return null;
    return Uint8List.fromList(scope.sessionKey);
  }

  Future<void> _reload({required bool forceLoading}) async {
    final backend = _knowledgeBackend;
    final key = _sessionKey;
    if (backend == null || key == null) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _loading = false;
        _busy = false;
        _uiError = null;
      });
      return;
    }

    final generation = ++_generation;
    if (forceLoading && mounted) {
      setState(() => _loading = true);
    }

    try {
      final status = await backend.getKnowledgeIndexStatus(key);
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = status;
        _loading = false;
        _uiError = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _uiError = error.toString();
      });
    }
  }

  String _statusLabel(BuildContext context) {
    if (_loading) return context.t.settings.knowledgeIndex.status.loading;
    final status = _status?.status.trim() ?? 'empty';
    final labels = context.t.settings.knowledgeIndex.status;
    return switch (status) {
      'complete' => labels.complete,
      'running' || 'requested' => labels.running,
      'stale' => labels.stale,
      'failed' => labels.failed,
      'cancelled' => labels.cancelled,
      _ => labels.empty,
    };
  }

  String _versionSummary(BuildContext context) {
    final versions = _status?.versions;
    if (versions == null) {
      return context.t.settings.knowledgeIndex.versionSummaryUnavailable;
    }
    return context.t.settings.knowledgeIndex.versionSummary(
      schema: versions.schemaVersion,
      normalization: versions.normalizationVersion,
      segmentation: versions.segmentationVersion,
      embedding: versions.embeddingPolicyVersion,
      retrieval: versions.retrievalPolicyVersion,
    );
  }

  String? _lastBuildLine(BuildContext context) {
    final completedAtMs = _status?.lastRebuildCompletedAtMs;
    if (completedAtMs == null || completedAtMs <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(completedAtMs, isUtc: false)
        .toLocal();
    return context.t.settings.knowledgeIndex.lastBuild(value: dt.toString());
  }

  Future<void> _requestRebuild() async {
    final backend = _knowledgeBackend;
    final key = _sessionKey;
    if (backend == null || key == null || _busy) return;
    setState(() {
      _busy = true;
      _uiError = null;
    });
    try {
      await backend.requestKnowledgeRebuild(key);
      try {
        await backend.processPendingKnowledgeIndexJobs(key, limit: 1);
      } catch (_) {}
      await _reload(forceLoading: false);
    } catch (error) {
      if (mounted) {
        setState(() => _uiError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelRebuild() async {
    final backend = _knowledgeBackend;
    final key = _sessionKey;
    if (backend == null || key == null || _busy) return;
    setState(() {
      _busy = true;
      _uiError = null;
    });
    try {
      await backend.cancelKnowledgeRebuild(key);
      await _reload(forceLoading: false);
    } catch (error) {
      if (mounted) {
        setState(() => _uiError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = _knowledgeBackend;
    final key = _sessionKey;
    if (backend == null || key == null) {
      return const SizedBox.shrink();
    }

    final status = _status;
    final isRunning =
        status?.status == 'running' || status?.status == 'requested';
    final displayError = _uiError ?? status?.lastError;
    final detailLines = <String>[
      _versionSummary(context),
      if (_lastBuildLine(context) case final line?) line,
      if (status?.staleReason case final stale?)
        context.t.settings.knowledgeIndex.staleReason(value: stale),
      if (displayError case final error?)
        context.t.settings.knowledgeIndex.lastError(value: error),
      if (status != null)
        context.t.settings.knowledgeIndex.progress(
          documentsIndexed: status.documentsIndexed,
          totalDocuments: status.totalDocuments,
          unitsIndexed: status.unitsIndexed,
          embeddingsIndexed: status.embeddingsIndexed,
        ),
    ];

    return SlSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t.settings.knowledgeIndex.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(context.t.settings.knowledgeIndex.subtitle),
            const SizedBox(height: 8),
            Text(
              _statusLabel(context),
              key: const ValueKey('knowledge_index_status_label'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final line in detailLines) ...[
              Text(line),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  key: const ValueKey('knowledge_index_rebuild_button'),
                  onPressed: (_busy || isRunning) ? null : _requestRebuild,
                  child:
                      Text(context.t.settings.knowledgeIndex.actions.rebuild),
                ),
                OutlinedButton(
                  key: const ValueKey('knowledge_index_refresh_button'),
                  onPressed: _busy ? null : () => _reload(forceLoading: false),
                  child: Text(context.t.common.actions.refresh),
                ),
                if (isRunning)
                  OutlinedButton(
                    key: const ValueKey('knowledge_index_cancel_button'),
                    onPressed: _busy ? null : _cancelRebuild,
                    child:
                        Text(context.t.settings.knowledgeIndex.actions.cancel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
