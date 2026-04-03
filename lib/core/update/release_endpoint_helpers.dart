Uri buildLatestReleaseEndpoint(Uri origin) {
  final normalizedPath = origin.path.toLowerCase();
  if (normalizedPath.endsWith('/api/releases/latest')) {
    return origin;
  }

  final basePath = origin.path.endsWith('/') ? origin.path : '${origin.path}/';
  return origin.replace(path: '${basePath}api/releases/latest');
}
