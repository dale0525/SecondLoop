import 'package:flutter/foundation.dart';

import 'local_runtime_helper_process.dart';
import 'runtime_connection_store.dart';
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

  void beginCloudflareAuthorization() {
    _state = _state.copyWith(
      step: SelfManagedSetupStep.authorizing,
      statusMessage: 'authorizing',
      errorCode: null,
    );
    notifyListeners();
  }

  Future<void> deploy(SelfManagedSetupRequest request) async {
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
