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
  });
}
