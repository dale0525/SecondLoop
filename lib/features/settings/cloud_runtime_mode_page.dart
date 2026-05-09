import 'package:flutter/material.dart';

import '../../core/cloud/runtime_connection_store.dart';
import '../../core/cloud/runtime_profile.dart';
import '../../i18n/strings.g.dart';
import 'cloud_account_page.dart';
import 'self_managed_setup_page.dart';

class CloudRuntimeModePage extends StatelessWidget {
  const CloudRuntimeModePage({
    super.key,
    this.connectionStore,
  });

  final RuntimeConnectionStore? connectionStore;

  @override
  Widget build(BuildContext context) {
    final store = connectionStore ?? RuntimeConnectionStore();
    return Scaffold(
      key: const ValueKey('runtime_mode_page_root'),
      appBar: AppBar(
        title: Text(context.t.settings.runtimeMode.title),
      ),
      body: FutureBuilder<CloudRuntimeConnection?>(
        future: store.loadConnection(),
        builder: (context, snapshot) {
          final connection = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                key: const ValueKey('runtime_mode_self_managed'),
                title: Text(
                    context.t.settings.runtimeMode.options.selfManaged.title),
                subtitle: Text(
                  connection?.profile.runtimeMode ==
                          CloudRuntimeMode.selfManaged
                      ? context.t.settings.runtimeMode.status.selfManagedReady
                      : context.t.settings.runtimeMode.options.selfManaged
                          .description,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SelfManagedSetupPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                key: const ValueKey('runtime_mode_managed_pro'),
                title: Text(
                    context.t.settings.runtimeMode.options.managedPro.title),
                subtitle: Text(
                  connection?.profile.runtimeMode == CloudRuntimeMode.managedPro
                      ? context.t.settings.runtimeMode.status.managedProReady
                      : context.t.settings.runtimeMode.options.managedPro
                          .description,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CloudAccountPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                _runtimeDetailsTitle(context, connection),
                key: const ValueKey('runtime_mode_status_title'),
              ),
              if (connection != null) ...[
                const SizedBox(height: 8),
                Text(connection.profile.apiBaseUrl),
                Text(connection.profile.authMode.wireValue),
                Text('${connection.manifest.manifestVersion}'),
              ] else ...[
                const SizedBox(height: 8),
                Text(context.t.settings.runtimeMode.status.notConfigured),
              ],
            ],
          );
        },
      ),
    );
  }

  String _runtimeDetailsTitle(
    BuildContext context,
    CloudRuntimeConnection? connection,
  ) {
    if (connection == null) {
      return context.t.settings.runtimeMode.status.notConfigured;
    }
    return connection.profile.runtimeMode == CloudRuntimeMode.managedPro
        ? context.t.settings.runtimeMode.details.managedSession
        : context.t.settings.runtimeMode.details.selfManagedConnection;
  }
}
