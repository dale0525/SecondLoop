import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_connection_store.dart';
import '../../core/cloud/runtime_manifest.dart';
import '../../core/cloud/runtime_profile.dart';
import '../../i18n/strings.g.dart';
import 'cloud_account_page.dart';
import 'self_managed_setup_page.dart';
import 'settings_ui.dart';

class CloudRuntimeModePage extends StatelessWidget {
  const CloudRuntimeModePage({
    super.key,
    this.connectionStore,
  });

  final RuntimeConnectionStore? connectionStore;

  @override
  Widget build(BuildContext context) {
    return SettingsPageShell(
      key: const ValueKey('runtime_mode_page_root'),
      title: context.t.settings.runtimeMode.title,
      children: [
        CloudRuntimeModePanel(connectionStore: connectionStore),
      ],
    );
  }
}

class CloudRuntimeModePanel extends StatelessWidget {
  const CloudRuntimeModePanel({
    super.key,
    this.connectionStore,
    this.onOpenSelfManaged,
    this.onOpenManagedPro,
  });

  final RuntimeConnectionStore? connectionStore;
  final VoidCallback? onOpenSelfManaged;
  final VoidCallback? onOpenManagedPro;

  @override
  Widget build(BuildContext context) {
    final store = connectionStore ?? RuntimeConnectionStore();
    return FutureBuilder<CloudRuntimeConnection?>(
      future: store.loadConnection(),
      builder: (context, snapshot) {
        final connection = _effectiveConnection(context, snapshot.data);
        final isManagedPro =
            connection?.profile.runtimeMode == CloudRuntimeMode.managedPro;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsSection(
              title: context.t.settings.runtimeMode.subtitle,
              children: [
                SettingsRow(
                  key: const ValueKey('runtime_mode_self_managed'),
                  leading: const Icon(Icons.dns_rounded),
                  title:
                      context.t.settings.runtimeMode.options.selfManaged.title,
                  body: connection?.profile.runtimeMode ==
                          CloudRuntimeMode.selfManaged
                      ? context.t.settings.runtimeMode.status.selfManagedReady
                      : context.t.settings.runtimeMode.options.selfManaged
                          .description,
                  showChevron: true,
                  onTap: onOpenSelfManaged ??
                      () {
                        final selfManagedConnection =
                            connection?.profile.runtimeMode ==
                                    CloudRuntimeMode.selfManaged
                                ? connection
                                : null;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SelfManagedSetupPage(
                              initialConnection: selfManagedConnection,
                            ),
                          ),
                        );
                      },
                ),
                SettingsRow(
                  key: const ValueKey('runtime_mode_managed_pro'),
                  leading: const Icon(Icons.cloud_done_rounded),
                  title:
                      context.t.settings.runtimeMode.options.managedPro.title,
                  body: connection?.profile.runtimeMode ==
                          CloudRuntimeMode.managedPro
                      ? context.t.settings.runtimeMode.status.managedProReady
                      : context.t.settings.runtimeMode.options.managedPro
                          .description,
                  showChevron: true,
                  onTap: onOpenManagedPro ??
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CloudAccountPage(),
                          ),
                        );
                      },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _runtimeDetailsTitle(context, connection),
                        key: const ValueKey('runtime_mode_status_title'),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (connection == null)
                        Text(
                            context.t.settings.runtimeMode.status.notConfigured)
                      else if (isManagedPro)
                        Text(context.t.settings.runtimeMode.options.managedPro
                            .description)
                      else ...[
                        Text(connection.profile.apiBaseUrl),
                        Text(connection.profile.authMode.wireValue),
                        Text(
                          context.t.settings.runtimeMode.details
                              .manifestVersionValue(
                            value: connection.manifest.manifestVersion,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String _runtimeDetailsTitle(
  BuildContext context,
  CloudRuntimeConnection? connection,
) {
  if (connection == null) {
    return context.t.settings.runtimeMode.status.notConfigured;
  }
  return connection.profile.runtimeMode == CloudRuntimeMode.managedPro
      ? context.t.settings.runtimeMode.options.managedPro.title
      : context.t.settings.runtimeMode.details.selfManagedConnection;
}

CloudRuntimeConnection? _effectiveConnection(
  BuildContext context,
  CloudRuntimeConnection? storedConnection,
) {
  if (storedConnection != null) {
    return storedConnection;
  }

  final cloudScope = CloudAuthScope.maybeOf(context);
  final uid = cloudScope?.controller.uid?.trim() ?? '';
  final apiBaseUrl = cloudScope?.gatewayConfig.baseUrl.trim() ?? '';
  if (uid.isEmpty || apiBaseUrl.isEmpty) {
    return null;
  }

  return CloudRuntimeConnection(
    profile: CloudRuntimeProfile(
      runtimeMode: CloudRuntimeMode.managedPro,
      apiBaseUrl: apiBaseUrl,
      authMode: CloudRuntimeAuthMode.hostedSession,
      authToken: '',
      capabilityManifestId: 'managed-pro-runtime',
      manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    ),
    manifest: CloudRuntimeManifest(
      manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
      runtimeMode: CloudRuntimeMode.managedPro,
      apiBaseUrl: apiBaseUrl,
      authMode: CloudRuntimeAuthMode.hostedSession,
      capabilities: CloudRuntimeRequiredCapabilities.all,
    ),
  );
}
