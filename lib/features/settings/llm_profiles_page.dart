import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';

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

  var _busy = false;
  String? _error;
  List<LlmProfile>? _profiles;

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
        providerType: 'openai-compatible',
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
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.t.llmProfiles.activeProfileHelp,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
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
                              ),
                            ],
                          ],
                        ),
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
          Card(
            child: Padding(
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
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText: context.t.llmProfiles.fields.baseUrlOptional,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
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
          ),
        ],
      ),
    );
  }
}
