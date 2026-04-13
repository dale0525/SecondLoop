import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter/material.dart';

import '../core/ai/ai_routing.dart';
import '../core/backend/app_backend.dart';
import '../core/backend/cloud_web_backend.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/cloud_auth_scope.dart';
import '../core/cloud/cloud_usage_client.dart';
import '../core/cloud/vault_attachments_client.dart';
import '../core/cloud/vault_usage_client.dart';
import '../core/session/session_scope.dart';
import '../core/sync/sync_config_store.dart';
import '../features/attachments/web_media_processing_notice.dart';
import 'web_app_gate_helpers.dart';
import 'web_entry_intent.dart';
import 'web_public_entry_scaffold.dart';
import 'web_app_service.dart';
import 'web_chat_page.dart';
import 'web_app_shell.dart';
import '../features/settings/cloud_account_panel.dart';
import '../i18n/strings.g.dart';
import '../features/settings/vault_usage_card.dart';
import 'web_formal_settings_adapters.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/subscription_scope.dart';

export 'web_app_service.dart';

String _shortWebAttachmentSha(String sha256) {
  if (sha256.length <= 12) return sha256;
  return '${sha256.substring(0, 12)}…';
}

String _recentWebAttachmentTitle(
  BuildContext context,
  WebVaultAttachmentItem item,
) {
  if (item.groupType == 'video') {
    return context.t.attachments.workspace.types.video;
  }
  final mimeType = item.mimeType.trim();
  if (mimeType.isNotEmpty) return mimeType;
  return _shortWebAttachmentSha(item.primarySha256);
}

class WebAppGate extends StatefulWidget {
  const WebAppGate({
    required this.authController,
    required this.service,
    this.chatBackend,
    this.entryIntent = WebEntryIntent.open,
    super.key,
  });

  final ObservableCloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend? chatBackend;
  final WebEntryIntent entryIntent;

  @override
  State<WebAppGate> createState() => _WebAppGateState();
}

class _WebAppGateState extends State<WebAppGate> {
  late CloudWebBackend _chatBackend;
  late CloudSubscriptionController _subscriptionController;
  late WebAppBillingClient _billingClient;
  late CloudUsageClient _cloudUsageClient;
  late VaultUsageClient _vaultUsageClient;
  late VaultAttachmentsClient _vaultAttachmentsClient;
  late SyncConfigStore _vaultConfigStore;

  bool _canAccessMainShell = false;
  String? _activeUid;
  String? _mainShellUid;

