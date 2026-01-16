import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
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
      setState(() => _error = 'Name, API key, and model name are required.');
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
        const SnackBar(content: Text('LLM profile saved and activated')),
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
        title: const Text('LLM Profiles'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Active profile is used for Ask AI.'),
          const SizedBox(height: 12),
          if (profiles == null)
            const Center(child: CircularProgressIndicator())
          else if (profiles.isEmpty)
            const Text('No profiles yet.')
          else
            ...profiles.map(
              (p) => RadioListTile<String>(
                value: p.id,
                groupValue: activeId,
                onChanged: _busy
                    ? null
                    : (v) => v == null ? null : _activateProfile(v),
                title: Text(p.name),
                subtitle: Text(
                  '${p.providerType} • ${p.modelName}${p.baseUrl == null ? '' : ' • ${p.baseUrl}'}',
                ),
              ),
            ),
          const Divider(height: 32),
          const Text(
            'Add profile',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Model name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _createProfile,
            child: const Text('Save & Activate'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
