import 'package:flutter/foundation.dart';

import 'local_runtime_helper_process.dart';
import 'runtime_connection_store.dart';
import 'runtime_manifest.dart';
import 'runtime_profile.dart';
import 'self_managed_setup_models.dart';

final class SelfManagedSetupController extends ChangeNotifier {
  SelfManagedSetupController({
    RuntimeConnectionStore? connectionStore,
    LocalRuntimeHelperProcess? helperProcess,
  })  : _connectionStore = connectionStore ?? RuntimeConnectionStore(),
        _helperProcess = helperProcess ?? LocalRuntimeHelperProcess();

  final RuntimeConnectionStore _connectionStore;
  final LocalRuntimeHelperProcess _helperProcess;

  SelfManagedSetupState _state = const SelfManagedSetupState.idle();

  SelfManagedSetupState get state => _state;

  void restoreConnection(CloudRuntimeConnection connection) {
    _state = _state.copyWith(
      step: SelfManagedSetupStep.ready,
      statusMessage: 'ready',
      errorCode: null,
      manifest: connection.manifest,
      verification: null,
    );
    notifyListeners();
  }

  void beginCloudflareAuthorization() {
    _state = _state.copyWith(
      step: SelfManagedSetupStep.authorizing,
      statusMessage: 'authorizing',
      errorCode: null,
    );
    notifyListeners();
  }

  void reportCloudflareOAuthUnavailable() {
    _state = _state.copyWith(
      step: SelfManagedSetupStep.failed,
      statusMessage: 'tool_unavailable:cloudflare_oauth',
      errorCode: 'tool_unavailable:cloudflare_oauth',
    );
    notifyListeners();
  }

  Future<SelfManagedCloudflareAuthorizationResult?> authorizeCloudflareOAuth({
    required String accountLabel,
  }) async {
    _state = _state.copyWith(
      step: SelfManagedSetupStep.authorizing,
      statusMessage: 'authorizing_cloudflare_oauth',
      errorCode: null,
    );
    notifyListeners();
    try {
      final result = await _helperProcess.runCloudflareAuthorization(
        accountLabel,
        onProgress: (event) {
          _state = _state.copyWith(
            step: event.step,
            statusMessage: event.message,
            errorCode: null,
          );
          notifyListeners();
        },
      );
      _state = _state.copyWith(
        step: SelfManagedSetupStep.cloudflareReady,
        statusMessage: 'cloudflare_oauth_ready',
        errorCode: null,
      );
      notifyListeners();
      return result;
    } on LocalRuntimeHelperException catch (error) {
      _state = _state.copyWith(
        step: SelfManagedSetupStep.failed,
        statusMessage: error.message,
        errorCode: error.code,
      );
      notifyListeners();
      return null;
    }
  }

  bool prepareManualCloudflareAuthorization({
    required String accountId,
    required String apiToken,
  }) {
    final request = SelfManagedSetupRequest(
      cloudflareAccountLabel: accountId.trim(),
      provider: '',
      apiKey: '',
      cloudflareAuthorizationMethod:
          SelfManagedCloudflareAuthorizationMethod.manual,
      cloudflareAccountId: accountId,
      cloudflareApiToken: apiToken,
    );
    final missing = request.firstMissingCloudflareAuthorizationField;
    if (missing != null) {
      _state = _state.copyWith(
        step: SelfManagedSetupStep.failed,
        statusMessage: missing,
        errorCode: missing,
      );
      notifyListeners();
      return false;
    }
    _state = _state.copyWith(
      step: SelfManagedSetupStep.cloudflareReady,
      statusMessage: 'manual_cloudflare_credentials_ready',
      errorCode: null,
    );
    notifyListeners();
    return true;
  }

