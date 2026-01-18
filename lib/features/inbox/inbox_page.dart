import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../chat/chat_page.dart';
import '../../src/rust/db.dart';

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

    final conversations = await backend.listConversations(sessionKey);
    if (conversations.isNotEmpty) return conversations;

    await backend.createConversation(sessionKey, defaultTitle);
    return backend.listConversations(sessionKey);
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
                    builder: (_) => ChatPage(conversation: conversation),
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
