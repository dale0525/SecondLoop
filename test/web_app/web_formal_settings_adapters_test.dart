import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/web_app/web_app_gate.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';

class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({this.idTokenValue = 'token'});

  final String? uidValue = 'uid-1';
  final String? idTokenValue;

  @override
  String? get uid => uidValue;

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => uidValue == null ? null : idTokenValue;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({
    this.subscription = WebSubscriptionState.entitled,
    this.canManageSubscription,
    this.usage,
    this.vaultUsage,
    this.items = const <WebVaultAttachmentItem>[],
    this.previews = const <String, WebVaultAttachmentPreview>{},
  });

  final WebSubscriptionState subscription;
  final bool? canManageSubscription;
  final WebUsageSummary? usage;
  final WebVaultUsageSummary? vaultUsage;
  final List<WebVaultAttachmentItem> items;
  final Map<String, WebVaultAttachmentPreview> previews;
  final List<String> openedActions = <String>[];

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
      {required String idToken}) async {
    return WebSubscriptionSnapshot(
      state: subscription,
      canManageSubscription: canManageSubscription ??
          (subscription == WebSubscriptionState.entitled),
    );
  }

  @override
  Future<void> openCheckout({required String idToken}) async {
    openedActions.add('checkout:$idToken');
  }

  @override
  Future<void> openPortal({required String idToken}) async {
    openedActions.add('portal:$idToken');
  }

  @override
  Future<WebUsageSummary?> fetchUsage({required String idToken}) async => usage;

  @override
  Future<WebVaultUsageSummary?> fetchVaultUsage({
    required String idToken,
    required String vaultId,
  }) async =>
      vaultUsage;

  @override
  Future<List<WebVaultAttachmentItem>> listVaultAttachments({
    required String idToken,
    required String vaultId,
  }) async =>
      items;

  @override
  Future<WebVaultAttachmentPreview> fetchVaultAttachmentPreview({
    required String idToken,
    required String vaultId,
    required String attachmentId,
  }) async =>
      previews[attachmentId] ??
      WebVaultAttachmentPreview(
        kind: 'download',
        url: '/api/app/vault-proxy/v1/vaults/$vaultId/attachments/'
            '$attachmentId',
      );

  @override
  Future<void> deleteVaultAttachment({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async {}
}

void main() {
  test('web formal settings adapter maps usage and vault requests', () async {
    final authController = _FakeCloudAuthController();
    final service = _FakeWebAppService(
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
          id: 'att-settings',
          sha256: 'sha-settings',
          displayName: 'original-name.txt',
          mimeType: 'text/plain',
          byteLen: 12,
          uploadedAtMs: 200,
          preview: WebVaultAttachmentPreview(
            kind: 'download',
            url: '/api/app/vault-proxy/v1/vaults/uid-1/attachments/'
                'att-settings',
          ),
        ),
      ],
      previews: const <String, WebVaultAttachmentPreview>{
        'att-settings': WebVaultAttachmentPreview(
          kind: 'download',
          url: '/api/app/vault-proxy/v1/vaults/uid-1/attachments/'
              'att-settings',
        ),
      },
    );

    final usageClient = CloudUsageClient(
      httpClient: WebFormalSettingsHttpClient(
        service: service,
        authController: authController,
      ),
    );
    final vaultUsageClient = VaultUsageClient(
      httpClient: WebFormalSettingsHttpClient(
        service: service,
        authController: authController,
      ),
    );
    final attachmentsClient = VaultAttachmentsClient(
      httpClient: WebFormalSettingsHttpClient(
        service: service,
        authController: authController,
      ),
    );

    final usage = await usageClient.fetchUsageSummary(
      cloudGatewayBaseUrl: kWebFormalSettingsBaseUrl,
      idToken: 'token',
    );
    final vaultUsage = await vaultUsageClient.fetchVaultUsageSummary(
      managedVaultBaseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'uid-1',
      idToken: 'token',
    );
    final attachmentUsage =
        await attachmentsClient.fetchVaultAttachmentUsageList(
      managedVaultBaseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'uid-1',
      idToken: 'token',
    );

    expect(usage.askAiUsagePercent, 27);
    expect(usage.embeddingsUsagePercent, 9);
    expect(vaultUsage.totalBytesUsed, 12);
    expect(vaultUsage.limitBytes, 128);
    expect(attachmentUsage.totalCount, 1);
    expect(attachmentUsage.totalBytesUsed, 12);
    expect(attachmentUsage.items.single.id, 'att-settings');
    expect(attachmentUsage.items.single.sha256, 'sha-settings');
    expect(attachmentUsage.items.single.displayName, 'original-name.txt');

    final preview = await attachmentsClient.fetchAttachmentPreview(
      managedVaultBaseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'uid-1',
      idToken: 'token',
      attachmentId: 'att-settings',
    );
    expect(preview.kind, 'download');
    expect(
      preview.url,
      'https://web.secondloop.invalid/api/app/vault-proxy/v1/vaults/'
      'uid-1/attachments/att-settings',
    );
  });

  test(
      'web formal settings adapter prefers request authorization over auth state',
      () async {
    final authController = _FakeCloudAuthController(idTokenValue: null);
    final service = _FakeWebAppService(
      usage: const WebUsageSummary(
        askAiUsagePercent: 31,
        embeddingsUsagePercent: 12,
        resetAtMs: 1735689600000,
      ),
    );

    final usageClient = CloudUsageClient(
      httpClient: WebFormalSettingsHttpClient(
        service: service,
        authController: authController,
      ),
    );

    final usage = await usageClient.fetchUsageSummary(
      cloudGatewayBaseUrl: kWebFormalSettingsBaseUrl,
      idToken: 'token-from-request',
    );

    expect(usage.askAiUsagePercent, 31);
    expect(usage.embeddingsUsagePercent, 12);
  });

  test('web formal settings adapter maps subscription and billing client',
      () async {
    final authController = _FakeCloudAuthController();
    final service = _FakeWebAppService();
    final subscriptionController = createWebFormalSubscriptionController(
      service: service,
      authController: authController,
    );
    final billing = WebAppBillingClient(
      service: service,
      authController: authController,
    );

    await subscriptionController.refresh();
    await billing.openCheckout();
    await billing.openPortal();

    expect(subscriptionController.status, SubscriptionStatus.entitled);
    expect(subscriptionController.canManageSubscription, isTrue);
    expect(service.openedActions, <String>['checkout:token', 'portal:token']);

    subscriptionController.dispose();
  });

  test('web formal settings bridge does not synthesize billing urls', () async {
    final client = WebFormalSettingsHttpClient(
      service: _FakeWebAppService(),
      authController: _FakeCloudAuthController(),
    );

    final request = http.Request(
      'POST',
      Uri.parse('${kWebFormalSettingsBaseUrl}v1/billing/checkout'),
    );
    final response = await http.Response.fromStream(await client.send(request));

    expect(response.statusCode, 404);
    expect(response.body, contains('unsupported_bridge_request'));
  });

  test('web formal settings adapter preserves can_manage_subscription=false',
      () async {
    final authController = _FakeCloudAuthController();
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
      canManageSubscription: false,
    );
    final subscriptionController = createWebFormalSubscriptionController(
      service: service,
      authController: authController,
    );

    await subscriptionController.refresh();

    expect(subscriptionController.status, SubscriptionStatus.entitled);
    expect(subscriptionController.canManageSubscription, isFalse);

    subscriptionController.dispose();
  });
}