  Future<void> deploy(SelfManagedSetupRequest request) async {
    final missingCloudflare = request.firstMissingCloudflareAuthorizationField;
    if (missingCloudflare != null) {
      _state = _state.copyWith(
        step: SelfManagedSetupStep.failed,
        statusMessage: missingCloudflare,
        errorCode: missingCloudflare,
      );
      notifyListeners();
      return;
    }
    beginCloudflareAuthorization();
    try {
      final result = await _helperProcess.runSetup(
        request,
        onProgress: (event) {
          _state = _state.copyWith(
            step: event.step,
            statusMessage: event.message,
            errorCode: null,
          );
          notifyListeners();
        },
      );
      final verification = result.verification;
      if (verification == null || !verification.ok) {
        final failureCode = verification?.firstFailureCode ??
            'model_capability_verification_failed';
        _state = _state.copyWith(
          step: SelfManagedSetupStep.failed,
          statusMessage: failureCode,
          errorCode: failureCode,
          verification: verification,
        );
        notifyListeners();
        return;
      }
      final missingCheck =
          ModelCapabilityRequiredChecks.firstMissingFrom(verification.checks);
      if (missingCheck != null) {
        _state = _state.copyWith(
          step: SelfManagedSetupStep.failed,
          statusMessage: missingCheck,
          errorCode: 'missing_model_capability_check:$missingCheck',
          verification: verification,
        );
        notifyListeners();
        return;
      }
      final missingCapability =
          CloudRuntimeRequiredCapabilities.firstMissingFrom(
        result.manifest.capabilities,
      );
      if (missingCapability != null) {
        _state = _state.copyWith(
          step: SelfManagedSetupStep.failed,
          statusMessage: missingCapability.id,
          errorCode: 'missing_runtime_capability',
          verification: verification,
        );
        notifyListeners();
        return;
      }
      await _connectionStore.saveConnection(
        CloudRuntimeConnection(
          profile: CloudRuntimeProfile(
            runtimeMode: result.manifest.runtimeMode,
            apiBaseUrl: result.manifest.apiBaseUrl,
            authMode: result.manifest.authMode,
            authToken: result.authToken,
            capabilityManifestId: result.capabilityManifestId,
            manifestVersion: result.manifest.manifestVersion,
          ),
          manifest: result.manifest,
        ),
      );
      _state = _state.copyWith(
        step: SelfManagedSetupStep.ready,
        statusMessage: 'ready',
        errorCode: null,
        manifest: result.manifest,
        verification: verification,
      );
      notifyListeners();
    } on LocalRuntimeHelperException catch (error) {
      _state = _state.copyWith(
        step: SelfManagedSetupStep.failed,
        statusMessage: error.message,
        errorCode: error.code,
      );
      notifyListeners();
    }
  }

  Future<void> uninstall(SelfManagedRuntimeUninstallRequest request) async {
    final missingCloudflare = request.firstMissingCloudflareAuthorizationField;
    if (missingCloudflare != null) {
      _state = _state.copyWith(
        step: SelfManagedSetupStep.failed,
        statusMessage: missingCloudflare,
        errorCode: missingCloudflare,
      );
      notifyListeners();
      return;
    }
    _state = _state.copyWith(
      step: SelfManagedSetupStep.authorizing,
      statusMessage: 'authorizing',
      errorCode: null,
    );
    notifyListeners();
    try {
      final result = await _helperProcess.runUninstall(
        request,
        onProgress: (event) {
          _state = _state.copyWith(
            step: event.step,
            statusMessage: event.message,
            errorCode: null,
          );
          notifyListeners();
        },
      );
      if (!result.ok) {
        _state = _state.copyWith(
          step: SelfManagedSetupStep.failed,
          statusMessage: 'self_managed_runtime_uninstall_failed',
          errorCode: 'self_managed_runtime_uninstall_failed',
        );
        notifyListeners();
        return;
      }
      await _connectionStore.clearConnection();
      _state = _state.copyWith(
        step: SelfManagedSetupStep.uninstalled,
        statusMessage: 'uninstalled',
        errorCode: null,
        manifest: null,
        verification: null,
      );
      notifyListeners();
    } on LocalRuntimeHelperException catch (error) {
      _state = _state.copyWith(
        step: SelfManagedSetupStep.failed,
        statusMessage: error.message,
        errorCode: error.code,
      );
      notifyListeners();
    }
  }

  Future<void> reset() async {
    await _connectionStore.clearConnection();
    _state = const SelfManagedSetupState.idle();
    notifyListeners();
  }
}
