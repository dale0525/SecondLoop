import 'web_local_runtime_recovery_base.dart';
import 'web_local_runtime_recovery_stub.dart'
    if (dart.library.html) 'web_local_runtime_recovery_web.dart';

WebLocalRuntimeRecovery createDefaultWebLocalRuntimeRecovery() =>
    createWebLocalRuntimeRecovery();
