import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';
import 'package:secondloop/features/settings/cloud_usage_card.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/web_app/web_entry_intent.dart';
import 'package:secondloop/web_app/web_app_gate.dart';

import '../test_i18n.dart';

class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _FakeCloudAuthController({
    this.initialUid,
    this.initialEmail,
    this.initialEmailVerified,
    this.sendVerificationError,
    List<String?>? idTokenSequence,
  })  : _idTokenSequence = idTokenSequence == null
            ? <String?>[]
            : List<String?>.from(idTokenSequence),
        _uid = initialUid,
        _email = initialEmail,
        _emailVerified = initialEmailVerified;

  final String? initialUid;
  final String? initialEmail;
  final bool? initialEmailVerified;
  final Object? sendVerificationError;

  final List<String?> _idTokenSequence;
  Completer<String?>? _deferredIdToken;
  String? _uid;
  String? _email;
  bool? _emailVerified;

  void setSession({
    required String? uid,
    String? email,
    bool? emailVerified,
  }) {
    _uid = uid;
    _email = email;
    _emailVerified = emailVerified;
    notifyListeners();
  }

  void setIdTokenSequence(List<String?> values) {
    _idTokenSequence
      ..clear()
      ..addAll(values);
  }

  void deferNextIdToken() {
    _deferredIdToken = Completer<String?>();
  }

  void completeDeferredIdToken(String? value) {
    _deferredIdToken?.complete(value);
    _deferredIdToken = null;
  }

  @override
  String? get uid => _uid;

  @override
  String? get email => _email;

  @override
  bool? get emailVerified => _emailVerified;

  @override
  Future<String?> getIdToken() async {
    if (_uid == null) return null;
    final deferredIdToken = _deferredIdToken;
    if (deferredIdToken != null) return deferredIdToken.future;
    if (_idTokenSequence.isNotEmpty) {
      return _idTokenSequence.removeAt(0);
    }
    return 'token';
  }

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {
    if (sendVerificationError != null) throw sendVerificationError!;
  }

  @override
  Future<void> signInWithEmailPassword(
      {required String email, required String password}) async {
    _uid = 'uid-1';
    _email = email;
    _emailVerified = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _email = null;
    _emailVerified = null;
    notifyListeners();
  }

  @override
  Future<void> signUpWithEmailPassword(
      {required String email, required String password}) async {
    _uid = 'uid-2';
    _email = email;
    _emailVerified = false;
    notifyListeners();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}
}

