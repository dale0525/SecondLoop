import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

enum EmbeddingProfilesFocusTarget {
  activeProfile,
  addProfileForm,
}

class EmbeddingProfilesPage extends StatefulWidget {
  const EmbeddingProfilesPage({
    this.focusTarget,
    this.highlightFocus = false,
    super.key,
  });

  final EmbeddingProfilesFocusTarget? focusTarget;
  final bool highlightFocus;

  @override
  State<EmbeddingProfilesPage> createState() => _EmbeddingProfilesPageState();
}

class _EmbeddingProfilesPageState extends State<EmbeddingProfilesPage> {
  final _nameController = TextEditingController(text: 'Embeddings');
  final _baseUrlController =
      TextEditingController(text: 'https://api.openai.com/v1');
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: 'multilingual-e5-small');

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _activeProfileSectionKey = GlobalKey();
  final GlobalKey _addProfileSectionKey = GlobalKey();

  bool _didRunInitialFocus = false;
  EmbeddingProfilesFocusTarget? _highlightedFocusTarget;
  Timer? _clearHighlightTimer;

  var _providerType = 'openai-compatible';
  var _busy = false;
  String? _error;
  List<EmbeddingProfile>? _profiles;

  static const _defaultNameByProvider = <String, String>{
    'openai-compatible': 'Embeddings',
  };

  static const _defaultModelByProvider = <String, String>{
    'openai-compatible': 'multilingual-e5-small',
  };

  static const _defaultBaseUrlByProvider = <String, String>{
    'openai-compatible': 'https://api.openai.com/v1',
  };

  GlobalKey _anchorKeyOf(EmbeddingProfilesFocusTarget target) {
    return switch (target) {
      EmbeddingProfilesFocusTarget.activeProfile => _activeProfileSectionKey,
      EmbeddingProfilesFocusTarget.addProfileForm => _addProfileSectionKey,
    };
  }

  EmbeddingProfilesFocusTarget _resolveFocusTarget(
    EmbeddingProfilesFocusTarget target,
  ) {
    if (target != EmbeddingProfilesFocusTarget.activeProfile) return target;
    final profiles = _profiles;
    if (profiles == null) return target;

    final hasActive = profiles.any((p) => p.isActive);
    return hasActive ? target : EmbeddingProfilesFocusTarget.addProfileForm;
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

  Future<void> _scrollToAndHighlight(
      EmbeddingProfilesFocusTarget target) async {
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
    required EmbeddingProfilesFocusTarget target,
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
    final profiles = await backend.listEmbeddingProfiles(key);
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

  Future<bool> _confirmReindex() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('embedding_profile_reindex_dialog'),
            title: Text(context.t.embeddingProfiles.reindexDialog.title),
            content: Text(context.t.embeddingProfiles.reindexDialog.message),
            actions: [
              TextButton(
                key: const ValueKey('embedding_profile_reindex_cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t.embeddingProfiles.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('embedding_profile_reindex_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context
                    .t.embeddingProfiles.reindexDialog.actions.continueLabel),
              ),
            ],
          ),
        ) ??
        false;

    return confirmed;
  }

  Future<void> _activateProfile(String profileId) async {
    if (_busy) return;

    final confirmed = await _confirmReindex();
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      await backend.setActiveEmbeddingProfile(key, profileId);
      await _loadProfiles();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProfile(EmbeddingProfile profile) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('embedding_profile_delete_dialog'),
            title: Text(context.t.embeddingProfiles.deleteDialog.title),
            content: Text(
              context.t.embeddingProfiles.deleteDialog
                  .message(name: profile.name),
            ),
            actions: [
              TextButton(
                key: const ValueKey('embedding_profile_delete_cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t.embeddingProfiles.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('embedding_profile_delete_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.t.embeddingProfiles.actions.delete),
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
      await backend.deleteEmbeddingProfile(key, profile.id);
      await _loadProfiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.embeddingProfiles.deleted),
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
      setState(() => _error = context.t.embeddingProfiles.validationError);
      return;
    }

    final confirmed = await _confirmReindex();
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      await backend.createEmbeddingProfile(
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
          content: Text(context.t.embeddingProfiles.savedActivated),
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
        title: Text(context.t.embeddingProfiles.title),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: context.t.embeddingProfiles.refreshTooltip,
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('embedding_profiles_list'),
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.t.embeddingProfiles.activeProfileHelp,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _buildFocusSection(
            target: EmbeddingProfilesFocusTarget.activeProfile,
            anchorKey: _activeProfileSectionKey,
            markerKey: const ValueKey(
              'embedding_profiles_focus_active_highlight_marker',
            ),
            child: SlSurface(
              padding: const EdgeInsets.all(12),
              child: profiles == null
                  ? const Center(child: CircularProgressIndicator())
                  : profiles.isEmpty
                      ? Text(context.t.embeddingProfiles.noProfilesYet)
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
                                    'embedding_profile_actions_${profiles[i].id}',
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
                                        'embedding_profile_delete_${profiles[i].id}',
                                      ),
                                      value: _ProfileMenuAction.delete,
                                      child: Text(
                                        context
                                            .t.embeddingProfiles.actions.delete,
                                      ),
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
            context.t.embeddingProfiles.addProfile,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildFocusSection(
            target: EmbeddingProfilesFocusTarget.addProfileForm,
            anchorKey: _addProfileSectionKey,
            markerKey:
                const ValueKey('embedding_profiles_focus_add_highlight_marker'),
            child: SlSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: context.t.embeddingProfiles.fields.name,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('embedding_provider_type'),
                    value: _providerType,
                    decoration: InputDecoration(
                      labelText: context.t.embeddingProfiles.fields.provider,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'openai-compatible',
                        child: Text(
                          context
                              .t.embeddingProfiles.providers.openaiCompatible,
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
                    key: const ValueKey('embedding_base_url'),
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText:
                          context.t.embeddingProfiles.fields.baseUrlOptional,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('embedding_model_name'),
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: context.t.embeddingProfiles.fields.modelName,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('embedding_api_key'),
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.t.embeddingProfiles.fields.apiKey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('embedding_profile_save_activate'),
                    onPressed: _busy ? null : _createProfile,
                    child:
                        Text(context.t.embeddingProfiles.actions.saveActivate),
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
