import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_diagnostics.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

part 'sync_engine_gate_media_uploads_test_helpers.dart';
part 'sync_engine_gate_media_uploads_test_webdav.dart';
part 'sync_engine_gate_media_uploads_test_managed_vault.dart';
part 'sync_engine_gate_media_uploads_test_gate_state.dart';

void main() {
  registerSyncEngineGateMediaUploadWebdavTests();
  registerSyncEngineGateMediaUploadManagedVaultTests();
  registerSyncEngineGateMediaUploadGateStateTests();
}
