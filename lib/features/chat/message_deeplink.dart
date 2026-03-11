class MessageDeepLink {
  const MessageDeepLink({required this.messageId});

  final String messageId;
}

MessageDeepLink? parseMessageDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'message') return null;

  final messageId =
      uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
  if (messageId.isEmpty) return null;

  return MessageDeepLink(messageId: messageId);
}
