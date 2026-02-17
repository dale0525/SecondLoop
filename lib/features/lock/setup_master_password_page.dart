import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';

class SetupMasterPasswordPage extends StatefulWidget {
  const SetupMasterPasswordPage({required this.onUnlocked, super.key});

  final void Function(Uint8List sessionKey) onUnlocked;

  @override
  State<SetupMasterPasswordPage> createState() =>
      _SetupMasterPasswordPageState();
}

class _SetupMasterPasswordPageState extends State<SetupMasterPasswordPage> {
  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kBiometricUnlockEnabledPrefsKey = 'biometric_unlock_enabled_v1';
  static const _kMasterPasswordSetupRequiredPrefsKey =
      'master_password_setup_required_v1';

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _defaultSystemUnlockEnabled() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<void> _submit() async {
    if (_busy) return;

    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty) {
      setState(() => _error = context.t.lock.masterPasswordRequired);
      return;
    }
    if (password != confirm) {
      setState(() => _error = context.t.lock.passwordsDoNotMatch);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = await backend.initMasterPassword(password);

      final prefs = await SharedPreferences.getInstance();
      final appLockEnabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;

      final systemUnlockEnabled =
          prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
              _defaultSystemUnlockEnabled();
      final shouldPersist = !appLockEnabled || systemUnlockEnabled;

      await prefs.remove(_kMasterPasswordSetupRequiredPrefsKey);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.lock.setupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SlSurface(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.t.lock.masterPasswordRequired,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('setup_password'),
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.t.common.fields.masterPassword,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('setup_confirm_password'),
                    controller: _confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.t.common.fields.confirm,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('setup_continue'),
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? context.t.lock.creating
                            : context.t.common.actions.continueLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