class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({
    required this.subscription,
    this.items = const <WebVaultAttachmentItem>[],
    this.bytesBySha = const <String, List<int>>{},
    this.usage,
    this.usageError,
    this.vaultUsage,
    this.vaultUsageError,
    this.listError,
    this.bytesError,
    this.portalError,
    this.checkoutError,
    this.deleteError,
  });

  WebSubscriptionState subscription;
  bool failNextSubscriptionFetch = false;
  Object? failNextSubscriptionError;
  final List<WebVaultAttachmentItem> items;
  final Map<String, List<int>> bytesBySha;
  final WebUsageSummary? usage;
  final Object? usageError;
  final WebVaultUsageSummary? vaultUsage;
  final Object? vaultUsageError;
  final Object? listError;
  final Object? bytesError;
  final Object? portalError;
  final Object? checkoutError;
  final Object? deleteError;
  final List<_FakeUploadedFile> uploads = <_FakeUploadedFile>[];
  final List<Future<List<WebVaultAttachmentItem>>> queuedListResponses =
      <Future<List<WebVaultAttachmentItem>>>[];
  int deleteCallCount = 0;
  Completer<void>? _heldDelete;

  void queueListResponse(Future<List<WebVaultAttachmentItem>> response) {
    queuedListResponses.add(response);
  }

  void holdNextDelete() {
    _heldDelete = Completer<void>();
  }

  void releaseHeldDelete() {
    _heldDelete?.complete();
    _heldDelete = null;
  }

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
      {required String idToken}) async {
    if (failNextSubscriptionFetch) {
      failNextSubscriptionFetch = false;
      throw failNextSubscriptionError ??
          StateError('forced_subscription_error');
    }
    return WebSubscriptionSnapshot(
      state: subscription,
      canManageSubscription: subscription == WebSubscriptionState.entitled,
    );
  }

  @override
  Future<WebUsageSummary?> fetchUsage({required String idToken}) async {
    if (usageError != null) throw usageError!;
    return usage;
  }

  @override
  Future<WebVaultUsageSummary?> fetchVaultUsage({
    required String idToken,
    required String vaultId,
  }) async {
    if (vaultUsageError != null) throw vaultUsageError!;
    return vaultUsage;
  }

  @override
  Future<List<WebVaultAttachmentItem>> listVaultAttachments({
    required String idToken,
    required String vaultId,
  }) async {
    if (listError != null) throw listError!;
    if (queuedListResponses.isNotEmpty) {
      return await queuedListResponses.removeAt(0);
    }
    return items;
  }

  @override
  Future<List<int>> fetchVaultAttachmentBytes({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async {
    if (bytesError != null) throw bytesError!;
    return bytesBySha[sha256] ?? const <int>[];
  }

  @override
  Future<void> openCheckout({required String idToken}) async {
    if (checkoutError != null) throw checkoutError!;
  }

  @override
  Future<void> openPortal({required String idToken}) async {
    if (portalError != null) throw portalError!;
  }

  @override
  Future<void> deleteVaultAttachment({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async {
    deleteCallCount += 1;
    if (deleteError != null) throw deleteError!;
    final heldDelete = _heldDelete;
    if (heldDelete != null) {
      await heldDelete.future;
      _heldDelete = null;
    }
    items.removeWhere(
        (item) => item.primarySha256 == sha256 || item.sha256 == sha256);
  }

  @override
  Future<void> uploadVaultAttachment({
    required String idToken,
    required String vaultId,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    uploads.add(
      _FakeUploadedFile(
        idToken: idToken,
        vaultId: vaultId,
        fileName: fileName,
        mimeType: mimeType,
        bytes: bytes,
      ),
    );
  }
}

final class _FakeUploadedFile {
  const _FakeUploadedFile({
    required this.idToken,
    required this.vaultId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String idToken;
  final String vaultId;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
}

class _FakeCloudWebChatClient implements CloudWebChatClient {
  _FakeCloudWebChatClient({
    this.error,
  });

  final Object? error;

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
    if (error != null) throw error!;
    return 'Assistant reply';
  }
}

final class _TestWebFilePicker extends FilePicker {
  _TestWebFilePicker({required this.result});

  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    Function(FilePickerStatus)? onFileLoading,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool allowCompression = true,
    int compressionQuality = 30,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

final class _DeferredWebFilePicker extends FilePicker {
  _DeferredWebFilePicker({required this.resultFuture});

  final Future<FilePickerResult?> resultFuture;

  @override
  Future<FilePickerResult?> pickFiles({
    Function(FilePickerStatus)? onFileLoading,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool allowCompression = true,
    int compressionQuality = 30,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      resultFuture;
}

Finder _navigationLabel(String label) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
}

Widget _buildApp({
  required ObservableCloudAuthController controller,
  required WebAppService service,
  CloudWebBackend? chatBackend,
  Locale? locale,
  WebEntryIntent entryIntent = WebEntryIntent.open,
}) {
  return wrapWithI18n(
    MaterialApp(
      locale: locale,
      home: WebAppGate(
        authController: controller,
        service: service,
        chatBackend: chatBackend,
        entryIntent: entryIntent,
      ),
    ),
  );
}

void main() {
  testWidgets('shows auth form when signed out', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(),
        service: _FakeWebAppService(subscription: WebSubscriptionState.unknown),
      ),
    );

    expect(find.byType(CloudAccountPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_up')), findsOneWidget);
  });

  testWidgets('subscribe intent explains sign-in before web access',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(),
        service: _FakeWebAppService(subscription: WebSubscriptionState.unknown),
        entryIntent: WebEntryIntent.subscribe,
      ),
    );

    expect(find.text('Subscribe for web access'), findsOneWidget);
    expect(
      find.textContaining('Sign in first'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
  });

  testWidgets('shows upgrade gate when signed in without entitlement',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.notEntitled),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_subscribe')), findsOneWidget);
  });

  testWidgets(
      'subscription refresh unlocks main shell after entitlement changes',
      (tester) async {
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.notEntitled,
    );

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: service,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPanel), findsOneWidget);
    expect(find.text('Chat'), findsNothing);

    service.subscription = WebSubscriptionState.entitled;

    await tester.tap(find.byKey(const ValueKey('cloud_subscription_refresh')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    expect(find.byType(CloudAccountPanel), findsNothing);
  });

  testWidgets(
      'entitled users stay in main shell when subscription refresh fails',
      (tester) async {
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
    );

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: service,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    expect(find.byType(CloudAccountPanel), findsNothing);

    service.failNextSubscriptionError =
        'cloud-gateway request failed: HTTP 503';
    service.failNextSubscriptionFetch = true;

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('cloud_subscription_refresh')),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(
      find.byKey(const ValueKey('cloud_subscription_refresh')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    expect(_navigationLabel('Files'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud_manage_subscription')),
      findsOneWidget,
    );
  });

  testWidgets(
      'switching users clears web session state and blocks shell until new entitlement loads',
      (tester) async {
    final controller = _FakeCloudAuthController(
      initialUid: 'uid-1',
      initialEmail: 'user@example.com',
      initialEmailVerified: true,
    );
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
    );
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(),
    );

    await tester.pumpWidget(
      _buildApp(
        controller: controller,
        service: service,
        chatBackend: backend,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello cloud');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.text('Hello cloud'), findsOneWidget);
    expect(find.text('Assistant reply'), findsOneWidget);

    service.failNextSubscriptionError =
        'cloud-gateway request failed: HTTP 503';
    service.failNextSubscriptionFetch = true;
    controller.setSession(
      uid: 'uid-2',
      email: 'other@example.com',
      emailVerified: true,
    );
    await tester.pump();

    expect(find.text('SecondLoop Web'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Hello cloud'), findsNothing);
    expect(find.text('Assistant reply'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('Hello cloud'), findsNothing);
    expect(find.text('Assistant reply'), findsNothing);
  });

  testWidgets('upgrade gate localizes checkout payment-required error inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.notEntitled,
          checkoutError:
              'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final subscribeButton = find.byKey(const ValueKey('cloud_subscribe'));
    await tester.ensureVisible(subscribeButton);
    await tester.pumpAndSettle();
    await tester.tap(subscribeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
        'Failed to load: Cloud sync is paused. Renew your subscription to continue syncing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('upgrade gate localizes checkout missing web api key inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.notEntitled,
          checkoutError: FirebaseAuthException('missing_web_api_key'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final subscribeButton = find.byKey(const ValueKey('cloud_subscribe'));
    await tester.ensureVisible(subscribeButton);
    await tester.pumpAndSettle();
    await tester.tap(subscribeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('missing_web_api_key'), findsNothing);
    expect(
      find.textContaining("Cloud sign-in isn't available in this build."),
      findsOneWidget,
    );
  });

  testWidgets('shows main shell when signed in and entitled', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SecondLoop Web'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(_navigationLabel('Files'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('manage intent opens the entitled web app on Settings first',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        entryIntent: WebEntryIntent.manage,
      ),
    );
    await tester.pumpAndSettle();

    final navigationBar =
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigationBar.selectedIndex, 2);
    expect(
      find.byKey(const ValueKey('cloud_manage_subscription')),
      findsOneWidget,
    );
  });

  testWidgets('web shell localizes navigation and recent files in zh-CN',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    try {
      await tester.pumpWidget(
        _buildApp(
          controller: _FakeCloudAuthController(
            initialUid: 'uid-1',
            initialEmail: 'user@example.com',
            initialEmailVerified: true,
          ),
          service: _FakeWebAppService(
            subscription: WebSubscriptionState.entitled,
            usage: const WebUsageSummary(
              askAiUsagePercent: 27,
              embeddingsUsagePercent: 9,
              resetAtMs: 1735689600000,
            ),
            vaultUsage: const WebVaultUsageSummary(
              totalBytesUsed: 12,
              limitBytes: 128,
            ),
          ),
          locale: const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SecondLoop 网页版'), findsOneWidget);
      expect(find.text('对话'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('最近文件'),
        find.byType(ListView),
        const Offset(0, -240),
      );

      expect(find.text('最近文件'), findsOneWidget);
      expect(find.text('暂无云端文件。'), findsOneWidget);
    } finally {
      LocaleSettings.setLocale(AppLocale.en);
    }
  });

  testWidgets('web files localizes upload success snackbar in zh-CN',
      (tester) async {
    FilePicker.platform = _TestWebFilePicker(
      result: FilePickerResult([
        PlatformFile(
          name: 'note.txt',
          size: 5,
          bytes: Uint8List.fromList(const <int>[104, 101, 108, 108, 111]),
        ),
      ]),
    );

    LocaleSettings.setLocale(AppLocale.zhCn);
    try {
      await tester.pumpWidget(
        _buildApp(
          controller: _FakeCloudAuthController(
            initialUid: 'uid-1',
            initialEmail: 'user@example.com',
            initialEmailVerified: true,
          ),
          service: _FakeWebAppService(
            subscription: WebSubscriptionState.entitled,
            vaultUsage: const WebVaultUsageSummary(
              totalBytesUsed: 12,
              limitBytes: 128,
            ),
          ),
          locale: const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('已上传 1 个文件到 Cloud。'), findsOneWidget);
    } finally {
      LocaleSettings.setLocale(AppLocale.en);
      FilePicker.platform = _TestWebFilePicker(result: null);
    }
  });

  testWidgets('web files uploads from read stream without eager bytes',
      (tester) async {
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
      vaultUsage: const WebVaultUsageSummary(
        totalBytesUsed: 12,
        limitBytes: 128,
      ),
    );
    FilePicker.platform = _TestWebFilePicker(
      result: FilePickerResult([
        PlatformFile(
          name: 'stream-note.txt',
          size: 5,
          readStream: Stream<List<int>>.fromIterable(
            <List<int>>[
              const <int>[104, 101],
              const <int>[108, 108, 111],
            ],
          ),
        ),
      ]),
    );

    try {
      await tester.pumpWidget(
        _buildApp(
          controller: _FakeCloudAuthController(
            initialUid: 'uid-1',
            initialEmail: 'user@example.com',
            initialEmailVerified: true,
          ),
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_navigationLabel('Files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(service.uploads, hasLength(1));
      expect(service.uploads.single.fileName, 'stream-note.txt');
      expect(String.fromCharCodes(service.uploads.single.bytes), 'hello');
    } finally {
      FilePicker.platform = _TestWebFilePicker(result: null);
    }
  });

  testWidgets(
      'web files upload surfaces partial success for mixed readable batches',
      (tester) async {
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
      vaultUsage: const WebVaultUsageSummary(
        totalBytesUsed: 12,
        limitBytes: 128,
      ),
    );
    FilePicker.platform = _TestWebFilePicker(
      result: FilePickerResult([
        PlatformFile(name: 'broken.txt', size: 10),
        PlatformFile(
          name: 'stream-note.txt',
          size: 5,
          readStream: Stream<List<int>>.fromIterable(
            <List<int>>[
              const <int>[104, 101],
              const <int>[108, 108, 111],
            ],
          ),
        ),
      ]),
    );

    try {
      await tester.pumpWidget(
        _buildApp(
          controller: _FakeCloudAuthController(
            initialUid: 'uid-1',
            initialEmail: 'user@example.com',
            initialEmailVerified: true,
          ),
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_navigationLabel('Files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(service.uploads, hasLength(1));
      expect(
        find.text(
            'Uploaded 1 file(s) to Cloud. 1 file(s) could not be uploaded.'),
        findsOneWidget,
      );
    } finally {
      FilePicker.platform = _TestWebFilePicker(result: null);
    }
  });

  testWidgets('web files disables upload while picker is open', (tester) async {
    final pickerCompleter = Completer<FilePickerResult?>();
    FilePicker.platform =
        _DeferredWebFilePicker(resultFuture: pickerCompleter.future);

    try {
      await tester.pumpWidget(
        _buildApp(
          controller: _FakeCloudAuthController(
            initialUid: 'uid-1',
            initialEmail: 'user@example.com',
            initialEmailVerified: true,
          ),
          service: _FakeWebAppService(
            subscription: WebSubscriptionState.entitled,
            vaultUsage: const WebVaultUsageSummary(
              totalBytesUsed: 12,
              limitBytes: 128,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_navigationLabel('Files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload'));
      await tester.pump();

      final uploadButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Upload'),
      );
      expect(uploadButton.onPressed, isNull);

      pickerCompleter.complete(null);
      await tester.pumpAndSettle();
    } finally {
      FilePicker.platform = _TestWebFilePicker(result: null);
    }
  });

  testWidgets('web files upload surfaces auth expiry before any upload',
      (tester) async {
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
      vaultUsage: const WebVaultUsageSummary(
        totalBytesUsed: 12,
        limitBytes: 128,
      ),
    );
    FilePicker.platform = _TestWebFilePicker(
      result: FilePickerResult([
        PlatformFile(
          name: 'stream-note.txt',
          size: 5,
          readStream: Stream<List<int>>.fromIterable(
            <List<int>>[
              const <int>[104, 101],
              const <int>[108, 108, 111],
            ],
          ),
        ),
      ]),
    );

    try {
      final controller = _FakeCloudAuthController(
        initialUid: 'uid-1',
        initialEmail: 'user@example.com',
        initialEmailVerified: true,
      );
      await tester.pumpWidget(
        _buildApp(
          controller: controller,
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_navigationLabel('Files'));
      await tester.pumpAndSettle();
      controller.setIdTokenSequence(const <String?>[null]);
      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(service.uploads, isEmpty);
      expect(
        find.text(
            'Cloud upload expired before any file could be uploaded. Please try again.'),
        findsOneWidget,
      );
    } finally {
      FilePicker.platform = _TestWebFilePicker(result: null);
    }
  });

  testWidgets('web files opens attachment viewer with formal page',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          items: const <WebVaultAttachmentItem>[
            WebVaultAttachmentItem(
              sha256: 'sha-text',
              mimeType: 'text/plain',
              byteLen: 11,
            ),
          ],
          bytesBySha: const <String, List<int>>{
            'sha-text': <int>[104, 101, 108, 108, 111, 32, 119, 101, 98],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_navigationLabel('Files'));
    await tester.pumpAndSettle();

    expect(find.byType(VaultAttachmentUsageListView), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-text')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('vault_usage_attachment_sha-text')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AttachmentViewerPage), findsOneWidget);
  });

  testWidgets(
      'settings recent attachment opens attachment viewer with formal page',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
          items: const <WebVaultAttachmentItem>[
            WebVaultAttachmentItem(
              sha256:
                  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
              mimeType: 'text/plain',
              byteLen: 12,
              uploadedAtMs: 200,
            ),
          ],
          bytesBySha: const <String, List<int>>{
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef':
                <int>[104, 101, 108, 108, 111, 32, 119, 101, 98],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(CloudUsageCard), findsOneWidget);
    expect(find.text('27%'), findsOneWidget);
    expect(find.text('9%'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byType(VaultUsageCard),
      find.byType(ListView),
      const Offset(0, -240),
    );
    expect(find.byType(VaultUsageCard), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('text/plain • 12 bytes'),
      find.byType(ListView),
      const Offset(0, -240),
    );

    final recentTile = tester.widget<ListTile>(find.byType(ListTile).last);
    final recentTitle = recentTile.title! as Text;
    expect(
      recentTitle.data,
      isNot('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),
    );

    await tester.tap(find.byType(ListTile).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AttachmentViewerPage), findsOneWidget);
  });

  testWidgets('settings shows formal cloud account section inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('cloud_manage_subscription')),
      find.byType(ListView),
      const Offset(0, -240),
    );

    expect(find.text('Open full account page'), findsNothing);
    expect(find.byType(CloudAccountPage), findsNothing);
    expect(find.byKey(const ValueKey('cloud_manage_subscription')),
        findsOneWidget);
  });

  testWidgets(
      'settings shows localized cloud usage payment-required error inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usageError:
              'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}',
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text('Failed to load: Subscription required to view cloud usage.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'settings shows localized vault usage payment-required error inline',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_managed_vault_base_url': 'https://web.secondloop.invalid/',
    });
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsageError:
              'managed-vault request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byType(VaultUsageCard),
      find.byType(ListView),
      const Offset(0, -240),
    );

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
        'Failed to load: Cloud sync is paused. Renew your subscription to continue syncing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('files handled refresh error stays silent in debug log',
      (tester) async {
    final captured = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        captured.add(message);
      }
    };

    try {
      await tester.pumpWidget(
        _buildApp(
          controller: _FakeCloudAuthController(
            initialUid: 'uid-1',
            initialEmail: 'user@example.com',
            initialEmailVerified: true,
          ),
          service: _FakeWebAppService(
            subscription: WebSubscriptionState.entitled,
            vaultUsageError:
                'managed-vault request failed: HTTP 402 {"error":"payment_required"}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_navigationLabel('Files'));
      await tester.pumpAndSettle();

      expect(
        captured.where(
            (message) => message.contains('web_gate_refresh_auth_state_error')),
        isEmpty,
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  testWidgets('files shows localized vault refresh error inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          vaultUsageError:
              'managed-vault request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_navigationLabel('Files'));
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
          'Cloud sync is paused. Renew your subscription to continue syncing.'),
      findsOneWidget,
    );
  });

  testWidgets('files localizes storage quota exceeded inline', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          vaultUsageError:
              'managed-vault request failed: HTTP 403 {"error":"storage_quota_exceeded"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_navigationLabel('Files'));
    await tester.pumpAndSettle();

    expect(find.textContaining('storage_quota_exceeded'), findsNothing);
    expect(
      find.text('Cloud storage is full. Uploads are paused.'),
      findsOneWidget,
    );
  });

  testWidgets('files surfaces auth expiry inline on refresh', (tester) async {
    final controller = _FakeCloudAuthController(
      initialUid: 'uid-1',
      initialEmail: 'user@example.com',
      initialEmailVerified: true,
    );

    await tester.pumpWidget(
      _buildApp(
        controller: controller,
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_navigationLabel('Files'));
    await tester.pumpAndSettle();
    controller.setIdTokenSequence(const <String?>[null]);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Cloud sign-in required. Open Cloud account and sign in again.'),
      findsOneWidget,
    );
  });

  testWidgets('files localizes server unavailable inline', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          vaultUsageError: 'managed-vault request failed: HTTP 503',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_navigationLabel('Files'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 503'), findsNothing);
    expect(
      find.text(
          'Cloud sync is temporarily unavailable. Please try again later.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'settings shows localized billing portal payment-required error inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
          portalError:
              'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('cloud_manage_subscription')),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(find.byKey(const ValueKey('cloud_manage_subscription')));
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
        'Failed to load: Cloud sync is paused. Renew your subscription to continue syncing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings localizes vault delete failure snackbar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_managed_vault_base_url': 'https://web.secondloop.invalid/',
    });
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
          items: const <WebVaultAttachmentItem>[
            WebVaultAttachmentItem(
              sha256: 'sha-delete',
              mimeType: 'text/plain',
              byteLen: 11,
            ),
          ],
          deleteError:
              'managed-vault request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('vault_usage_attachment_delete_sha-delete')),
      find.byType(ListView),
      const Offset(0, -240),
    );
    final deleteButton =
        find.byKey(const ValueKey('vault_usage_attachment_delete_sha-delete'));
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    final confirmButton = find.byKey(
      const ValueKey('vault_usage_attachment_delete_confirm_sha-delete'),
    );
    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.textContaining(
        'Delete failed: Cloud sync is paused. Renew your subscription to continue syncing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings recent files localizes vault refresh error inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
          listError:
              'managed-vault request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Recent files'),
      find.byType(ListView),
      const Offset(0, -240),
    );

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
          'Cloud sync is paused. Renew your subscription to continue syncing.'),
      findsWidgets,
    );
  });

  testWidgets('settings recent files localizes open failure inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
          items: const <WebVaultAttachmentItem>[
            WebVaultAttachmentItem(
              sha256: 'sha-open-error',
              mimeType: 'text/plain',
              byteLen: 12,
              uploadedAtMs: 200,
            ),
          ],
          bytesError: 'managed-vault request failed: HTTP 429',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('text/plain • 12 bytes'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    final recentItem = find.byType(ListTile).last;
    await tester.ensureVisible(recentItem);
    await tester.pumpAndSettle();
    await tester.tap(recentItem, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 429'), findsNothing);
    expect(
      find.text('Cloud is rate limited. Please try again later.'),
      findsOneWidget,
    );
  });

  testWidgets('settings recent files localize oversized attachment errors',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
          items: const <WebVaultAttachmentItem>[
            WebVaultAttachmentItem(
              sha256: 'sha-open-too-large',
              mimeType: 'application/pdf',
              byteLen: 12,
              uploadedAtMs: 200,
            ),
          ],
          bytesError: StateError('attachment_too_large_for_web'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('application/pdf • 12 bytes'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    final recentItem = find.byType(ListTile).last;
    await tester.ensureVisible(recentItem);
    await tester.pumpAndSettle();
    await tester.tap(recentItem, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('attachment_too_large_for_web'), findsNothing);
    expect(
      find.text('This file is too large to open safely in the browser.'),
      findsOneWidget,
    );
  });

  testWidgets('settings localizes subscription refresh failure inline',
      (tester) async {
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
      usage: const WebUsageSummary(
        askAiUsagePercent: 27,
        embeddingsUsagePercent: 9,
        resetAtMs: 1735689600000,
      ),
      vaultUsage: const WebVaultUsageSummary(
        totalBytesUsed: 12,
        limitBytes: 128,
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: service,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final subscriptionRefresh =
        find.byKey(const ValueKey('cloud_subscription_refresh'));
    await tester.ensureVisible(subscriptionRefresh);
    await tester.pumpAndSettle();

    service.failNextSubscriptionError =
        'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}';
    service.failNextSubscriptionFetch = true;

    await tester.tap(subscriptionRefresh, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
        'Failed to load: Cloud sync is paused. Renew your subscription to continue syncing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings localizes resend verification failure snackbar',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: false,
          sendVerificationError: FirebaseAuthException('missing_web_api_key'),
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
          usage: const WebUsageSummary(
            askAiUsagePercent: 27,
            embeddingsUsagePercent: 9,
            resetAtMs: 1735689600000,
          ),
          vaultUsage: const WebVaultUsageSummary(
            totalBytesUsed: 12,
            limitBytes: 128,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('cloud_resend_verification')),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(
      find.byKey(const ValueKey('cloud_resend_verification')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('missing_web_api_key'), findsNothing);
    expect(
      find.textContaining("Cloud sign-in isn't available in this build."),
      findsOneWidget,
    );
  });

  testWidgets('web chat sends through cloud web backend', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        chatBackend: CloudWebBackend(
          chatClient: _FakeCloudWebChatClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello cloud');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.text('Hello cloud'), findsOneWidget);
    expect(find.text('Assistant reply'), findsOneWidget);

    await tester.tap(find.text('Assistant reply'));
    await tester.pumpAndSettle();

    expect(find.byType(MessageViewerPage), findsOneWidget);
  });

  testWidgets('web chat shows localized email verification error',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: false,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        chatBackend: CloudWebBackend(
          chatClient: _FakeCloudWebChatClient(
            error:
                'cloud-gateway request failed: HTTP 403 {"error":"email_not_verified"}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello cloud');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 403'), findsNothing);
    expect(
      find.text(
          'Email not verified. Verify your email to use SecondLoop Cloud Ask AI.'),
      findsOneWidget,
    );
  });

  testWidgets('web chat shows localized payment required error',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        chatBackend: CloudWebBackend(
          chatClient: _FakeCloudWebChatClient(
            error:
                'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello cloud');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
          'Cloud subscription required. Add an API key or try again later.'),
      findsOneWidget,
    );
  });

  testWidgets('web chat shows localized throttling error', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        chatBackend: CloudWebBackend(
          chatClient: _FakeCloudWebChatClient(
            error: 'cloud-gateway request failed: HTTP 429',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello cloud');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 429'), findsNothing);
    expect(
      find.text('Cloud is rate limited. Please try again later.'),
      findsOneWidget,
    );
  });
}
