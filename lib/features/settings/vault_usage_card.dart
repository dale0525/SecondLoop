import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/vault_usage_client.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

Widget _usageRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class VaultUsageSummaryView extends StatelessWidget {
  const VaultUsageSummaryView({super.key, required this.summary});

  final VaultUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final used = summary.totalBytesUsed;
    final limit = summary.limitBytes;
    final percent = limit == null || limit <= 0
        ? null
        : (used / limit).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usageRow(
          context.t.settings.vaultUsage.labels.used,
          _formatBytes(used),
        ),
        _usageRow(
          context.t.settings.vaultUsage.labels.limit,
          limit == null ? '—' : _formatBytes(limit),
        ),
        if (percent != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: percent),
        ],
        const SizedBox(height: 12),
        _usageRow(
          context.t.settings.vaultUsage.labels.attachments,
          _formatBytes(summary.attachmentsBytesUsed),
        ),
        _usageRow(
          context.t.settings.vaultUsage.labels.ops,
          _formatBytes(summary.opsBytesUsed),
        ),
      ],
    );
  }
}

class VaultUsageCard extends StatefulWidget {
  const VaultUsageCard({super.key, this.client, this.configStore});

  final VaultUsageClient? client;
  final SyncConfigStore? configStore;

  @override
  State<VaultUsageCard> createState() => _VaultUsageCardState();
}

class _VaultUsageCardState extends State<VaultUsageCard> {
  late final VaultUsageClient _client = widget.client ?? VaultUsageClient();
  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();

  bool _busy = false;
  VaultUsageSummary? _summary;
  Object? _error;

  String? _uid;

  @override
  void dispose() {
    if (widget.client == null) _client.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller == null) return;

    final vaultId = controller.uid;
    if (vaultId == null || vaultId.trim().isEmpty) return;

    final baseUrl = await _store.resolveManagedVaultBaseUrl();
    if (baseUrl == null || baseUrl.trim().isEmpty) return;

    String? idToken;
    try {
      idToken = await controller.getIdToken();
    } catch (_) {
      idToken = null;
    }
    if (idToken == null || idToken.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final summary = await _client.fetchVaultUsageSummary(
        managedVaultBaseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = CloudAuthScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final vaultBaseUrl = _store.resolveManagedVaultBaseUrl;
    final uid = scope.controller.uid;

    if (uid != _uid) {
      _uid = uid;
      _summary = null;
      _error = null;
      if (uid != null) {
        unawaited(_refresh());
      }
    }

    final body = FutureBuilder<String?>(
      future: vaultBaseUrl(),
      builder: (context, snapshot) {
        final baseUrl = snapshot.data ?? '';
        return switch ((baseUrl.trim().isEmpty, uid == null)) {
          (true, _) => Text(context.t.settings.vaultUsage.labels.notConfigured),
          (false, true) =>
            Text(context.t.settings.vaultUsage.labels.signInRequired),
          (false, false) when _busy =>
            const Center(child: CircularProgressIndicator()),
          (false, false) when _error != null => Text(
              context.t.settings.vaultUsage.labels.loadFailed(error: '$_error'),
            ),
          (false, false) when _summary != null =>
            VaultUsageSummaryView(summary: _summary!),
          _ => const SizedBox.shrink(),
        };
      },
    );

    return SlSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.settings.vaultUsage.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t.settings.vaultUsage.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('vault_usage_refresh'),
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: context.t.settings.vaultUsage.actions.refresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}
