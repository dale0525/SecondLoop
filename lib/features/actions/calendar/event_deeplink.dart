class EventDeepLink {
  const EventDeepLink({required this.eventId});

  final String eventId;
}

EventDeepLink? parseEventDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'event') return null;

  final eventId = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
  if (eventId.isEmpty) return null;

  return EventDeepLink(eventId: eventId);
}
