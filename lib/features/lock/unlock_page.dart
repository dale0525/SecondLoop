import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({required this.onUnlocked, super.key});

  final void Function(Uint8List sessionKey) onUnlocked;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _passwordController = TextEditingController();

  bool _busy = false;
  String? _error;

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

      final autoUnlock = await backend.readAutoUnlockEnabled();
      if (autoUnlock) {
        await backend.saveSessionKey(key);
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
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
