import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({
    required this.onUnlocked,
    this.authenticateBiometrics,
    super.key,
  });

  final void Function(Uint8List sessionKey) onUnlocked;
  final Future<bool> Function()? authenticateBiometrics;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kBiometricUnlockEnabledPrefsKey = 'biometric_unlock_enabled_v1';

  final _passwordController = TextEditingController();

  bool? _biometricUnlockEnabled;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUnlockPrefs();
  }

  bool _defaultSystemUnlockEnabled() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<void> _loadUnlockPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
        _defaultSystemUnlockEnabled();
    if (!mounted) return;
    setState(() => _biometricUnlockEnabled = enabled);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Master password required');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = await backend.unlockWithPassword(password);

      final prefs = await SharedPreferences.getInstance();
      final appLockEnabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;

      final systemUnlockEnabled =
          prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
              _defaultSystemUnlockEnabled();
      final shouldPersist = !appLockEnabled || systemUnlockEnabled;

      if (shouldPersist) {
        await backend.saveSessionKey(key);
      } else {
        await backend.clearSavedSessionKey();
      }

      widget.onUnlocked(key);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitBiometricUnlock() async {
    if (_busy) return;
    final authenticate = widget.authenticateBiometrics ??
        () async {
          final auth = LocalAuthentication();
          final canCheck = await auth.canCheckBiometrics;
          final supported = await auth.isDeviceSupported();
          if (!canCheck && !supported) return false;
          final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android;
          return auth.authenticate(
            localizedReason: 'Unlock SecondLoop',
            options: AuthenticationOptions(
              biometricOnly: isMobile,
              stickyAuth: true,
            ),
          );
        };

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final ok = await authenticate();
      if (!ok) return;

      final savedKey = await backend.loadSavedSessionKey();
      if (savedKey == null || savedKey.length != 32) {
        if (!mounted) return;
        setState(() => _error =
            'Missing saved session key. Unlock with master password once.');
        return;
      }

      await backend.validateKey(savedKey);
      widget.onUnlocked(savedKey);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biometricEnabled = _biometricUnlockEnabled ?? false;
    final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    final showSystemUnlock = biometricEnabled && (isMobile || isDesktop);
    final systemUnlockLabel = isMobile ? 'Use biometrics' : 'Use system unlock';
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const ValueKey('unlock_password'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Master password'),
            ),
            if (showSystemUnlock) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _busy ? null : _submitBiometricUnlock,
                child: Text(systemUnlockLabel),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('unlock_continue'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Unlocking…' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
