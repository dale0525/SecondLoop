import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import 'setup_master_password_page.dart';
import 'unlock_page.dart';

class LockGate extends StatefulWidget {
  const LockGate({required this.child, super.key});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  Future<_GateBootstrapResult>? _bootstrapFuture;
  Uint8List? _sessionKey;

  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kMasterPasswordSetupRequiredPrefsKey =
      'master_password_setup_required_v1';

  Uint8List _createSessionKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  void _lock() {
    setState(() {
      _sessionKey = null;
      _bootstrapFuture = null;
    });
  }

  Future<_GateBootstrapResult> _bootstrap() async {
    final backend = AppBackendScope.of(context);
    final prefs = await SharedPreferences.getInstance();
    final appLockEnabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;
    final setupRequired =
        prefs.getBool(_kMasterPasswordSetupRequiredPrefsKey) ?? false;

    final isSet = await backend.isMasterPasswordSet();
    if (!isSet) {
      if (appLockEnabled || setupRequired) {
        return const _GateBootstrapResult.needsSetup();
      }

      final savedKey = await backend.loadSavedSessionKey();
      if (savedKey != null && savedKey.length == 32) {
        return _GateBootstrapResult.unlocked(savedKey);
      }

      if (savedKey != null && savedKey.length != 32) {
        await backend.clearSavedSessionKey();
      }

      final generatedKey = _createSessionKey();
      await backend.saveSessionKey(generatedKey);
      return _GateBootstrapResult.unlocked(generatedKey);
    }

    if (setupRequired) {
      await prefs.remove(_kMasterPasswordSetupRequiredPrefsKey);
    }

    if (appLockEnabled) return const _GateBootstrapResult.needsUnlock();

    final savedKey = await backend.loadSavedSessionKey();
    if (savedKey == null) return const _GateBootstrapResult.needsUnlock();

    try {
      await backend.validateKey(savedKey);
      return _GateBootstrapResult.unlocked(savedKey);
    } catch (_) {
      await backend.clearSavedSessionKey();
      return const _GateBootstrapResult.needsUnlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionKey case final key?) {
      return SessionScope(sessionKey: key, lock: _lock, child: widget.child);
    }

    _bootstrapFuture ??= _bootstrap();
    return FutureBuilder<_GateBootstrapResult>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                context.t.errors.lockGateError(error: '${snapshot.error}'),
              ),
            ),
          );
        }

        final result = snapshot.data ?? const _GateBootstrapResult.needsSetup();
        return switch (result) {
          _GateBootstrapSetup() => Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => SetupMasterPasswordPage(
                    onUnlocked: (key) => setState(() => _sessionKey = key),
                  ),
                ),
              ],
            ),
          _GateBootstrapUnlock() => Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => UnlockPage(
                    onUnlocked: (key) => setState(() => _sessionKey = key),
                  ),
                ),
              ],
            ),
          _GateBootstrapUnlocked(:final sessionKey) => SessionScope(
              sessionKey: sessionKey,
              lock: _lock,
              child: widget.child,
            ),
        };
      },
    );
  }
}

sealed class _GateBootstrapResult {
  const _GateBootstrapResult();

  const factory _GateBootstrapResult.needsSetup() = _GateBootstrapSetup;
  const factory _GateBootstrapResult.needsUnlock() = _GateBootstrapUnlock;
  factory _GateBootstrapResult.unlocked(Uint8List sessionKey) =
      _GateBootstrapUnlocked;
}

final class _GateBootstrapSetup extends _GateBootstrapResult {
  const _GateBootstrapSetup();
}

final class _GateBootstrapUnlock extends _GateBootstrapResult {
  const _GateBootstrapUnlock();
}

final class _GateBootstrapUnlocked extends _GateBootstrapResult {
  _GateBootstrapUnlocked(this.sessionKey);

  final Uint8List sessionKey;
}
