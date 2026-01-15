import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../src/rust/db.dart';

class SemanticSearchDebugPage extends StatefulWidget {
  const SemanticSearchDebugPage({super.key});

  @override
  State<SemanticSearchDebugPage> createState() => _SemanticSearchDebugPageState();
}

class _SemanticSearchDebugPageState extends State<SemanticSearchDebugPage> {
  final _queryController = TextEditingController();

  var _topK = 10;
  var _busy = false;
  String? _error;
  List<SimilarMessage>? _results;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
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
      final processed = await backend.processPendingMessageEmbeddings(key, limit: 1024);
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
      final rebuilt = await backend.rebuildMessageEmbeddings(key, batchLimit: 1024);
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
      final results = await backend.searchSimilarMessages(key, query, topK: _topK);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: const Text('Semantic Search (Debug)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                      onChanged: _busy ? null : (v) => setState(() => _topK = v ?? 10),
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
                      child: const Text('Rebuild index'),
                    ),
                  ],
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

