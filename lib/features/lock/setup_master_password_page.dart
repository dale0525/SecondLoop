import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';

class SetupMasterPasswordPage extends StatefulWidget {
  const SetupMasterPasswordPage({required this.onUnlocked, super.key});

  final void Function(Uint8List sessionKey) onUnlocked;

  @override
  State<SetupMasterPasswordPage> createState() =>
      _SetupMasterPasswordPageState();
}

class _SetupMasterPasswordPageState extends State<SetupMasterPasswordPage> {
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

  Future<void> _submit() async {
    if (_busy) return;

    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty) {
      setState(() => _error = 'Master password required');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = await backend.initMasterPassword(password);

      final autoUnlock = await backend.readAutoUnlockEnabled();
      if (autoUnlock) {
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
      appBar: AppBar(title: const Text('Set master password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Master password required'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('setup_password'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Master password',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('setup_confirm_password'),
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('setup_continue'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Creating…' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
