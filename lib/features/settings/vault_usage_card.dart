import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/cloud/cloud_auth_access.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/vault_attachments_client.dart';
import '../../core/cloud/vault_usage_client.dart';
import '../../core/sync/sync_config_store.dart';
import '../../features/attachments/attachment_storage_controller.dart';
import '../../features/attachments/web_media_processing_notice.dart';
import '../../i18n/strings.g.dart';
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

String _attachmentUsageTitle(
  BuildContext context,
  VaultAttachmentUsageItem item,
) {
  final displayName = item.displayName?.trim() ?? '';
  if (displayName.isNotEmpty) return displayName;
  if (item.isGroupedVideo) {
    return context.t.attachments.workspace.types.video;
  }
  return item.mimeType.isEmpty ? item.primarySha256 : item.mimeType;
}

String _attachmentUsageSubtitle(
  BuildContext context,
  VaultAttachmentUsageItem item,
) {
  final linkedEntities = item.linkedEntities
      .map((entity) {
        final title = entity.title?.trim() ?? '';
        if (title.isNotEmpty) return title;
        return '${entity.kind}:${entity.id}';
      })
      .where((label) => label.trim().isNotEmpty)
      .join(', ');
  final parts = <String>[
    if (item.mimeType.isNotEmpty) item.mimeType,
    _formatBytes(item.byteLen),
    if (item.isGroupedVideo && (item.leafCount ?? 0) > 0) '${item.leafCount}×',
    _shortSha(item.primarySha256),
    _formatTimestamp(context, item.uploadedAtMs ?? item.createdAtMs),
    if (linkedEntities.isNotEmpty) linkedEntities,
    if ((item.processingStatus ?? '').trim().isNotEmpty)
      item.processingStatus!.trim(),
  ];
  return parts.join(' • ');
}

String _formatVaultUsageError(BuildContext context, Object error) {
  final status = parseHttpStatusFromError(error);
  final code = parseCloudErrorCodeFromError(error);
  if (status == 402 || code == 'payment_required') {
    return context.t.sync.cloudManagedVault.paymentRequired;
  }
  if (status == 400 && code == 'invalid_batch') {
    return context.t.sync.cloudManagedVault.localSyncDataRepairRequired;
  }
  if (status == 403 && code == 'email_not_verified') {
    return context.t.chat.cloudGateway.emailNotVerified;
  }
  if (status == 403 && code == 'storage_quota_exceeded') {
    return context.t.sync.cloudManagedVault.storageQuotaExceeded;
  }
  if (status == 429) {
    return context.t.chat.cloudGateway.errors.rateLimited;
  }
  if (status != null && status >= 500) {
    return context.t.sync.cloudManagedVault.serverUnavailable;
  }
  return '$error';
}

String _attachmentUsageTileKey(VaultAttachmentUsageItem item) {
  return 'vault_usage_attachment_${item.primarySha256}';
}

String _attachmentActionId(VaultAttachmentUsageItem item) {
  return item.attachmentId;
}

IconData _attachmentUsageIcon(VaultAttachmentUsageItem item) {
  if (item.isGroupedVideo) return Icons.video_file_rounded;
  return Icons.attach_file_rounded;
}

enum VaultAttachmentUsageSort { sizeDesc, uploadedDesc }

int _compareAttachmentUsage(
  VaultAttachmentUsageItem a,
  VaultAttachmentUsageItem b,
  VaultAttachmentUsageSort sort,
) {
  if (sort == VaultAttachmentUsageSort.sizeDesc) {
    final byBytes = b.byteLen - a.byteLen;
    if (byBytes != 0) return byBytes;
  }
  final aUploadedAt = a.uploadedAtMs ?? a.createdAtMs ?? 0;
  final bUploadedAt = b.uploadedAtMs ?? b.createdAtMs ?? 0;
  final byUploaded = bUploadedAt - aUploadedAt;
  if (byUploaded != 0) return byUploaded;
  return a.sha256.compareTo(b.sha256);
}

