import 'package:flutter/material.dart';

import '../core/backend/app_backend.dart';
import '../core/session/session_scope.dart';
import '../features/chat/chat_page.dart';
import '../features/settings/settings_page.dart';
import '../i18n/strings.g.dart';
import '../src/rust/db.dart';

Widget buildSharedDefaultChatTab(
  BuildContext context, {
  required bool isActive,
}) {
  return _DefaultChatTab(isActive: isActive);
}

Widget buildSharedDefaultSettingsTab(
  BuildContext context, {
  required bool isActive,
}) {
  return const _DefaultSettingsTab();
}

Widget buildSharedDefaultMemoryTab(
  BuildContext context, {
  required bool isActive,
}) {
  return _DefaultAgentPlaceholderTab(
    key: const ValueKey('agent_memory_placeholder'),
    title: context.t.app.tabs.memory,
  );
}

Widget buildSharedDefaultReviewTab(
  BuildContext context, {
  required bool isActive,
}) {
  return _DefaultAgentPlaceholderTab(
    key: const ValueKey('agent_review_placeholder'),
    title: context.t.app.tabs.review,
  );
}

final class _DefaultChatTab extends StatefulWidget {
  const _DefaultChatTab({required this.isActive});

  final bool isActive;

  @override
  State<_DefaultChatTab> createState() => _DefaultChatTabState();
}

final class _DefaultChatTabState extends State<_DefaultChatTab> {
  Future<Conversation>? _conversationFuture;

  Future<Conversation> _load() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return _withHomeLoadStage(
      'home.loopHomeConversation.initial',
      () => backend.getOrCreateLoopHomeConversation(sessionKey),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversationFuture ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Conversation>(
      future: _conversationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                context.t.errors.loadFailed(error: '${snapshot.error}'),
              ),
            ),
          );
        }

        final conversation = snapshot.data;
        if (conversation == null) {
          return Scaffold(
            body: Center(
              child: Text(context.t.errors.missingLoopHomeConversation),
            ),
          );
        }
        return ChatPage(
          conversation: conversation,
          isTabActive: widget.isActive,
        );
      },
    );
  }
}

Future<T> _withHomeLoadStage<T>(
  String stage,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(_HomeLoadStageError(stage, error), stackTrace);
  }
}

final class _HomeLoadStageError implements Exception {
  const _HomeLoadStageError(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => '$stage: $cause';
}

final class _DefaultSettingsTab extends StatelessWidget {
  const _DefaultSettingsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.settings.title)),
      body: const SettingsPage(),
    );
  }
}

final class _DefaultAgentPlaceholderTab extends StatelessWidget {
  const _DefaultAgentPlaceholderTab({
    required this.title,
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(title)),
    );
  }
}
