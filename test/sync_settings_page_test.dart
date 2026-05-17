import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_diagnostics.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_i18n.dart';

part 'sync_settings_page_core_a_part.dart';
part 'sync_settings_page_core_b_part.dart';
part 'sync_settings_page_core_c_part.dart';
part 'sync_settings_page_test_support_part.dart';
part 'sync_settings_page_managed_vault_support_part.dart';

void main() {
  registerSyncSettingsPageCoreATests();
  registerSyncSettingsPageCoreBTests();
  registerSyncSettingsPageCoreCTests();
}
