import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/vault_attachments_client.dart';
import '../../core/cloud/vault_usage_client.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../features/attachments/attachment_viewer_page.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_delete_confirm_dialog.dart';
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

String _shortSha(String sha256) {
  if (sha256.length <= 12) return sha256;
  return '${sha256.substring(0, 12)}…';
}

String _formatTimestamp(BuildContext context, int? ms) {
  if (ms == null || ms <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatShortDate(dt);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dt));
  return '$date $time';
}

String _attachmentUsageSubtitle(
  BuildContext context,
  VaultAttachmentUsageItem item,
) {
  final parts = <String>[
    _formatBytes(item.byteLen),
    _shortSha(item.sha256),
    _formatTimestamp(context, item.uploadedAtMs ?? item.createdAtMs),
  ];
  return parts.join(' • ');
}

int _compareAttachmentUsage(
  VaultAttachmentUsageItem a,
  VaultAttachmentUsageItem b,
) {
  final byBytes = b.byteLen - a.byteLen;
  if (byBytes != 0) return byBytes;
  final byCreated = (b.createdAtMs ?? 0) - (a.createdAtMs ?? 0);
  if (byCreated != 0) return byCreated;
  return a.sha256.compareTo(b.sha256);
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

class VaultAttachmentUsageListView extends StatelessWidget {
  const VaultAttachmentUsageListView({
    super.key,
    required this.items,
    required this.deletingSha,
    required this.onOpen,
    required this.onDelete,
  });

  final List<VaultAttachmentUsageItem> items;
  final String? deletingSha;
  final ValueChanged<VaultAttachmentUsageItem> onOpen;
  final ValueChanged<VaultAttachmentUsageItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final sorted = List<VaultAttachmentUsageItem>.from(items)
      ..sort(_compareAttachmentUsage);

    if (sorted.isEmpty) {
      return Text(context.t.actions.todoDetail.noAttachments);
    }

    return Column(
      children: [
        for (final item in sorted)
          ListTile(
            key: ValueKey('vault_usage_attachment_${item.sha256}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.attach_file_rounded),
            title: Text(
              item.mimeType.isEmpty ? item.sha256 : item.mimeType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _attachmentUsageSubtitle(context, item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(item),
            trailing: deletingSha == item.sha256
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    key: ValueKey(
                      'vault_usage_attachment_delete_${item.sha256}',
                    ),
                    tooltip: context.t.common.actions.delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => onDelete(item),
                  ),
          ),
      ],
    );
  }
}

class VaultUsageCard extends StatefulWidget {
  const VaultUsageCard({
    super.key,
    this.client,
    this.attachmentsClient,
    this.configStore,
  });

  final VaultUsageClient? client;
  final VaultAttachmentsClient? attachmentsClient;
  final SyncConfigStore? configStore;

  @override
  State<VaultUsageCard> createState() => _VaultUsageCardState();
}

class _VaultUsageCardState extends State<VaultUsageCard> {
  late final VaultUsageClient _usageClient =
      widget.client ?? VaultUsageClient();
  late final VaultAttachmentsClient _attachmentsClient =
      widget.attachmentsClient ?? VaultAttachmentsClient();
  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();

  bool _busy = false;
  VaultUsageSummary? _summary;
  Object? _summaryError;

  VaultAttachmentUsageList? _attachmentUsage;
  Object? _attachmentError;

  String? _uid;
  String? _deletingAttachmentSha;

  bool _buildingAttachmentReferenceIndex = false;
  Map<String, Attachment> _localAttachmentBySha = <String, Attachment>{};
  Map<String, String> _localMessageIdByAttachmentSha = <String, String>{};

  @override
  void dispose() {
    if (widget.client == null) _usageClient.dispose();
    if (widget.attachmentsClient == null) _attachmentsClient.dispose();
    super.dispose();
  }

  Future<_ManagedVaultAuth?> _resolveManagedVaultAuth() async {
    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller == null) return null;

    final vaultId = controller.uid?.trim() ?? '';
    if (vaultId.isEmpty) return null;

    final baseUrl = (await _store.resolveManagedVaultBaseUrl())?.trim() ?? '';
    if (baseUrl.isEmpty) return null;

    String? idToken;
    try {
      idToken = await controller.getIdToken();
    } catch (_) {
      idToken = null;
    }

    final token = idToken?.trim() ?? '';
    if (token.isEmpty) return null;

    return _ManagedVaultAuth(
      vaultId: vaultId,
      baseUrl: baseUrl,
      idToken: token,
    );
  }

  Future<void> _rebuildAttachmentReferenceIndex() async {
    if (_buildingAttachmentReferenceIndex) return;

    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;

    _buildingAttachmentReferenceIndex = true;
    try {
      final nextAttachmentBySha = <String, Attachment>{};
      final nextMessageIdByAttachmentSha = <String, String>{};
      final conversations = await backend.listConversations(sessionKey);

      for (final conversation in conversations) {
        final messages =
            await backend.listMessages(sessionKey, conversation.id);
        for (final message in messages) {
          List<Attachment> attachments;
          try {
            attachments = await attachmentsBackend.listMessageAttachments(
              sessionKey,
              message.id,
            );
          } catch (_) {
            continue;
          }
          for (final attachment in attachments) {
            nextAttachmentBySha.putIfAbsent(
              attachment.sha256,
              () => attachment,
            );
            nextMessageIdByAttachmentSha.putIfAbsent(
              attachment.sha256,
              () => message.id,
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _localAttachmentBySha = nextAttachmentBySha;
        _localMessageIdByAttachmentSha = nextMessageIdByAttachmentSha;
      });
    } catch (_) {
      // Best-effort only.
    } finally {
      _buildingAttachmentReferenceIndex = false;
    }
  }

  Future<Attachment?> _resolveLocalAttachmentBySha(String sha256) async {
    final cached = _localAttachmentBySha[sha256];
    if (cached != null) return cached;
    await _rebuildAttachmentReferenceIndex();
    return _localAttachmentBySha[sha256];
  }

  Future<String?> _resolveMessageIdByAttachmentSha(String sha256) async {
    final cached = _localMessageIdByAttachmentSha[sha256];
    if (cached != null) return cached;
    await _rebuildAttachmentReferenceIndex();
    return _localMessageIdByAttachmentSha[sha256];
  }

  Future<void> _refresh() async {
    if (_busy) return;

    final auth = await _resolveManagedVaultAuth();
    if (auth == null) return;

    setState(() => _busy = true);

    VaultUsageSummary? nextSummary;
    Object? nextSummaryError;
    VaultAttachmentUsageList? nextAttachmentUsage;
    Object? nextAttachmentError;

    try {
      nextSummary = await _usageClient.fetchVaultUsageSummary(
        managedVaultBaseUrl: auth.baseUrl,
        vaultId: auth.vaultId,
        idToken: auth.idToken,
      );
    } catch (e) {
      nextSummaryError = e;
    }

    try {
      final usage = await _attachmentsClient.fetchVaultAttachmentUsageList(
        managedVaultBaseUrl: auth.baseUrl,
        vaultId: auth.vaultId,
        idToken: auth.idToken,
      );
      final sortedItems = List<VaultAttachmentUsageItem>.from(usage.items)
        ..sort(_compareAttachmentUsage);
      nextAttachmentUsage = VaultAttachmentUsageList(
        items: sortedItems,
        totalCount: usage.totalCount,
        totalBytesUsed: usage.totalBytesUsed,
      );
    } catch (e) {
      nextAttachmentError = e;
    }

    if (!mounted) return;
    setState(() {
      _summary = nextSummary;
      _summaryError = nextSummaryError;
      _attachmentUsage = nextAttachmentUsage;
      _attachmentError = nextAttachmentError;
      _busy = false;
    });

    if (nextAttachmentUsage != null && nextAttachmentUsage.items.isNotEmpty) {
      unawaited(_rebuildAttachmentReferenceIndex());
    }
  }

  Future<void> _openAttachmentDetails(VaultAttachmentUsageItem item) async {
    final attachment = await _resolveLocalAttachmentBySha(item.sha256);
    if (!mounted) return;

    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.errors.loadFailed(error: 'attachment_not_found_locally'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AttachmentViewerPage(attachment: attachment),
      ),
    );
  }

  Future<void> _deleteAttachment(VaultAttachmentUsageItem item) async {
    if (_deletingAttachmentSha != null) return;

    final itemTitle = item.mimeType.isEmpty ? item.sha256 : item.mimeType;
    final itemDetails = <String>[
      itemTitle,
      _formatBytes(item.byteLen),
      item.sha256,
    ].join('\n');
    final confirmed = await showSlDeleteConfirmDialog(
      context,
      title: context.t.common.actions.delete,
      message: itemDetails,
      confirmButtonKey:
          ValueKey('vault_usage_attachment_delete_confirm_${item.sha256}'),
    );
    if (!confirmed) return;

    final auth = await _resolveManagedVaultAuth();
    if (auth == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    setState(() => _deletingAttachmentSha = item.sha256);
    try {
      final messageId = await _resolveMessageIdByAttachmentSha(item.sha256);
      if (messageId != null) {
        await backend.purgeMessageAttachments(sessionKey, messageId);
        if (!mounted) return;
        SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      }

      await _attachmentsClient.deleteVaultAttachment(
        managedVaultBaseUrl: auth.baseUrl,
        vaultId: auth.vaultId,
        idToken: auth.idToken,
        attachmentSha256: item.sha256,
      );

      _localAttachmentBySha.remove(item.sha256);
      _localMessageIdByAttachmentSha.remove(item.sha256);

      await _refresh();
      if (!mounted) return;
      unawaited(_rebuildAttachmentReferenceIndex());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.messageDeleted),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.deleteFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingAttachmentSha = null);
      }
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
      _summaryError = null;
      _attachmentUsage = null;
      _attachmentError = null;
      _localAttachmentBySha = <String, Attachment>{};
      _localMessageIdByAttachmentSha = <String, String>{};
      if (uid != null) {
        unawaited(_refresh());
      }
    }

    final body = FutureBuilder<String?>(
      future: vaultBaseUrl(),
      builder: (context, snapshot) {
        final baseUrl = snapshot.data ?? '';
        if (baseUrl.trim().isEmpty) {
          return Text(context.t.settings.vaultUsage.labels.notConfigured);
        }
        if (uid == null) {
          return Text(context.t.settings.vaultUsage.labels.signInRequired);
        }

        if (_busy &&
            _summary == null &&
            _attachmentUsage == null &&
            _summaryError == null &&
            _attachmentError == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_summaryError != null)
              Text(
                context.t.settings.vaultUsage.labels
                    .loadFailed(error: '$_summaryError'),
              )
            else if (_summary != null)
              VaultUsageSummaryView(summary: _summary!),
            const SizedBox(height: 16),
            Text(
              context.t.settings.vaultUsage.labels.attachments,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (_attachmentError != null)
              Text(
                context.t.settings.vaultUsage.labels
                    .loadFailed(error: '$_attachmentError'),
              )
            else if (_attachmentUsage != null)
              VaultAttachmentUsageListView(
                items: _attachmentUsage!.items,
                deletingSha: _deletingAttachmentSha,
                onOpen: (item) => unawaited(_openAttachmentDetails(item)),
                onDelete: (item) => unawaited(_deleteAttachment(item)),
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
        );
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

@immutable
final class _ManagedVaultAuth {
  const _ManagedVaultAuth({
    required this.vaultId,
    required this.baseUrl,
    required this.idToken,
  });

  final String vaultId;
  final String baseUrl;
  final String idToken;
}
