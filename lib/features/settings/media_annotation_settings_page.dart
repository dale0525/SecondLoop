import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'cloud_account_page.dart';
import 'llm_profiles_page.dart';

class MediaAnnotationSettingsPage extends StatefulWidget {
  const MediaAnnotationSettingsPage({
    super.key,
    this.configStore,
  });

  final MediaAnnotationConfigStore? configStore;

  static const annotateSwitchKey =
      ValueKey('media_annotation_settings_annotate_switch');
  static const searchSwitchKey =
      ValueKey('media_annotation_settings_search_switch');
  static const searchConfirmDialogKey =
      ValueKey('media_annotation_settings_search_confirm_dialog');
  static const searchConfirmCancelKey =
      ValueKey('media_annotation_settings_search_confirm_cancel');
  static const searchConfirmContinueKey =
      ValueKey('media_annotation_settings_search_confirm_continue');

  @override
  State<MediaAnnotationSettingsPage> createState() =>
      _MediaAnnotationSettingsPageState();
}

class _MediaAnnotationSettingsPageState
    extends State<MediaAnnotationSettingsPage> {
  static const _kProviderFollowAskAi = 'follow_ask_ai';
  static const _kProviderCloudGateway = 'cloud_gateway';
  static const _kProviderByokProfile = 'byok_profile';

  bool _didKickoffLoad = false;
  MediaAnnotationConfig? _config;
  List<LlmProfile>? _llmProfiles;
  Object? _loadError;
  bool _busy = false;

  MediaAnnotationConfigStore get _store =>
      widget.configStore ?? const RustMediaAnnotationConfigStore();

  Future<void> _showSetupRequiredDialog({
    required String reason,
    Future<void> Function()? onOpen,
  }) async {
    final t = context.t.settings.mediaAnnotation.setupRequired;
    final body = [t.body, reason].join('\n\n');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.notNow),
            ),
            if (onOpen != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(onOpen());
                },
                child: Text(context.t.common.actions.open),
              ),
          ],
        );
      },
    );
  }

  Future<String?> _promptOpenAiCompatibleProfileId() async {
    final t = context.t.settings.mediaAnnotation.byokProfile;
    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.missingBackend),
          duration: const Duration(seconds: 3),
        ),
      );
      return null;
    }

    final profiles = await backend
        .listLlmProfiles(sessionKey)
        .catchError((_) => <LlmProfile>[]);
    if (!mounted) return null;

    final openAiCompatible = profiles
        .where((p) => p.providerType == 'openai-compatible')
        .toList(growable: false);
    if (openAiCompatible.isEmpty) {
      await _showSetupRequiredDialog(
        reason: context.t.settings.mediaAnnotation.setupRequired.reasons
            .byokOpenAiCompatible,
        onOpen: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
          );
        },
      );
      return null;
    }

    final selectedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(t.title),
          children: [
            for (final p in openAiCompatible)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(p.id),
                child: Text(p.name),
              ),
          ],
        );
      },
    );
    if (!mounted) return null;
    return selectedId;
  }

  Future<MediaAnnotationConfig?> _prepareEnableAnnotateConfig(
    MediaAnnotationConfig config,
  ) async {
    final desiredMode = config.providerMode.trim();

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final gatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

    final hasGateway = gatewayConfig.baseUrl.trim().isNotEmpty;
    String? idToken;
    if (subscriptionStatus == SubscriptionStatus.entitled) {
      try {
        idToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        idToken = null;
      }
    }
    final hasIdToken = (idToken?.trim() ?? '').isNotEmpty;
    if (!mounted) return null;

    if (desiredMode == _kProviderCloudGateway) {
      if (!hasGateway) {
        await _showSetupRequiredDialog(
          reason: context.t.settings.mediaAnnotation.setupRequired.reasons
              .cloudUnavailable,
        );
        return null;
      }
      if (subscriptionStatus != SubscriptionStatus.entitled) {
        await _showSetupRequiredDialog(
          reason: context.t.settings.mediaAnnotation.setupRequired.reasons
              .cloudRequiresPro,
          onOpen: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CloudAccountPage()),
            );
          },
        );
        return null;
      }
      if (!hasIdToken) {
        await _showSetupRequiredDialog(
          reason: context
              .t.settings.mediaAnnotation.setupRequired.reasons.cloudSignIn,
          onOpen: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CloudAccountPage()),
            );
          },
        );
        return null;
      }
      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      );
    }

    if (desiredMode == _kProviderByokProfile) {
      final byokId = config.byokProfileId?.trim();
      final cachedProfiles = _llmProfiles ?? const <LlmProfile>[];
      var hasValidSelected = false;
      if (byokId != null && byokId.isNotEmpty) {
        for (final p in cachedProfiles) {
          if (p.id == byokId && p.providerType == 'openai-compatible') {
            hasValidSelected = true;
            break;
          }
        }
      }

      var resolvedId = byokId;
      if (!hasValidSelected) {
        resolvedId = await _promptOpenAiCompatibleProfileId();
        final trimmed = resolvedId?.trim();
        if (trimmed == null || trimmed.isEmpty) return null;
        resolvedId = trimmed;
      }

      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: resolvedId,
        cloudModelName: config.cloudModelName,
      );
    }

    final canUseCloud = subscriptionStatus == SubscriptionStatus.entitled &&
        hasGateway &&
        hasIdToken;
    if (canUseCloud) {
      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      );
    }

    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;

    List<LlmProfile> profiles = _llmProfiles ?? const <LlmProfile>[];
    if (profiles.isEmpty && backend != null) {
      profiles =
          await backend.listLlmProfiles(sessionKey).catchError((_) => profiles);
    }
    if (!mounted) return null;

    LlmProfile? active;
    for (final p in profiles) {
      if (p.isActive) {
        active = p;
        break;
      }
    }

    final canUseByok =
        active != null && active.providerType == 'openai-compatible';
    if (canUseByok) {
      return MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      );
    }

    await _showSetupRequiredDialog(
      reason:
          context.t.settings.mediaAnnotation.setupRequired.reasons.followAskAi,
      onOpen: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
        );
      },
    );
    return null;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didKickoffLoad) return;
    _didKickoffLoad = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final sessionKey = SessionScope.of(context).sessionKey;
    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    try {
      final config = await _store.read(sessionKey);
      List<LlmProfile>? profiles;
      if (backend != null) {
        try {
          profiles = await backend.listLlmProfiles(sessionKey);
        } catch (_) {
          profiles = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _config = config;
        _llmProfiles = profiles;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _config = null;
      });
    }
  }

  Future<void> _persist(MediaAnnotationConfig next) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    setState(() => _busy = true);
    try {
      await _store.write(sessionKey, next);
      if (!mounted) return;
      setState(() => _config = next);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmSearchToggle({required bool enabled}) async {
    final t = context.t.settings.mediaAnnotation.searchToggleConfirm;

    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              key: MediaAnnotationSettingsPage.searchConfirmDialogKey,
              title: Text(t.title),
              content: Text(
                enabled ? t.bodyEnable : t.bodyDisable,
              ),
              actions: [
                TextButton(
                  key: MediaAnnotationSettingsPage.searchConfirmCancelKey,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.t.common.actions.cancel),
                ),
                FilledButton(
                  key: MediaAnnotationSettingsPage.searchConfirmContinueKey,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(context.t.common.actions.continueLabel),
                ),
              ],
            );
          },
        )) ==
        true;
  }

  String _providerModeLabel(BuildContext context, String mode) {
    final t = context.t.settings.mediaAnnotation.providerMode.labels;
    return switch (mode) {
      _kProviderCloudGateway => t.cloudGateway,
      _kProviderByokProfile => t.byokProfile,
      _ => t.followAskAi,
    };
  }

  String? _byokProfileName(String? id) {
    final profiles = _llmProfiles;
    if (id == null || id.trim().isEmpty || profiles == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  Future<void> _pickProviderMode(MediaAnnotationConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.providerMode;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = config.providerMode;

        return AlertDialog(
          title: Text(t.title),
          content: StatefulBuilder(
            builder: (context, setInnerState) {
              Widget option({
                required String mode,
                required String title,
                required String body,
              }) {
                return RadioListTile<String>(
                  value: mode,
                  groupValue: value,
                  title: Text(title),
                  subtitle: Text(body),
                  onChanged: (next) {
                    if (next == null) return;
                    setInnerState(() => value = next);
                  },
                );
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    option(
                      mode: _kProviderFollowAskAi,
                      title: t.labels.followAskAi,
                      body: t.descriptions.followAskAi,
                    ),
                    option(
                      mode: _kProviderCloudGateway,
                      title: t.labels.cloudGateway,
                      body: t.descriptions.cloudGateway,
                    ),
                    option(
                      mode: _kProviderByokProfile,
                      title: t.labels.byokProfile,
                      body: t.descriptions.byokProfile,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(context.t.common.actions.save),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    if (selected == config.providerMode) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: selected,
        byokProfileId: config.byokProfileId,
        cloudModelName: config.cloudModelName,
      ),
    );
  }

  Future<void> _pickCloudModelName(MediaAnnotationConfig config) async {
    if (_busy) return;
    final t = context.t.settings.mediaAnnotation.cloudModelName;

    final controller = TextEditingController(text: config.cloudModelName ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: t.hint,
            ),
            textInputAction: TextInputAction.done,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(context.t.common.actions.save),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (saved == null || !mounted) return;

    final trimmed = saved.trim();
    final nextCloudModelName = trimmed.isEmpty ? null : trimmed;
    if (nextCloudModelName == config.cloudModelName) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: config.byokProfileId,
        cloudModelName: nextCloudModelName,
      ),
    );
  }

  Future<void> _pickByokProfile(MediaAnnotationConfig config) async {
    if (_busy) return;
    final selectedId = await _promptOpenAiCompatibleProfileId();
    if (selectedId == null || !mounted) return;
    if (selectedId == config.byokProfileId) return;

    await _persist(
      MediaAnnotationConfig(
        annotateEnabled: config.annotateEnabled,
        searchEnabled: config.searchEnabled,
        allowCellular: config.allowCellular,
        providerMode: config.providerMode,
        byokProfileId: selectedId,
        cloudModelName: config.cloudModelName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final t = context.t.settings.mediaAnnotation;

    Widget sectionCard(List<Widget> children) {
      return SlSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i != 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadError != null)
            SlSurface(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t.errors.loadFailed(error: '$_loadError'),
              ),
            ),
          if (config == null && _loadError == null)
            const Center(child: CircularProgressIndicator()),
          if (config != null) ...[
            sectionCard([
              SwitchListTile(
                key: MediaAnnotationSettingsPage.annotateSwitchKey,
                title: Text(t.annotateEnabled.title),
                subtitle: Text(t.annotateEnabled.subtitle),
                value: config.annotateEnabled,
                onChanged: _busy
                    ? null
                    : (value) async {
                        if (!value) {
                          await _persist(
                            MediaAnnotationConfig(
                              annotateEnabled: false,
                              searchEnabled: config.searchEnabled,
                              allowCellular: config.allowCellular,
                              providerMode: config.providerMode,
                              byokProfileId: config.byokProfileId,
                              cloudModelName: config.cloudModelName,
                            ),
                          );
                          return;
                        }

                        final prepared =
                            await _prepareEnableAnnotateConfig(config);
                        if (prepared == null || !mounted) return;
                        await _persist(prepared);
                      },
              ),
              SwitchListTile(
                key: MediaAnnotationSettingsPage.searchSwitchKey,
                title: Text(t.searchEnabled.title),
                subtitle: Text(t.searchEnabled.subtitle),
                value: config.searchEnabled,
                onChanged: _busy
                    ? null
                    : (value) async {
                        final confirmed =
                            await _confirmSearchToggle(enabled: value);
                        if (!confirmed || !mounted) return;
                        await _persist(
                          MediaAnnotationConfig(
                            annotateEnabled: config.annotateEnabled,
                            searchEnabled: value,
                            allowCellular: config.allowCellular,
                            providerMode: config.providerMode,
                            byokProfileId: config.byokProfileId,
                            cloudModelName: config.cloudModelName,
                          ),
                        );
                      },
              ),
            ]),
            const SizedBox(height: 16),
            Text(
              t.advanced.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            sectionCard([
              ListTile(
                title: Text(t.providerMode.title),
                subtitle: Text(t.providerMode.subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_providerModeLabel(context, config.providerMode)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: _busy ? null : () => _pickProviderMode(config),
              ),
              if (config.providerMode == _kProviderCloudGateway)
                ListTile(
                  title: Text(t.cloudModelName.title),
                  subtitle: Text(t.cloudModelName.subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text((config.cloudModelName ??
                              t.cloudModelName.followAskAi)
                          .trim()),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _busy ? null : () => _pickCloudModelName(config),
                ),
              if (config.providerMode == _kProviderByokProfile)
                ListTile(
                  title: Text(t.byokProfile.title),
                  subtitle: Text(t.byokProfile.subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _byokProfileName(config.byokProfileId) ??
                            t.byokProfile.unset,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _busy ? null : () => _pickByokProfile(config),
                ),
              SwitchListTile(
                title: Text(t.allowCellular.title),
                subtitle: Text(t.allowCellular.subtitle),
                value: config.allowCellular,
                onChanged: _busy
                    ? null
                    : (value) async {
                        await _persist(
                          MediaAnnotationConfig(
                            annotateEnabled: config.annotateEnabled,
                            searchEnabled: config.searchEnabled,
                            allowCellular: value,
                            providerMode: config.providerMode,
                            byokProfileId: config.byokProfileId,
                            cloudModelName: config.cloudModelName,
                          ),
                        );
                      },
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
