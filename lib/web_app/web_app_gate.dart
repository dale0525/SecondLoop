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
import '../src/rust/db.dart';
import '../core/session/session_scope.dart';
import '../core/sync/sync_config_store.dart';
import '../features/attachments/attachment_viewer_page.dart';
import '../features/attachments/web_media_processing_notice.dart';
import 'web_app_service.dart';
import 'web_chat_page.dart';
import '../features/settings/cloud_account_panel.dart';
import '../i18n/strings.g.dart';
import '../features/settings/vault_usage_card.dart';
import 'web_formal_settings_adapters.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/subscription_scope.dart';

export 'web_app_service.dart';

class WebAppGate extends StatefulWidget {
  const WebAppGate({
    required this.authController,
    required this.service,
    this.chatBackend,
    super.key,
  });

  final CloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend? chatBackend;

  @override
  State<WebAppGate> createState() => _WebAppGateState();
}

class _WebAppGateState extends State<WebAppGate> {
  late CloudWebBackend _chatBackend;
  late Listenable _authListenable;
  late final CloudSubscriptionController _subscriptionController =
      createWebFormalSubscriptionController(
    service: widget.service,
    authController: widget.authController,
  );
  late final WebAppBillingClient _billingClient = WebAppBillingClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final CloudUsageClient _cloudUsageClient =
      createWebFormalCloudUsageClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final VaultUsageClient _vaultUsageClient =
      createWebFormalVaultUsageClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final VaultAttachmentsClient _vaultAttachmentsClient =
      createWebFormalVaultAttachmentsClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final SyncConfigStore _vaultConfigStore = SyncConfigStore(
    managedVaultDefaultBaseUrl: kWebFormalSettingsBaseUrl,
  );

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

  @override
  void initState() {
    super.initState();
    _authListenable = _requireObservableAuthController(widget.authController);
    _chatBackend = widget.chatBackend ??
        CloudWebBackend(chatClient: const UnsupportedCloudWebChatClient());
    _activeUid = _normalizedUid();
    unawaited(
        _vaultConfigStore.writeManagedVaultBaseUrl(kWebFormalSettingsBaseUrl));
    _authListenable.addListener(_onAuthChanged);
    _subscriptionController.addListener(_onSubscriptionChanged);
    unawaited(_refreshGateState());
  }

  @override
  void dispose() {
    _authListenable.removeListener(_onAuthChanged);
    _subscriptionController.removeListener(_onSubscriptionChanged);
    _subscriptionController.dispose();
    _cloudUsageClient.dispose();
    _vaultUsageClient.dispose();
    _vaultAttachmentsClient.dispose();
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
      child = _WebPublicEntryScaffold(
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
      child = _WebPublicEntryScaffold(
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

Listenable _requireObservableAuthController(CloudAuthController controller) {
  if (controller is Listenable) return controller as Listenable;
  throw StateError('WebAppGate requires a Listenable CloudAuthController');
}

class _WebPublicEntryScaffold extends StatelessWidget {
  const _WebPublicEntryScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.app.web.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [child],
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
    super.key,
  });

  final CloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend chatBackend;

  @override
  State<_WebMainShell> createState() => _WebMainShellState();
}

class _WebMainShellState extends State<_WebMainShell> {
  int _index = 0;

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
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t.app.web.title)),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            label: context.t.app.web.navigation.chat,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            label: context.t.app.web.navigation.files,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: context.t.app.web.navigation.settings,
          ),
        ],
      ),
    );
  }
}

String? _webVaultIdForController(CloudAuthController controller) {
  final uid = controller.uid?.trim();
  if (uid == null || uid.isEmpty) return null;
  return uid;
}

Attachment _webAttachmentFromVaultItem(WebVaultAttachmentItem item) {
  return Attachment(
    sha256: item.primarySha256,
    mimeType: item.mimeType,
    path: 'vault/${item.primarySha256}.bin',
    byteLen: PlatformInt64Util.from(item.byteLen),
    createdAtMs: PlatformInt64Util.from(item.createdAtMs ?? 0),
  );
}

