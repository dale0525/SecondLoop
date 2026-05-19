import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings.g.dart';
import '../backend/app_backend.dart';
import '../sync/sync_key_manager.dart';
import 'session_scope.dart';

class SessionBootstrap extends StatefulWidget {
  const SessionBootstrap({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<SessionBootstrap> createState() => _SessionBootstrapState();
}

class _SessionBootstrapState extends State<SessionBootstrap> {
  Future<Uint8List>? _sessionFuture;

  static const _legacyAppLockPrefsKeys = <String>[
    'app_lock_enabled_v1',
    'biometric_unlock_enabled_v1',
    'master_password_setup_required_v1',
  ];

  Future<Uint8List> _load() async {
    final key = await AppBackendScope.of(context).ensureSessionKey();
    final prefs = await SharedPreferences.getInstance();
    for (final prefsKey in _legacyAppLockPrefsKeys) {
      await prefs.remove(prefsKey);
    }
    return key;
  }

  void _refreshSession() {
    SyncKeyManager.setSessionKey(null);
    setState(() => _sessionFuture = _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionFuture ??= _load();
  }

  @override
  void dispose() {
    SyncKeyManager.setSessionKey(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                context.t.errors.initFailed(error: '${snapshot.error}'),
              ),
            ),
          );
        }

        final sessionKey = snapshot.data;
        if (sessionKey == null || sessionKey.length != 32) {
          return Scaffold(
            body: Center(
              child: Text(
                context.t.errors.initFailed(error: 'invalid_session_key'),
              ),
            ),
          );
        }

        SyncKeyManager.setSessionKey(sessionKey);
        return SessionScope(
          sessionKey: sessionKey,
          lock: _refreshSession,
          child: widget.child,
        );
      },
    );
  }
}