  String? _normalizedUid() {
    final uid = widget.authController.uid?.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  void _resetSessionScopedState() {
    _chatBackend.clearWebSessionState();
    _subscriptionController.reset();
    _canAccessMainShell = false;
    _mainShellUid = null;
  }

  void _createInjectedDependencies() {
    _chatBackend = widget.chatBackend ??
        CloudWebBackend(chatClient: const UnsupportedCloudWebChatClient());
    _subscriptionController = createWebFormalSubscriptionController(
      service: widget.service,
      authController: widget.authController,
    );
    _subscriptionController.addListener(_onSubscriptionChanged);
    _billingClient = WebAppBillingClient(
      service: widget.service,
      authController: widget.authController,
    );
    _cloudUsageClient = createWebFormalCloudUsageClient(
      service: widget.service,
      authController: widget.authController,
    );
    _vaultUsageClient = createWebFormalVaultUsageClient(
      service: widget.service,
      authController: widget.authController,
    );
    _vaultAttachmentsClient = createWebFormalVaultAttachmentsClient(
      service: widget.service,
      authController: widget.authController,
    );
    _vaultConfigStore = SyncConfigStore(
      managedVaultDefaultBaseUrl: kWebFormalSettingsBaseUrl,
    );
    unawaited(
      _vaultConfigStore.writeManagedVaultBaseUrl(kWebFormalSettingsBaseUrl),
    );
  }

  void _disposeInjectedDependencies() {
    _subscriptionController.removeListener(_onSubscriptionChanged);
    _subscriptionController.dispose();
    _cloudUsageClient.dispose();
    _vaultUsageClient.dispose();
    _vaultAttachmentsClient.dispose();
  }

  @override
  void initState() {
    super.initState();
    _createInjectedDependencies();
    _activeUid = _normalizedUid();
    widget.authController.addListener(_onAuthChanged);
    unawaited(_refreshGateState());
  }

  @override
  void didUpdateWidget(covariant WebAppGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final authChanged = oldWidget.authController != widget.authController;
    final serviceChanged = oldWidget.service != widget.service;
    final chatBackendChanged = oldWidget.chatBackend != widget.chatBackend;
    if (!authChanged && !serviceChanged && !chatBackendChanged) {
      return;
    }

    oldWidget.authController.removeListener(_onAuthChanged);
    _disposeInjectedDependencies();
    _createInjectedDependencies();
    widget.authController.addListener(_onAuthChanged);

    _activeUid = _normalizedUid();
    if (authChanged || chatBackendChanged) {
      _resetSessionScopedState();
    } else {
      _syncMainShellAccess();
    }

    unawaited(_refreshGateState(expectedUid: _activeUid));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    _disposeInjectedDependencies();
    super.dispose();
  }

  void _onAuthChanged() {
    final nextUid = _normalizedUid();
    if (nextUid != _activeUid) {
      _activeUid = nextUid;
      _resetSessionScopedState();
    }
    _syncMainShellAccess();
    if (mounted) {
      setState(() {});
    }
    unawaited(_refreshGateState(expectedUid: nextUid));
  }

  void _onSubscriptionChanged() {
    _syncMainShellAccess();
    if (!mounted) return;
    setState(() {});
  }

  void _syncMainShellAccess() {
    final uid = widget.authController.uid?.trim() ?? '';
    if (uid.isEmpty) {
      _canAccessMainShell = false;
      _mainShellUid = null;
      return;
    }

    switch (_subscriptionController.status) {
      case SubscriptionStatus.entitled:
        _canAccessMainShell = true;
        _mainShellUid = uid;
        return;
      case SubscriptionStatus.notEntitled:
        _canAccessMainShell = false;
        _mainShellUid = null;
        return;
      case SubscriptionStatus.unknown:
        if (_mainShellUid != uid) {
          _canAccessMainShell = false;
        }
        return;
    }
  }

  Future<void> _refreshGateState({String? expectedUid}) async {
    final refreshUid = expectedUid ?? _normalizedUid();
    await _subscriptionController.refresh();
    if (refreshUid != _normalizedUid()) return;
    _syncMainShellAccess();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.authController.uid;
    late final Widget child;
    if (uid == null || uid.trim().isEmpty) {
      child = WebPublicEntryScaffold(
        entryIntent: widget.entryIntent,
        signedIn: false,
        child: CloudAccountPanel(
          billingClient: _billingClient,
          cloudUsageClient: _cloudUsageClient,
          vaultUsageClient: _vaultUsageClient,
          vaultAttachmentsClient: _vaultAttachmentsClient,
          vaultConfigStore: _vaultConfigStore,
          isWebOverride: true,
        ),
      );
    } else if (!_canAccessMainShell || _mainShellUid != uid.trim()) {
      child = WebPublicEntryScaffold(
        entryIntent: widget.entryIntent,
        signedIn: true,
        child: CloudAccountPanel(
          billingClient: _billingClient,
          cloudUsageClient: _cloudUsageClient,
          vaultUsageClient: _vaultUsageClient,
          vaultAttachmentsClient: _vaultAttachmentsClient,
          vaultConfigStore: _vaultConfigStore,
          isWebOverride: true,
        ),
      );
    } else {
      child = _WebMainShell(
        key: ValueKey<String>('web-main-shell-$uid'),
        authController: widget.authController,
        service: widget.service,
        chatBackend: _chatBackend,
        billingClient: _billingClient,
        cloudUsageClient: _cloudUsageClient,
        vaultUsageClient: _vaultUsageClient,
        vaultAttachmentsClient: _vaultAttachmentsClient,
        vaultConfigStore: _vaultConfigStore,
        entryIntent: widget.entryIntent,
      );
    }

    return AppBackendScope(
      backend: _chatBackend,
      child: CloudAuthScope(
        controller: widget.authController,
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: kWebFormalSettingsBaseUrl,
          modelName: 'cloud',
        ),
        child: SubscriptionScope(
          controller: _subscriptionController,
          child: SessionScope(
            sessionKey: Uint8List(0),
            lock: () {},
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WebMainShell extends StatefulWidget {
  const _WebMainShell({
    required this.authController,
    required this.service,
    required this.chatBackend,
    required this.billingClient,
    required this.cloudUsageClient,
    required this.vaultUsageClient,
    required this.vaultAttachmentsClient,
    required this.vaultConfigStore,
    required this.entryIntent,
    super.key,
  });

  final ObservableCloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend chatBackend;
  final WebAppBillingClient billingClient;
  final CloudUsageClient cloudUsageClient;
  final VaultUsageClient vaultUsageClient;
  final VaultAttachmentsClient vaultAttachmentsClient;
  final SyncConfigStore vaultConfigStore;
  final WebEntryIntent entryIntent;

  @override
  State<_WebMainShell> createState() => _WebMainShellState();
}

class _WebMainShellState extends State<_WebMainShell> {
  late int _index;

  int _defaultIndexForIntent() {
    return widget.entryIntent == WebEntryIntent.manage ? 2 : 0;
  }

  @override
  void initState() {
    super.initState();
    _index = _defaultIndexForIntent();
  }

  @override
  void didUpdateWidget(covariant _WebMainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryIntent != widget.entryIntent) {
      _index = _defaultIndexForIntent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      WebChatPage(
        service: widget.service,
        authController: widget.authController,
        chatBackend: widget.chatBackend,
      ),
      _WebFilesPage(
        service: widget.service,
        authController: widget.authController,
        chatBackend: widget.chatBackend,
      ),
      _WebSettingsPage(
        authController: widget.authController,
        service: widget.service,
        chatBackend: widget.chatBackend,
        billingClient: widget.billingClient,
        cloudUsageClient: widget.cloudUsageClient,
        vaultUsageClient: widget.vaultUsageClient,
        vaultAttachmentsClient: widget.vaultAttachmentsClient,
        vaultConfigStore: widget.vaultConfigStore,
      ),
    ];
    return WebAppShell(
      title: context.t.app.web.title,
      selectedIndex: _index,
      destinations: <WebAppShellDestination>[
        WebAppShellDestination(
          label: context.t.app.web.navigation.chat,
          icon: Icons.chat_bubble_outline,
          selectedIcon: Icons.chat_bubble,
        ),
        WebAppShellDestination(
          label: context.t.app.web.navigation.files,
          icon: Icons.folder_outlined,
          selectedIcon: Icons.folder,
        ),
        WebAppShellDestination(
          label: context.t.app.web.navigation.settings,
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
        ),
      ],
      onDestinationSelected: (value) => setState(() => _index = value),
      child: IndexedStack(
        index: _index,
        children: pages,
      ),
    );
  }
}

class _WebFilesPage extends StatefulWidget {
  const _WebFilesPage({
    required this.service,
    required this.authController,
    required this.chatBackend,
  });

  final WebAppService service;
  final CloudAuthController authController;
  final CloudWebBackend chatBackend;

  @override
  State<_WebFilesPage> createState() => _WebFilesPageState();
}

class _WebFilesPageState extends State<_WebFilesPage> {
  String _formatWebVaultError(BuildContext context, Object error) {
    if ('$error'.contains('upload_read_failed')) {
      return context.t.app.web.files.messages.uploadReadFailed;
    }
    if ('$error'.contains('upload_auth_failed')) {
      return context.t.app.web.files.messages.uploadAuthFailed;
    }
    if ('$error'.contains('attachment_too_large_for_web')) {
      return context.t.app.web.files.messages.attachmentTooLarge;
    }
    return formatWebCloudError(context, error);
  }

  final Uint8List _sessionKey = Uint8List(0);
  bool _busy = false;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _uploading = false;
  String? _error;
  String? _deletingAttachmentSha;
  WebVaultUsageSummary? _usage;
  List<WebVaultAttachmentItem> _items = const <WebVaultAttachmentItem>[];

  String? get _vaultId {
    final uid = widget.authController.uid?.trim();
    if (uid == null || uid.isEmpty) return null;
    return uid;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    } else {
      _busy = true;
      _error = null;
    }

    try {
      final idToken = await widget.authController.getIdToken();
      final vaultId = _vaultId;
      if (idToken == null || idToken.isEmpty || vaultId == null) {
        if (!mounted) return;
        final authError = context.t.chat.cloudGateway.errors.auth;
        setState(() => _error = authError);
        return;
      }
      if (!mounted) return;
      final usage = await widget.service.fetchVaultUsage(
        idToken: idToken,
        vaultId: vaultId,
      );
      if (!mounted) return;
      final items = await widget.service.listVaultAttachments(
        idToken: idToken,
        vaultId: vaultId,
      );
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _items = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _formatWebVaultError(context, error));
    } finally {
      _refreshing = false;
      final shouldRefreshAgain = _refreshQueued;
      _refreshQueued = false;
      if (mounted) {
        setState(() => _busy = false);
        if (shouldRefreshAgain) {
          unawaited(_refresh());
        }
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: true,
        readSequential: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      if (!mounted) return;

      final vaultId = _vaultId;
      if (vaultId == null) return;
      if (!mounted) return;

      setState(() => _busy = true);

      var uploadCount = 0;
      var authFailed = false;
      var needsAppProcessing = false;
      for (final file in picked.files) {
        final bytes = await readPlatformFileBytes(file);
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        final freshToken = await widget.authController.getIdToken();
        if (freshToken == null || freshToken.isEmpty) {
          authFailed = true;
          break;
        }
        if (!mounted) return;
        final resolvedMimeType = guessMimeTypeFromExtension(file.extension);
        await widget.service.uploadVaultAttachment(
          idToken: freshToken,
          vaultId: vaultId,
          fileName: file.name,
          mimeType: resolvedMimeType,
          bytes: bytes,
        );
        uploadCount += 1;
        needsAppProcessing = needsAppProcessing ||
            WebVaultAttachmentItem(
              sha256: '',
              mimeType: resolvedMimeType,
              byteLen: bytes.length,
            ).needsAppProcessing;
      }
      if (!mounted) return;
      final failedCount = picked.files.length - uploadCount;
      if (uploadCount == 0 && failedCount > 0) {
        throw StateError(
            authFailed ? 'upload_auth_failed' : 'upload_read_failed');
      }
      if (uploadCount > 0) {
        final message = failedCount > 0
            ? context.t.app.web.files.messages.uploadPartial(
                uploaded: uploadCount,
                skipped: failedCount,
              )
            : (needsAppProcessing
                ? context.t.app.web.files.messages.uploadNeedsApp
                : context.t.app.web.files.messages
                    .uploadSuccess(count: uploadCount));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _formatWebVaultError(context, error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploading = false;
        });
      } else {
        _busy = false;
        _uploading = false;
      }
    }
  }

  Future<void> _openAttachment(WebVaultAttachmentItem item) async {
    if (_busy || _uploading) return;
    setState(() => _busy = true);
    try {
      await openWebVaultAttachmentViewer(
        context: context,
        service: widget.service,
        authController: widget.authController,
        chatBackend: widget.chatBackend,
        sessionKey: _sessionKey,
        item: item,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _formatWebVaultError(context, error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _deleteAttachment(VaultAttachmentUsageItem item) async {
    if (_deletingAttachmentSha != null) return;
    setState(() => _deletingAttachmentSha = item.primarySha256);
    try {
      final idToken = await widget.authController.getIdToken();
      final vaultId = _vaultId;
      if (idToken == null || idToken.isEmpty || vaultId == null) {
        if (!mounted) return;
        final authError = context.t.chat.cloudGateway.errors.auth;
        setState(() => _error = authError);
        return;
      }
      if (!mounted) return;

      await widget.service.deleteVaultAttachment(
        idToken: idToken,
        vaultId: vaultId,
        sha256: item.primarySha256,
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _formatWebVaultError(context, error));
    } finally {
      if (mounted) {
        setState(() => _deletingAttachmentSha = null);
      } else {
        _deletingAttachmentSha = null;
      }
    }
  }

  List<VaultAttachmentUsageItem> get _formalItems {
    return _items
        .map(
          (item) => VaultAttachmentUsageItem(
            sha256: item.sha256,
            rootSha256: item.rootSha256,
            groupType: item.groupType,
            leafCount: item.leafCount,
            mimeType: item.mimeType,
            byteLen: item.byteLen,
            createdAtMs: item.createdAtMs,
            uploadedAtMs: item.uploadedAtMs,
          ),
        )
        .toList(growable: false);
  }

  WebVaultAttachmentItem? _findWebItem(String sha256) {
    for (final item in _items) {
      if (item.primarySha256 == sha256 || item.sha256 == sha256) {
        return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final formalItems = _formalItems;
    final hasItemsNeedingAppProcessing = formalItems.any(
      (item) => item.isGroupedVideo || needsAppProcessingInWeb(item.mimeType),
    );

    return ListView(
      key: const ValueKey('web_files_list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.t.app.web.files.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.t.app.web.files.description,
        ),
        const SizedBox(height: 12),
        if (hasItemsNeedingAppProcessing) ...[
          const WebMediaProcessingNotice(),
          const SizedBox(height: 12),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Row(
          children: [
            FilledButton(
              onPressed: _busy ? null : _refresh,
              child: Text(context.t.app.web.files.actions.refresh),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: (_busy || _uploading) ? null : _pickAndUpload,
              child: Text(context.t.app.web.files.actions.upload),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_usage != null) ...[
          VaultUsageSummaryView(
            summary: VaultUsageSummary(
              totalBytesUsed: _usage!.totalBytesUsed,
              attachmentsBytesUsed: _usage!.totalBytesUsed,
              opsBytesUsed: 0,
              otherBytesUsed: 0,
              limitBytes: _usage!.limitBytes,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          context.t.app.web.files.attachmentsTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_busy && formalItems.isEmpty)
          const Center(child: CircularProgressIndicator())
        else
          VaultAttachmentUsageListView(
            items: formalItems,
            deletingSha: _deletingAttachmentSha,
            isWebOverride: true,
            onOpen: (item) {
              final webItem = _findWebItem(item.primarySha256);
              if (webItem != null) {
                unawaited(_openAttachment(webItem));
              }
            },
            onDelete: _deletingAttachmentSha != null
                ? null
                : (item) => unawaited(_deleteAttachment(item)),
          ),
      ],
    );
  }
}

class _WebSettingsPage extends StatefulWidget {
  const _WebSettingsPage({
    required this.authController,
    required this.service,
    required this.chatBackend,
    required this.billingClient,
    required this.cloudUsageClient,
    required this.vaultUsageClient,
    required this.vaultAttachmentsClient,
    required this.vaultConfigStore,
  });

  final CloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend chatBackend;
  final WebAppBillingClient billingClient;
  final CloudUsageClient cloudUsageClient;
  final VaultUsageClient vaultUsageClient;
  final VaultAttachmentsClient vaultAttachmentsClient;
  final SyncConfigStore vaultConfigStore;

  @override
  State<_WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<_WebSettingsPage> {
  final Uint8List _sessionKey = Uint8List(0);
  bool _loadingRecent = false;
  String? _recentError;
  String? _openingAttachmentSha;
  List<WebVaultAttachmentItem> _recentItems = const <WebVaultAttachmentItem>[];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshRecentItems());
  }

  Future<void> _refreshRecentItems() async {
    if (_loadingRecent) return;
    setState(() {
      _loadingRecent = true;
      _recentError = null;
    });
    try {
      final idToken = await widget.authController.getIdToken();
      final vaultId = webVaultIdForController(widget.authController);
      if (idToken == null || idToken.isEmpty || vaultId == null) return;
      if (!mounted) return;

      final items = List<WebVaultAttachmentItem>.from(
        await widget.service.listVaultAttachments(
          idToken: idToken,
          vaultId: vaultId,
        ),
      );
      items.sort((left, right) {
        final rightTs = right.uploadedAtMs ?? right.createdAtMs ?? 0;
        final leftTs = left.uploadedAtMs ?? left.createdAtMs ?? 0;
        return rightTs.compareTo(leftTs);
      });
      if (!mounted) return;
      setState(() => _recentItems = items.take(5).toList(growable: false));
    } catch (error) {
      if (!mounted) return;
      setState(() => _recentError = formatWebCloudError(context, error));
    } finally {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _openAttachment(WebVaultAttachmentItem item) async {
    if (_openingAttachmentSha != null) return;
    setState(() => _openingAttachmentSha = item.sha256);
    try {
      await openWebVaultAttachmentViewer(
        context: context,
        service: widget.service,
        authController: widget.authController,
        chatBackend: widget.chatBackend,
        sessionKey: _sessionKey,
        item: item,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _recentError = formatWebCloudError(context, error));
    } finally {
      if (mounted) setState(() => _openingAttachmentSha = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('web_settings_list'),
      padding: const EdgeInsets.all(16),
      children: [
        CloudAccountPanel(
          billingClient: widget.billingClient,
          cloudUsageClient: widget.cloudUsageClient,
          vaultUsageClient: widget.vaultUsageClient,
          vaultAttachmentsClient: widget.vaultAttachmentsClient,
          vaultConfigStore: widget.vaultConfigStore,
          isWebOverride: true,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                context.t.app.web.settings.recentFiles.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: _loadingRecent ? null : _refreshRecentItems,
              tooltip: context.t.app.web.settings.recentFiles.refreshTooltip,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.t.app.web.settings.recentFiles.description,
        ),
        const SizedBox(height: 12),
        if (_loadingRecent) const LinearProgressIndicator(),
        if (_recentError != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            _recentError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (!_loadingRecent && _recentItems.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.t.app.web.settings.recentFiles.empty),
          ),
        ..._recentItems.map(
          (item) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_recentWebAttachmentTitle(context, item)),
            subtitle: Text(
              context.t.app.web.settings.recentFiles.itemSummary(
                mimeType: item.mimeType,
                byteCount: item.byteLen,
              ),
            ),
            trailing: _openingAttachmentSha == item.sha256
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new),
            onTap: _openingAttachmentSha != null
                ? null
                : () => _openAttachment(item),
          ),
        ),
      ],
    );
  }
}