String _attachmentTypeKey(VaultAttachmentUsageItem item) {
  final mime = item.mimeType.trim().toLowerCase();
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/') || item.isGroupedVideo) return 'video';
  if (mime.startsWith('audio/')) return 'audio';
  if (mime == 'application/pdf') return 'pdf';
  return 'other';
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
    this.isWebOverride,
    this.typeFilter,
    this.sort = VaultAttachmentUsageSort.sizeDesc,
    this.onTypeFilterChanged,
    this.onSortChanged,
    required this.onOpen,
    required this.onDelete,
    this.onPreview,
    this.onClearLocalCache,
  });

  final List<VaultAttachmentUsageItem> items;
  final String? deletingSha;
  final bool? isWebOverride;
  final String? typeFilter;
  final VaultAttachmentUsageSort sort;
  final ValueChanged<String?>? onTypeFilterChanged;
  final ValueChanged<VaultAttachmentUsageSort>? onSortChanged;
  final ValueChanged<VaultAttachmentUsageItem> onOpen;
  final ValueChanged<VaultAttachmentUsageItem>? onDelete;
  final ValueChanged<VaultAttachmentUsageItem>? onPreview;
  final ValueChanged<VaultAttachmentUsageItem>? onClearLocalCache;

  @override
  Widget build(BuildContext context) {
    final filtered = items
        .where(
          (item) =>
              typeFilter == null || _attachmentTypeKey(item) == typeFilter,
        )
        .toList();
    final sorted = List<VaultAttachmentUsageItem>.from(filtered)
      ..sort((a, b) => _compareAttachmentUsage(a, b, sort));

    if (sorted.isEmpty) {
      return Text(context.t.settings.vaultUsage.labels.noAttachments);
    }

    return Column(
      children: [
        if (onTypeFilterChanged != null || onSortChanged != null) ...[
          Row(
            children: [
              if (onTypeFilterChanged != null)
                DropdownButton<String?>(
                  key: const ValueKey('vault_usage_type_filter'),
                  value: typeFilter,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child:
                          Text(context.t.settings.vaultUsage.labels.allTypes),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'image',
                      child: Text(context.t.settings.vaultUsage.labels.images),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'video',
                      child: Text(context.t.settings.vaultUsage.labels.videos),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'audio',
                      child: Text(context.t.settings.vaultUsage.labels.audio),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'pdf',
                      child: Text(context.t.settings.vaultUsage.labels.pdf),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'other',
                      child: Text(context.t.settings.vaultUsage.labels.other),
                    ),
                  ],
                  onChanged: onTypeFilterChanged,
                ),
              const SizedBox(width: 12),
              if (onSortChanged != null)
                DropdownButton<VaultAttachmentUsageSort>(
                  key: const ValueKey('vault_usage_sort_filter'),
                  value: sort,
                  items: [
                    DropdownMenuItem(
                      value: VaultAttachmentUsageSort.sizeDesc,
                      child:
                          Text(context.t.settings.vaultUsage.labels.sortBySize),
                    ),
                    DropdownMenuItem(
                      value: VaultAttachmentUsageSort.uploadedDesc,
                      child: Text(
                        context.t.settings.vaultUsage.labels.sortByUploadTime,
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSortChanged!(value);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        for (final item in sorted)
          ListTile(
            key: ValueKey(_attachmentUsageTileKey(item)),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(_attachmentUsageIcon(item)),
            title: Text(
              _attachmentUsageTitle(context, item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _attachmentUsageSubtitle(context, item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(item),
            trailing: () {
              final showWebOnlyHint = isWebOverride ?? kIsWeb;
              final needsAppProcessing = showWebOnlyHint &&
                  (item.isGroupedVideo ||
                      needsAppProcessingInWeb(item.mimeType));
              final actionId = _attachmentActionId(item);
              final deleteAction = deletingSha == actionId
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: ValueKey(
                        'vault_usage_attachment_delete_$actionId',
                      ),
                      tooltip: context.t.common.actions.delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: deletingSha != null ||
                              onDelete == null ||
                              !item.canDelete
                          ? null
                          : () => onDelete!(item),
                    );
              final actions = <Widget>[
                IconButton(
                  key: ValueKey('vault_usage_attachment_preview_$actionId'),
                  tooltip: context.t.settings.vaultUsage.actions.preview,
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: onPreview == null ? null : () => onPreview!(item),
                ),
                IconButton(
                  key: ValueKey('vault_usage_attachment_clear_cache_$actionId'),
                  tooltip:
                      context.t.settings.vaultUsage.actions.clearLocalCache,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  onPressed: onClearLocalCache == null
                      ? null
                      : () => onClearLocalCache!(item),
                ),
                deleteAction,
              ];
              if (!needsAppProcessing) {
                return Row(mainAxisSize: MainAxisSize.min, children: actions);
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      context.t.app.web.common.actions.continueInApp,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  ...actions,
                ],
              );
            }(),
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
    this.isWebOverride,
  });

  final VaultUsageClient? client;
  final VaultAttachmentsClient? attachmentsClient;
  final SyncConfigStore? configStore;
  final bool? isWebOverride;

  @override
  State<VaultUsageCard> createState() => _VaultUsageCardState();
}

class _VaultUsageCardState extends State<VaultUsageCard> {
  late VaultUsageClient _usageClient;
  late VaultAttachmentsClient _attachmentsClient;
  late SyncConfigStore _store;
  var _ownsUsageClient = false;
  var _ownsAttachmentsClient = false;
  final Set<int> _activeRefreshTokens = <int>{};
  int _refreshEpoch = 0;

  bool get _busy => _activeRefreshTokens.isNotEmpty;
  String? _resolvedVaultBaseUrl;
  String? _pendingResolvedVaultBaseUrl;
  VaultUsageSummary? _summary;
  Object? _summaryError;

  VaultAttachmentUsageList? _attachmentUsage;
  Object? _attachmentError;

  String? _uid;
  String? _deletingAttachmentSha;
  String? _attachmentTypeFilter;
  var _attachmentSort = VaultAttachmentUsageSort.sizeDesc;
  final AttachmentLocalCacheMetadataStore _localCacheMetadataStore =
      InMemoryAttachmentLocalCacheMetadataStore();

  @override
  void initState() {
    super.initState();
    _replaceDependencies(
      client: widget.client,
      attachmentsClient: widget.attachmentsClient,
      configStore: widget.configStore,
    );
  }

  @override
  void didUpdateWidget(covariant VaultUsageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.attachmentsClient != widget.attachmentsClient ||
        oldWidget.configStore != widget.configStore) {
      _disposeOwnedClients();
      _replaceDependencies(
        client: widget.client,
        attachmentsClient: widget.attachmentsClient,
        configStore: widget.configStore,
      );
      _resetLoadedState(resetBaseUrl: true, invalidateRefreshes: true);
      if (_uid != null) {
        unawaited(_refresh());
      }
    }
  }

  void _replaceDependencies({
    required VaultUsageClient? client,
    required VaultAttachmentsClient? attachmentsClient,
    required SyncConfigStore? configStore,
  }) {
    _usageClient = client ?? VaultUsageClient();
    _attachmentsClient = attachmentsClient ?? VaultAttachmentsClient();
    _store = configStore ?? SyncConfigStore();
    _ownsUsageClient = client == null;
    _ownsAttachmentsClient = attachmentsClient == null;
  }

  void _disposeOwnedClients() {
    if (_ownsUsageClient) {
      _usageClient.dispose();
    }
    if (_ownsAttachmentsClient) {
      _attachmentsClient.dispose();
    }
  }

  void _resetLoadedState({
    bool resetBaseUrl = false,
    bool invalidateRefreshes = false,
  }) {
    if (invalidateRefreshes) {
      _refreshEpoch += 1;
      _activeRefreshTokens.clear();
    }
    _summary = null;
    _summaryError = null;
    _attachmentUsage = null;
    _attachmentError = null;
    if (resetBaseUrl) {
      _resolvedVaultBaseUrl = null;
    }
  }

  void _markRefreshStarted(int refreshEpoch) {
    if (_activeRefreshTokens.contains(refreshEpoch)) return;
    if (!mounted) {
      _activeRefreshTokens.add(refreshEpoch);
      return;
    }
    setState(() => _activeRefreshTokens.add(refreshEpoch));
  }

  void _markRefreshFinished(int refreshEpoch) {
    if (!_activeRefreshTokens.contains(refreshEpoch)) return;
    if (!mounted) {
      _activeRefreshTokens.remove(refreshEpoch);
      return;
    }
    setState(() => _activeRefreshTokens.remove(refreshEpoch));
  }

  @override
  void dispose() {
    _disposeOwnedClients();
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
      idToken = await readCloudAuthIdToken(
        controller,
        mode: CloudAuthAccessMode.interactive,
      );
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

  void _scheduleVaultBaseUrlSync(String baseUrl, {required String? uid}) {
    final normalizedBaseUrl = baseUrl.trim();
    if (_resolvedVaultBaseUrl == normalizedBaseUrl ||
        _pendingResolvedVaultBaseUrl == normalizedBaseUrl) {
      return;
    }
    _pendingResolvedVaultBaseUrl = normalizedBaseUrl;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingResolvedVaultBaseUrl == normalizedBaseUrl) {
        _pendingResolvedVaultBaseUrl = null;
      }
      if (!mounted || _resolvedVaultBaseUrl == normalizedBaseUrl) return;
      setState(() {
        _resolvedVaultBaseUrl = normalizedBaseUrl;
        _resetLoadedState(invalidateRefreshes: true);
      });
      if (uid != null &&
          uid.trim().isNotEmpty &&
          normalizedBaseUrl.isNotEmpty) {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _refresh() async {
    final auth = await _resolveManagedVaultAuth();
    if (auth == null) return;
    final refreshEpoch = ++_refreshEpoch;
    _markRefreshStarted(refreshEpoch);

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
        ..sort(
          (a, b) => _compareAttachmentUsage(a, b, _attachmentSort),
        );
      nextAttachmentUsage = VaultAttachmentUsageList(
        items: sortedItems,
        totalCount: usage.totalCount,
        totalBytesUsed: usage.totalBytesUsed,
      );
    } catch (e) {
      nextAttachmentError = e;
    }

    final shouldApply = mounted && refreshEpoch == _refreshEpoch;
    if (shouldApply) {
      setState(() {
        _summary = nextSummary;
        _summaryError = nextSummaryError;
        _attachmentUsage = nextAttachmentUsage;
        _attachmentError = nextAttachmentError;
      });
    }

    _markRefreshFinished(refreshEpoch);
  }

  AttachmentStorageController _createAttachmentStorageController(
    _ManagedVaultAuth auth,
  ) {
    return AttachmentStorageController(
      client: _attachmentsClient,
      localCacheMetadataStore: _localCacheMetadataStore,
      managedVaultBaseUrl: auth.baseUrl,
      vaultId: auth.vaultId,
      idToken: auth.idToken,
    );
  }

  Future<void> _previewAttachment(VaultAttachmentUsageItem item) async {
    final auth = await _resolveManagedVaultAuth();
    if (auth == null || !mounted) return;

    try {
      final controller = _createAttachmentStorageController(auth);
      final descriptor = await controller.previewAttachment(item);
      final launched = await launchUrl(
        Uri.parse(descriptor.url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(context.t.settings.vaultUsage.labels.previewOpenFailed),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatVaultUsageError(context, e)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearLocalAttachmentCache(VaultAttachmentUsageItem item) async {
    final auth = await _resolveManagedVaultAuth();
    if (auth == null || !mounted) return;

    try {
      final controller = _createAttachmentStorageController(auth);
      await controller.clearLocalCache(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.settings.vaultUsage.labels.localCacheDeleted),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatVaultUsageError(context, e)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteAttachment(VaultAttachmentUsageItem item) async {
    if (_deletingAttachmentSha != null) return;

    final currentContext = context;
    final actionId = _attachmentActionId(item);
    final itemTitle = _attachmentUsageTitle(currentContext, item);
    final deleteTitle = currentContext.t.common.actions.delete;
    final vaultUsageLabels = currentContext.t.settings.vaultUsage.labels;
    final auth = await _resolveManagedVaultAuth();
    if (auth == null || !mounted) return;

    VaultAttachmentDeleteImpact impact;
    try {
      impact = await _attachmentsClient.fetchDeleteImpact(
        managedVaultBaseUrl: auth.baseUrl,
        vaultId: auth.vaultId,
        idToken: auth.idToken,
        attachmentId: item.attachmentId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatVaultUsageError(context, e)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final linkedEntities = impact.linkedEntities
        .map((entity) => entity.title ?? '${entity.kind}:${entity.id}')
        .join(', ');
    final itemDetails = <String>[
      itemTitle,
      _formatBytes(item.byteLen),
      item.attachmentId,
      if (linkedEntities.isNotEmpty)
        vaultUsageLabels.linkedEntities(
          value: linkedEntities,
        ),
    ].join('\n');
    if (!currentContext.mounted) return;
    final confirmed = await showSlDeleteConfirmDialog(
      currentContext,
      title: deleteTitle,
      message: itemDetails,
      confirmButtonKey:
          ValueKey('vault_usage_attachment_delete_confirm_$actionId'),
    );
    if (!confirmed) return;

    setState(() => _deletingAttachmentSha = actionId);
    try {
      await _attachmentsClient.deleteVaultAttachment(
        managedVaultBaseUrl: auth.baseUrl,
        vaultId: auth.vaultId,
        idToken: auth.idToken,
        attachmentId: item.attachmentId,
      );

      await _refresh();
      if (!mounted) return;

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
          content: Text(
            context.t.chat.deleteFailed(
              error: _formatVaultUsageError(context, e),
            ),
          ),
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

    final uid = scope.controller.uid;

    if (uid != _uid) {
      _uid = uid;
      _resetLoadedState(invalidateRefreshes: true);
      if (uid != null && (_resolvedVaultBaseUrl?.trim().isNotEmpty ?? false)) {
        unawaited(_refresh());
      }
    }

    final body = FutureBuilder<String?>(
      future: _store.resolveManagedVaultBaseUrl(),
      initialData: _resolvedVaultBaseUrl,
      builder: (context, snapshot) {
        final baseUrl = (snapshot.data ?? _resolvedVaultBaseUrl ?? '').trim();
        _scheduleVaultBaseUrlSync(baseUrl, uid: uid);

        if (snapshot.connectionState != ConnectionState.done &&
            _resolvedVaultBaseUrl == null) {
          return const SizedBox.shrink();
        }
        if (baseUrl.isEmpty) {
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
                context.t.settings.vaultUsage.labels.loadFailed(
                  error: _formatVaultUsageError(context, _summaryError!),
                ),
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
                context.t.settings.vaultUsage.labels.loadFailed(
                  error: _formatVaultUsageError(context, _attachmentError!),
                ),
              )
            else if (_attachmentUsage != null)
              VaultAttachmentUsageListView(
                items: _attachmentUsage!.items,
                deletingSha: _deletingAttachmentSha,
                isWebOverride: widget.isWebOverride,
                typeFilter: _attachmentTypeFilter,
                sort: _attachmentSort,
                onTypeFilterChanged: (value) {
                  setState(() => _attachmentTypeFilter = value);
                },
                onSortChanged: (value) {
                  setState(() => _attachmentSort = value);
                },
                onOpen: (item) => unawaited(_previewAttachment(item)),
                onPreview: (item) => unawaited(_previewAttachment(item)),
                onClearLocalCache: (item) =>
                    unawaited(_clearLocalAttachmentCache(item)),
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
                onPressed: _busy
                    ? null
                    : () async {
                        final baseUrl =
                            (await _store.resolveManagedVaultBaseUrl())
                                    ?.trim() ??
                                '';
                        if (!mounted) return;
                        setState(() => _resolvedVaultBaseUrl = baseUrl);
                        await _refresh();
                      },
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
