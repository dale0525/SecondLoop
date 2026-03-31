import 'package:flutter_test/flutter_test.dart';

import '../../tools/generate_update_manifest.dart' as cli;

void main() {
  test('release page URL normalization accepts uppercase V prefixes', () {
    final url = cli.releasePageUrlFromRepoForTest(
      repo: 'dale0525/SecondLoop',
      version: 'V1.2.3',
    );

    expect(
      url,
      'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3',
    );
  });
}