String _formatWebCloudError(BuildContext context, Object error) {
  final status = parseHttpStatusFromError(error);
  final code = parseCloudErrorCodeFromError(error);
  if (status == 402 || code == 'payment_required') {
    return context.t.sync.cloudManagedVault.paymentRequired;
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

Future<Uint8List?> _readPlatformFileBytes(PlatformFile file) async {
  final directBytes = file.bytes;
  if (directBytes != null) {
    return Uint8List.fromList(directBytes);
  }

  final readStream = file.readStream;
  if (readStream == null) return null;

  final builder = BytesBuilder(copy: false);
  await for (final chunk in readStream) {
    if (chunk.isNotEmpty) {
      builder.add(chunk);
    }
  }
  return builder.takeBytes();
}

Future<void> _openWebVaultAttachmentViewer({
  required BuildContext context,
  required WebAppService service,
  required CloudAuthController authController,
  required CloudWebBackend chatBackend,
  required Uint8List sessionKey,
  required WebVaultAttachmentItem item,
}) async {
  final idToken = await authController.getIdToken();
  final vaultId = _webVaultIdForController(authController);
  if (idToken == null || idToken.isEmpty || vaultId == null) return;

  final bytes = await service.fetchVaultAttachmentBytes(
    idToken: idToken,
    vaultId: vaultId,
    sha256: item.primarySha256,
  );
  final attachment = _webAttachmentFromVaultItem(item);
  chatBackend.rememberAttachment(
    attachment,
    bytes: Uint8List.fromList(bytes),
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => SessionScope(
        sessionKey: sessionKey,
        lock: () {},
        child: AppBackendScope(
          backend: chatBackend,
          child: AttachmentViewerPage(
            attachment: attachment,
            isWebOverride: true,
          ),
        ),
      ),
    ),
  );
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
    return _formatWebCloudError(context, error);
  }

  final Uint8List _sessionKey = Uint8List(0);
  bool _busy = false;
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
    final idToken = await widget.authController.getIdToken();
    final vaultId = _vaultId;
    if (idToken == null || idToken.isEmpty || vaultId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final usage = await widget.service.fetchVaultUsage(
        idToken: idToken,
        vaultId: vaultId,
      );
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final idToken = await widget.authController.getIdToken();
    final vaultId = _vaultId;
    if (idToken == null || idToken.isEmpty || vaultId == null) return;

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: true,
      readSequential: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      var uploadCount = 0;
      var needsAppProcessing = false;
      for (final file in picked.files) {
        final bytes = await _readPlatformFileBytes(file);
        if (bytes == null || bytes.isEmpty) continue;
        final resolvedMimeType = guessMimeTypeFromExtension(file.extension);
        await widget.service.uploadVaultAttachment(
          idToken: idToken,
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
      if (uploadCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              needsAppProcessing
                  ? context.t.app.web.files.messages.uploadNeedsApp
                  : context.t.app.web.files.messages
                      .uploadSuccess(count: uploadCount),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _formatWebVaultError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttachment(WebVaultAttachmentItem item) async {
    setState(() => _busy = true);
    try {
      await _openWebVaultAttachmentViewer(
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAttachment(VaultAttachmentUsageItem item) async {
    final idToken = await widget.authController.getIdToken();
    final vaultId = _vaultId;
    if (idToken == null || idToken.isEmpty || vaultId == null) return;

    setState(() => _deletingAttachmentSha = item.primarySha256);
    try {
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
      if (mounted) setState(() => _deletingAttachmentSha = null);
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                onPressed: _busy ? null : _pickAndUpload,
                child: Text(context.t.app.web.files.actions.upload),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
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
                    onDelete: (item) => unawaited(_deleteAttachment(item)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSettingsPage extends StatefulWidget {
  const _WebSettingsPage({
    required this.authController,
    required this.service,
    required this.chatBackend,
  });

  final CloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend chatBackend;

  @override
  State<_WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<_WebSettingsPage> {
  final Uint8List _sessionKey = Uint8List(0);
  late final CloudUsageClient _cloudUsageClient =
      createWebFormalCloudUsageClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final VaultUsageClient _vaultUsageClient =
      createWebFormalVaultUsageClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final VaultAttachmentsClient _vaultAttachmentsClient =
      createWebFormalVaultAttachmentsClient(
    service: widget.service,
    authController: widget.authController,
  );
  late final SyncConfigStore _vaultConfigStore = SyncConfigStore(
    managedVaultDefaultBaseUrl: kWebFormalSettingsBaseUrl,
  );
  bool _loadingRecent = false;
  String? _recentError;
  String? _openingAttachmentSha;
  List<WebVaultAttachmentItem> _recentItems = const <WebVaultAttachmentItem>[];

  @override
  void initState() {
    super.initState();
    unawaited(
        _vaultConfigStore.writeManagedVaultBaseUrl(kWebFormalSettingsBaseUrl));
    unawaited(_refreshRecentItems());
  }

  @override
  void dispose() {
    _cloudUsageClient.dispose();
    _vaultUsageClient.dispose();
    _vaultAttachmentsClient.dispose();
    super.dispose();
  }

  Future<void> _refreshRecentItems() async {
    final idToken = await widget.authController.getIdToken();
    final vaultId = _webVaultIdForController(widget.authController);
    if (idToken == null || idToken.isEmpty || vaultId == null) return;

    setState(() {
      _loadingRecent = true;
      _recentError = null;
    });
    try {
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
      setState(() => _recentError = _formatWebCloudError(context, error));
    } finally {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _openAttachment(WebVaultAttachmentItem item) async {
    setState(() => _openingAttachmentSha = item.sha256);
    try {
      await _openWebVaultAttachmentViewer(
        context: context,
        service: widget.service,
        authController: widget.authController,
        chatBackend: widget.chatBackend,
        sessionKey: _sessionKey,
        item: item,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _recentError = _formatWebCloudError(context, error));
    } finally {
      if (mounted) setState(() => _openingAttachmentSha = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CloudAccountPanel(
          billingClient: WebAppBillingClient(
            service: widget.service,
            authController: widget.authController,
          ),
          cloudUsageClient: _cloudUsageClient,
          vaultUsageClient: _vaultUsageClient,
          vaultAttachmentsClient: _vaultAttachmentsClient,
          vaultConfigStore: _vaultConfigStore,
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
            title: Text(item.sha256),
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
            onTap: _openingAttachmentSha == item.sha256
                ? null
                : () => _openAttachment(item),
          ),
        ),
      ],
    );
  }
}
