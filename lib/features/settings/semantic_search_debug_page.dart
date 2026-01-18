import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../src/rust/db.dart';

class SemanticSearchDebugPage extends StatefulWidget {
  const SemanticSearchDebugPage({super.key});

  @override
  State<SemanticSearchDebugPage> createState() =>
      _SemanticSearchDebugPageState();
}

class _SemanticSearchDebugPageState extends State<SemanticSearchDebugPage> {
  final _queryController = TextEditingController();

  var _topK = 10;
  var _busy = false;
  String? _error;
  String? _modelStatus;
  List<String>? _embeddingModels;
  String? _activeEmbeddingModel;
  String? _selectedEmbeddingModel;
  List<SimilarMessage>? _results;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmbeddingModels());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadEmbeddingModels() async {
    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      final models = await backend.listEmbeddingModelNames(key);
      final active = await backend.getActiveEmbeddingModelName(key);
      if (!mounted) return;
      setState(() {
        _embeddingModels = models;
        _activeEmbeddingModel = active;
        _selectedEmbeddingModel =
            models.contains(active) ? active : (models.isEmpty ? null : models.first);
      });
    } catch (e) {
      if (mounted) setState(() => _modelStatus = '$e');
    }
  }

  Future<void> _applySelectedModel() async {
    if (_busy) return;
    final selected = _selectedEmbeddingModel;
    if (selected == null || selected.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      final changed = await backend.setActiveEmbeddingModelName(key, selected);
      await _loadEmbeddingModels();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? 'Switched embedding model; re-index pending'
                : 'Embedding model already active',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _processPending() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      final processed =
          await backend.processPendingMessageEmbeddings(key, limit: 1024);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processed $processed pending embeddings')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuildIndex() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      final rebuilt =
          await backend.rebuildMessageEmbeddings(key, batchLimit: 1024);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rebuilt embeddings for $rebuilt messages')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    if (_busy) return;
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final backend = AppBackendScope.of(context);
      final key = SessionScope.of(context).sessionKey;
      await _prepareEmbeddingsForSearch(backend, key);
      final results =
          await backend.searchSimilarMessages(key, query, topK: _topK);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareEmbeddingsForSearch(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    final status = ValueNotifier<String>('Preparing semantic search…');
    var dialogShown = false;

    final showTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            content: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (context, value, child) {
                return Row(
                  children: [
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(value)),
                  ],
                );
              },
            ),
          );
        },
      );
    });

    try {
      var totalProcessed = 0;
      while (true) {
        final processed = await backend.processPendingMessageEmbeddings(
          sessionKey,
          limit: 256,
        );
        if (processed <= 0) break;
        totalProcessed += processed;
        status.value = 'Indexing messages… ($totalProcessed indexed)';
      }
    } finally {
      showTimer.cancel();
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      status.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final models = _embeddingModels;
    final activeModel = _activeEmbeddingModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Semantic Search (Debug)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activeModel == null
                            ? 'Embedding model: (loading...)'
                            : 'Embedding model: $activeModel',
                      ),
                    ),
                    if (models != null && models.isNotEmpty) ...[
                      DropdownButton<String>(
                        value: _selectedEmbeddingModel,
                        items: models
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _selectedEmbeddingModel = v),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _busy ? null : _applySelectedModel,
                        child: const Text('Use model'),
                      ),
                    ],
                  ],
                ),
                if (_modelStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _modelStatus!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Query',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Top‑K:'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _topK,
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 5, child: Text('5')),
                        DropdownMenuItem(value: 10, child: Text('10')),
                        DropdownMenuItem(value: 20, child: Text('20')),
                      ],
                      onChanged:
                          _busy ? null : (v) => setState(() => _topK = v ?? 10),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _busy ? null : _search,
                      child: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _processPending,
                      child: const Text('Process pending'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _rebuildIndex,
                      child: const Text('Rebuild embeddings'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: results == null
                ? const Center(child: Text('Run a search to see results'))
                : results.isEmpty
                    ? const Center(child: Text('No results'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return ListTile(
                            title: Text(item.message.content),
                            subtitle: Text(
                              'distance=${item.distance.toStringAsFixed(4)} • role=${item.message.role} • convo=${item.message.conversationId}',
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
