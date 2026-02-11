import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'byok_usage_card.dart';

enum LlmProfilesFocusTarget {
  activeProfile,
  addProfileForm,
}

class LlmProfilesPage extends StatefulWidget {
  const LlmProfilesPage({
    this.focusTarget,
    this.highlightFocus = false,
    super.key,
  });

  final LlmProfilesFocusTarget? focusTarget;
  final bool highlightFocus;

  @override
  State<LlmProfilesPage> createState() => _LlmProfilesPageState();
}

class _LlmProfilesPageState extends State<LlmProfilesPage> {
  final _nameController = TextEditingController(text: 'OpenAI');
  final _baseUrlController =
      TextEditingController(text: 'https://api.openai.com/v1');
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: 'gpt-4o-mini');

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _activeProfileSectionKey = GlobalKey();
  final GlobalKey _addProfileSectionKey = GlobalKey();

  bool _didRunInitialFocus = false;
  LlmProfilesFocusTarget? _highlightedFocusTarget;
  Timer? _clearHighlightTimer;

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

  GlobalKey _anchorKeyOf(LlmProfilesFocusTarget target) {
    return switch (target) {
      LlmProfilesFocusTarget.activeProfile => _activeProfileSectionKey,
      LlmProfilesFocusTarget.addProfileForm => _addProfileSectionKey,
    };
  }

  LlmProfilesFocusTarget _resolveFocusTarget(LlmProfilesFocusTarget target) {
    if (target != LlmProfilesFocusTarget.activeProfile) return target;
    final profiles = _profiles;
    if (profiles == null) return target;

    final hasActive = profiles.any((p) => p.isActive);
    return hasActive ? target : LlmProfilesFocusTarget.addProfileForm;
  }

  void _scheduleInitialFocus() {
    if (_didRunInitialFocus) return;
    final focusTarget = widget.focusTarget;
    if (focusTarget == null) return;
    _didRunInitialFocus = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToAndHighlight(focusTarget));
    });
  }

  Future<void> _scrollToAndHighlight(LlmProfilesFocusTarget target) async {
    if (!mounted) return;

    final resolvedTarget = _resolveFocusTarget(target);
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;

    final targetContext = _anchorKeyOf(resolvedTarget).currentContext;
    if (targetContext == null) {
      if (widget.highlightFocus && mounted) {
        _clearHighlightTimer?.cancel();
        setState(() => _highlightedFocusTarget = resolvedTarget);
        if (!disableAnimations) {
          _clearHighlightTimer = Timer(const Duration(milliseconds: 1400), () {
            if (!mounted || _highlightedFocusTarget != resolvedTarget) return;
            setState(() => _highlightedFocusTarget = null);
          });
        }
      }
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );

    if (!mounted || !widget.highlightFocus) return;

    _clearHighlightTimer?.cancel();
    setState(() => _highlightedFocusTarget = resolvedTarget);
    if (disableAnimations) return;

    _clearHighlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || _highlightedFocusTarget != resolvedTarget) return;
      setState(() => _highlightedFocusTarget = null);
    });
  }

  Widget _buildFocusSection({
    required LlmProfilesFocusTarget target,
    required GlobalKey anchorKey,
    required Key markerKey,
    required Widget child,
  }) {
    final highlighted = _highlightedFocusTarget == target;
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: anchorKey,
      child: AnimatedContainer(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? colorScheme.primary : Colors.transparent,
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.18),
                    blurRadius: 18,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            child,
            if (highlighted) SizedBox.shrink(key: markerKey),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.highlightFocus && widget.focusTarget != null) {
      _highlightedFocusTarget = widget.focusTarget;
    }
  }

  @override
  void dispose() {
    _clearHighlightTimer?.cancel();
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _scrollController.dispose();
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
        SnackBar(
          content: Text(context.t.llmProfiles.deleted),
          duration: const Duration(seconds: 3),
        ),
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
        SnackBar(
          content: Text(context.t.llmProfiles.savedActivated),
          duration: const Duration(seconds: 3),
        ),
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
    _scheduleInitialFocus();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    String? activeId;
    LlmProfile? activeProfile;
    if (profiles != null) {
      for (final p in profiles) {
        if (p.isActive) {
          activeId = p.id;
          activeProfile = p;
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
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.t.llmProfiles.activeProfileHelp,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (activeProfile != null) ...[
            ByokUsageCard(activeProfile: activeProfile),
            const SizedBox(height: 12),
          ],
          _buildFocusSection(
            target: LlmProfilesFocusTarget.activeProfile,
            anchorKey: _activeProfileSectionKey,
            markerKey:
                const ValueKey('llm_profiles_focus_active_highlight_marker'),
            child: SlSurface(
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
          _buildFocusSection(
            target: LlmProfilesFocusTarget.addProfileForm,
            anchorKey: _addProfileSectionKey,
            markerKey:
                const ValueKey('llm_profiles_focus_add_highlight_marker'),
            child: SlSurface(
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
          ),
        ],
      ),
    );
  }
}

enum _ProfileMenuAction {
  delete,
}
