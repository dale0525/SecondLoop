enum WebEntryIntent {
  open,
  subscribe,
  manage,
}

WebEntryIntent parseWebEntryIntent(Uri uri) {
  final rawIntent = uri.queryParameters['intent']?.trim().toLowerCase() ?? '';
  switch (rawIntent) {
    case 'subscribe':
      return WebEntryIntent.subscribe;
    case 'manage':
      return WebEntryIntent.manage;
    case 'open':
    default:
      return WebEntryIntent.open;
  }
}
