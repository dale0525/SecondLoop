import 'package:flutter/material.dart';

import '../core/cloud/runtime_connection_store.dart';
import '../core/cloud/runtime_profile.dart';

final class AppShellRuntimeStatusPill extends StatelessWidget {
  const AppShellRuntimeStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudRuntimeConnection?>(
      future: _loadConnection(),
      initialData: RuntimeConnectionStore.cachedConnection,
      builder: (context, snapshot) {
        return _RuntimeStatusPill(label: _label(snapshot.data));
      },
    );
  }
}

final class _RuntimeStatusPill extends StatelessWidget {
  const _RuntimeStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF316BF3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFEFCFF),
            fontSize: 11,
            height: 14 / 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

Future<CloudRuntimeConnection?> _loadConnection() async {
  try {
    return await RuntimeConnectionStore().loadConnection();
  } catch (_) {
    return RuntimeConnectionStore.cachedConnection;
  }
}

String _label(CloudRuntimeConnection? connection) {
  return connection?.profile.runtimeMode == CloudRuntimeMode.selfManaged
      ? 'Self-managed'
      : 'Managed Pro';
}
