import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

class LlmProfilesPage extends StatefulWidget {
  const LlmProfilesPage({super.key});

  @override
  State<LlmProfilesPage> createState() => _LlmProfilesPageState();
}

class _LlmProfilesPageState extends State<LlmProfilesPage> {
  final _nameController = TextEditingController(text: 'OpenAI');
  final _baseUrlController =
      TextEditingController(text: 'https://api.openai.com/v1');
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: 'gpt-4o-mini');

  var _providerType = 'openai-compatible';
  var _busy = false;
  String? _error;
  List<LlmProfile>? _profiles;

  static const _defaultNameByProvider = <String, String>{
    'openai-compatible': 'OpenAI',
    'gemini-compatible': 'Gemini',
    'anthropic-compatible': 'Anthropic',
  };

  static const _defaultModelByProvider = <String, String>{
    'openai-compatible': 'gpt-4o-mini',
    'gemini-compatible': 'gemini-1.5-flash',
    'anthropic-compatible': 'claude-3-5-sonnet-20240620',
  };

  static const _defaultBaseUrlByProvider = <String, String>{
    'openai-compatible': 'https://api.openai.com/v1',
    'gemini-compatible': 'https://generativelanguage.googleapis.com/v1beta',
    'anthropic-compatible': 'https://api.anthropic.com/v1',
  };

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final backend = AppBackendScope.of(context);
    final key = SessionScope.of(context).sessionKey;
    final profiles = await backend.listLlmProfiles(key);
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _loadProfiles();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activateProfile(String profileId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      await backend.setActiveLlmProfile(key, profileId);
      await _loadProfiles();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProfile(LlmProfile profile) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('llm_profile_delete_dialog'),
            title: Text(context.t.llmProfiles.deleteDialog.title),
            content: Text(
              context.t.llmProfiles.deleteDialog.message(name: profile.name),
            ),
            actions: [
              TextButton(
                key: const ValueKey('llm_profile_delete_cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t.llmProfiles.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('llm_profile_delete_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.t.llmProfiles.actions.delete),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      await backend.deleteLlmProfile(key, profile.id);
      await _loadProfiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.llmProfiles.deleted)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createProfile() async {
    if (_busy) return;

    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final modelName = _modelController.text.trim();

    if (name.isEmpty || modelName.isEmpty || apiKey.isEmpty) {
      setState(() => _error = context.t.llmProfiles.validationError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      await backend.createLlmProfile(
        key,
        name: name,
        providerType: _providerType,
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
        apiKey: apiKey,
        modelName: modelName,
        setActive: true,
      );
      _apiKeyController.clear();
      await _loadProfiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.llmProfiles.savedActivated)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profiles == null) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    String? activeId;
    if (profiles != null) {
      for (final p in profiles) {
        if (p.isActive) {
          activeId = p.id;
          break;
        }
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.llmProfiles.title),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: context.t.llmProfiles.refreshTooltip,
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('llm_profiles_list'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.t.llmProfiles.activeProfileHelp,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SlSurface(
            padding: const EdgeInsets.all(12),
            child: profiles == null
                ? const Center(child: CircularProgressIndicator())
                : profiles.isEmpty
                    ? Text(context.t.llmProfiles.noProfilesYet)
                    : Column(
                        children: [
                          for (var i = 0; i < profiles.length; i++) ...[
                            if (i != 0) const Divider(height: 1),
                            RadioListTile<String>(
                              value: profiles[i].id,
                              groupValue: activeId,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                      v == null ? null : _activateProfile(v),
                              title: Text(profiles[i].name),
                              subtitle: Text(
                                [
                                  profiles[i].providerType,
                                  profiles[i].modelName,
                                  if (profiles[i].baseUrl != null &&
                                      profiles[i].baseUrl!.isNotEmpty)
                                    profiles[i].baseUrl!,
                                ].join(' • '),
                              ),
                              secondary: PopupMenuButton<_ProfileMenuAction>(
                                key: ValueKey(
                                  'llm_profile_actions_${profiles[i].id}',
                                ),
                                enabled: !_busy,
                                onSelected: (action) async {
                                  switch (action) {
                                    case _ProfileMenuAction.delete:
                                      await _deleteProfile(profiles[i]);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem<_ProfileMenuAction>(
                                    key: ValueKey(
                                      'llm_profile_delete_${profiles[i].id}',
                                    ),
                                    value: _ProfileMenuAction.delete,
                                    child: Text(
                                        context.t.llmProfiles.actions.delete),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
          const SizedBox(height: 16),
          Text(
            context.t.llmProfiles.addProfile,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SlSurface(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: context.t.llmProfiles.fields.name,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('llm_provider_type'),
                  value: _providerType,
                  decoration: InputDecoration(
                    labelText: context.t.llmProfiles.fields.provider,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'openai-compatible',
                      child: Text(
                        context.t.llmProfiles.providers.openaiCompatible,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'gemini-compatible',
                      child: Text(
                          context.t.llmProfiles.providers.geminiCompatible),
                    ),
                    DropdownMenuItem(
                      value: 'anthropic-compatible',
                      child: Text(
                        context.t.llmProfiles.providers.anthropicCompatible,
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            final oldProviderType = _providerType;
                            _providerType = v;

                            final oldDefaultModel =
                                _defaultModelByProvider[oldProviderType];
                            final newDefaultModel =
                                _defaultModelByProvider[_providerType];
                            if (newDefaultModel != null) {
                              final modelText = _modelController.text.trim();
                              if (modelText.isEmpty ||
                                  modelText == oldDefaultModel) {
                                _modelController.text = newDefaultModel;
                              }
                            }

                            final oldDefaultName =
                                _defaultNameByProvider[oldProviderType];
                            final newDefaultName =
                                _defaultNameByProvider[_providerType];
                            if (newDefaultName != null) {
                              final nameText = _nameController.text.trim();
                              if (nameText.isEmpty ||
                                  nameText == oldDefaultName) {
                                _nameController.text = newDefaultName;
                              }
                            }

                            final oldDefaultBaseUrl =
                                _defaultBaseUrlByProvider[oldProviderType];
                            final newDefaultBaseUrl =
                                _defaultBaseUrlByProvider[_providerType];
                            if (newDefaultBaseUrl != null) {
                              final baseUrlText =
                                  _baseUrlController.text.trim();
                              if (baseUrlText.isEmpty ||
                                  baseUrlText == oldDefaultBaseUrl) {
                                _baseUrlController.text = newDefaultBaseUrl;
                              }
                            }
                          });
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('llm_base_url'),
                  controller: _baseUrlController,
                  decoration: InputDecoration(
                    labelText: context.t.llmProfiles.fields.baseUrlOptional,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('llm_model_name'),
                  controller: _modelController,
                  decoration: InputDecoration(
                    labelText: context.t.llmProfiles.fields.modelName,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.t.llmProfiles.fields.apiKey,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('llm_profile_save_activate'),
                  onPressed: _busy ? null : _createProfile,
                  child: Text(context.t.llmProfiles.actions.saveActivate),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ProfileMenuAction {
  delete,
}
