import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/release_notes_service.dart';

void main() {
  group('ReleaseNotesService', () {
    test('prefers locale-specific release notes asset', () async {
      final service = ReleaseNotesService(
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.2.3',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3',
          'assets': [
            {
              'name': 'release-notes-v1.2.3-en-US.json',
              'browser_download_url': 'https://cdn.example.com/en.json',
            },
            {
              'name': 'release-notes-v1.2.3-zh-CN.json',
              'browser_download_url': 'https://cdn.example.com/zh.json',
            },
          ],
        },
        notesJsonFetcher: (uri) async {
          if (uri.toString().endsWith('/zh.json')) {
            return {
              'version': 'v1.2.3',
              'summary': '修复了同步问题',
              'highlights': [
                {
                  'text': '同步冲突减少',
                  'change_ids': ['c1'],
                },
              ],
              'sections': [
                {
                  'title': '修复',
                  'items': [
                    {
                      'text': '修复同步冲突',
                      'change_ids': ['c1']
                    },
                  ],
                },
              ],
            };
          }
          throw StateError('unexpected_url_$uri');
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3',
        locale: const Locale('zh', 'CN'),
      );

      expect(result.notes, isNotNull);
      expect(result.notes!.summary, '修复了同步问题');
      expect(result.notes!.sections.first.title, '修复');
      expect(result.sourceLocaleTag, 'zh-CN');
    });

    test('falls back to en-US when locale file is missing', () async {
      final service = ReleaseNotesService(
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.2.3',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3',
          'assets': [
            {
              'name': 'release-notes-v1.2.3-en-US.json',
              'browser_download_url': 'https://cdn.example.com/en.json',
            },
          ],
        },
        notesJsonFetcher: (uri) async => {
          'version': 'v1.2.3',
          'summary': 'Improved startup reliability.',
          'highlights': [
            {
              'text': 'Startup now handles migration errors better',
              'change_ids': ['c1'],
            },
          ],
          'sections': [
            {
              'title': 'Fixes',
              'items': [
                {
                  'text': 'Guard invalid migration states',
                  'change_ids': ['c1'],
                },
              ],
            },
          ],
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3',
        locale: const Locale('fr', 'FR'),
      );

      expect(result.notes, isNotNull);
      expect(result.sourceLocaleTag, 'en-US');
      expect(result.notes!.summary, contains('startup'));
    });

    test('prefers script-specific release notes asset', () async {
      final service = ReleaseNotesService(
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.2.3',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3',
          'assets': [
            {
              'name': 'release-notes-v1.2.3-en-US.json',
              'browser_download_url': 'https://cdn.example.com/en.json',
            },
            {
              'name': 'release-notes-v1.2.3-zh-Hans.json',
              'browser_download_url': 'https://cdn.example.com/zh-hans.json',
            },
          ],
        },
        notesJsonFetcher: (uri) async {
          if (uri.toString().endsWith('/zh-hans.json')) {
            return {
              'version': 'v1.2.3',
              'summary': '简体中文说明。',
              'highlights': [
                {
                  'text': '优先匹配脚本语言资源',
                  'change_ids': ['c1'],
                },
              ],
              'sections': [
                {
                  'title': '说明',
                  'items': [
                    {
                      'text': '命中 zh-Hans 资源',
                      'change_ids': ['c1']
                    },
                  ],
                },
              ],
            };
          }
          throw StateError('unexpected_url_$uri');
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3',
        locale:
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );

      expect(result.notes, isNotNull);
      expect(result.notes!.summary, '简体中文说明。');
      expect(result.sourceLocaleTag, 'zh-Hans');
    });

    test('rejects fourth-segment release tags for release notes assets',
        () async {
      final service = ReleaseNotesService(
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.2.3.4',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3.4',
          'assets': [
            {
              'name': 'release-notes-v1.2.3.4-en-US.json',
              'browser_download_url': 'https://cdn.example.com/en-1234.json',
            },
          ],
        },
        notesJsonFetcher: (uri) async => {
          'version': 'v1.2.3.4',
          'summary': 'Fourth segment release notes.',
          'highlights': [
            {
              'text': 'Supports four-part versions',
              'change_ids': ['c1'],
            },
          ],
          'sections': [
            {
              'title': 'Notes',
              'items': [
                {
                  'text': 'Release notes match the update tag format',
                  'change_ids': ['c1'],
                },
              ],
            },
          ],
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3.4',
        locale: const Locale('en', 'US'),
      );

      expect(result.notes, isNull);
      expect(result.errorMessage, 'invalid_tag');
    });

    test('rejects prerelease tags for release notes assets', () async {
      final service = ReleaseNotesService(
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.2.3-rc.1',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3-rc.1',
          'assets': [
            {
              'name': 'release-notes-v1.2.3-rc.1-en-US.json',
              'browser_download_url': 'https://cdn.example.com/en-rc1.json',
            },
          ],
        },
        notesJsonFetcher: (uri) async => {
          'version': 'v1.2.3-rc.1',
          'summary': 'Prerelease notes.',
          'highlights': [
            {
              'text': 'Supports prerelease tags',
              'change_ids': ['c1'],
            },
          ],
          'sections': [
            {
              'title': 'Notes',
              'items': [
                {
                  'text': 'Release notes match prerelease update tags',
                  'change_ids': ['c1'],
                },
              ],
            },
          ],
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3-rc.1',
        locale: const Locale('en', 'US'),
      );

      expect(result.notes, isNull);
      expect(result.errorMessage, 'invalid_tag');
    });

    test('rejects short prerelease tags without misparsing locale', () async {
      final service = ReleaseNotesService(
        releaseJsonFetcher: (uri) async => {
          'tag_name': 'v1.2.3-rc',
          'html_url':
              'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3-rc',
          'assets': [
            {
              'name': 'release-notes-v1.2.3-rc.json',
              'browser_download_url': 'https://cdn.example.com/en-rc.json',
            },
          ],
        },
        notesJsonFetcher: (uri) async => {
          'version': 'v1.2.3-rc',
          'summary': 'Short prerelease notes.',
          'highlights': [
            {
              'text': 'Supports rc tags without numeric suffixes',
              'change_ids': ['c1'],
            },
          ],
          'sections': [
            {
              'title': 'Notes',
              'items': [
                {
                  'text': 'Parses release note assets with rc suffixes',
                  'change_ids': ['c1'],
                },
              ],
            },
          ],
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3-rc',
        locale: const Locale('en', 'US'),
      );

      expect(result.notes, isNull);
      expect(result.errorMessage, 'invalid_tag');
    });

    test('preserves custom release API base path before GitHub tag fallback',
        () async {
      final attempted = <Uri>[];
      final service = ReleaseNotesService(
        releaseApiOriginOverride: 'https://updates.example.com/custom/base/',
        releaseRepoOverride: 'acme/SecondLoop',
        releaseJsonFetcher: (uri) async {
          attempted.add(uri);
          if (attempted.length == 1) {
            return {
              'tag_name': 'v1.2.4',
              'html_url': 'https://updates.example.com/releases/tag/v1.2.4',
              'assets': const [],
            };
          }
          return {
            'tag_name': 'v1.2.3',
            'html_url':
                'https://github.com/acme/SecondLoop/releases/tag/v1.2.3',
            'assets': [
              {
                'name': 'release-notes-v1.2.3-en-US.json',
                'browser_download_url': 'https://cdn.example.com/en-123.json',
              },
            ],
          };
        },
        notesJsonFetcher: (uri) async => {
          'version': 'v1.2.3',
          'summary': 'Fallback notes.',
          'highlights': [
            {
              'text': 'Falls back from self-hosted latest to GitHub tag',
              'change_ids': ['c1'],
            },
          ],
          'sections': [
            {
              'title': 'Notes',
              'items': [
                {
                  'text': 'Preserves the configured API base path',
                  'change_ids': ['c1'],
                },
              ],
            },
          ],
        },
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3',
        locale: const Locale('en', 'US'),
      );

      expect(result.notes, isNotNull);
      expect(attempted, hasLength(2));
      expect(
        attempted.first.toString(),
        'https://updates.example.com/custom/base/api/releases/latest',
      );
      expect(
        attempted.last.toString(),
        'https://api.github.com/repos/acme/SecondLoop/releases/tags/v1.2.3',
      );
    });

    test('times out stalled release notes fetchers', () async {
      final service = ReleaseNotesService(
        networkTimeoutOverride: const Duration(milliseconds: 10),
        releaseJsonFetcher: (uri) => Completer<Map<String, Object?>>().future,
      );

      final result = await service.fetchReleaseNotes(
        tag: 'v1.2.3',
        locale: const Locale('en', 'US'),
      );

      expect(result.notes, isNull);
      expect(result.errorMessage, contains('TimeoutException'));
    });
  });
}
