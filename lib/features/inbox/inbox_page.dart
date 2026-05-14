import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../agent_ui/agent_conversation_page.dart';
import '../chat/chat_route_scope_wrapper.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  Future<List<Conversation>>? _conversationsFuture;

  Future<List<Conversation>> _loadConversations() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final defaultTitle = context.t.inbox.defaultTitle;

    final conversations = await _withInboxStage(
      'inbox.listConversations.initial',
      () => backend.listConversations(sessionKey),
    );
    if (conversations.isNotEmpty) return conversations;

    await _withInboxStage(
      'inbox.createConversation',
      () => backend.createConversation(sessionKey, defaultTitle),
    );
    return _withInboxStage(
      'inbox.listConversations.afterCreate',
      () => backend.listConversations(sessionKey),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversationsFuture ??= _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _conversationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              context.t.errors.loadFailed(error: '${snapshot.error}'),
            ),
          );
        }

        final conversations = snapshot.data ?? const <Conversation>[];
        if (conversations.isEmpty) {
          return Center(child: Text(context.t.inbox.noConversationsYet));
        }

        return ListView.separated(
          itemCount: conversations.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final conversation = conversations[index];
            return ListTile(
              key: ValueKey('conversation_${conversation.id}'),
              title: Text(conversation.title),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => wrapPushedPageWithInheritedScopes(
                      context,
                      AgentConversationPage(
                        conversation: conversation,
                        isTabActive: true,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<T> _withInboxStage<T>(
  String stage,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(_InboxLoadStageError(stage, error), stackTrace);
  }
}

final class _InboxLoadStageError implements Exception {
  const _InboxLoadStageError(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => '$stage: $cause';
}
