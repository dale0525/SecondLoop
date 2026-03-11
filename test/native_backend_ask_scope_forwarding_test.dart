import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';

void main() {
  test('NativeAppBackend.askAiStreamScoped forwards args', () async {
    String? capturedAppDir;
    List<int>? capturedKey;
    String? capturedConversationId;
    String? capturedQuestion;
    int? capturedTopK;
    bool? capturedThisThreadOnly;
    int? capturedTimeStartMs;
    int? capturedTimeEndMs;
    List<String>? capturedIncludeTagIds;
    List<String>? capturedExcludeTagIds;
    bool? capturedStrictMode;
    String? capturedLocaleLanguage;
    String? capturedLocalDay;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      askAiStreamScopedFn: ({
        required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        int? timeStartMs,
        int? timeEndMs,
        required List<String> includeTagIds,
        required List<String> excludeTagIds,
        required bool strictMode,
        required String localeLanguage,
        required String localDay,
      }) {
        capturedAppDir = appDir;
        capturedKey = List<int>.from(key);
        capturedConversationId = conversationId;
        capturedQuestion = question;
        capturedTopK = topK;
        capturedThisThreadOnly = thisThreadOnly;
        capturedTimeStartMs = timeStartMs;
        capturedTimeEndMs = timeEndMs;
        capturedIncludeTagIds = List<String>.from(includeTagIds);
        capturedExcludeTagIds = List<String>.from(excludeTagIds);
        capturedStrictMode = strictMode;
        capturedLocaleLanguage = localeLanguage;
        capturedLocalDay = localDay;
        return Stream<String>.fromIterable(const <String>['ok']);
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 1));
    final result = await backend
        .askAiStreamScoped(
          key,
          'c1',
          question: '写一份工作周报',
          topK: 10,
          thisThreadOnly: false,
          timeStartMs: 100,
          timeEndMs: 200,
          includeTagIds: const <String>['system.tag.work'],
          excludeTagIds: const <String>['system.tag.personal'],
          strictMode: true,
          localeLanguage: 'zh',
          localDay: '2026-03-11',
        )
        .toList();

    expect(result, const <String>['ok']);
    expect(capturedAppDir, '/tmp/secondloop_test');
    expect(capturedKey, orderedEquals(key));
    expect(capturedConversationId, 'c1');
    expect(capturedQuestion, '写一份工作周报');
    expect(capturedTopK, 10);
    expect(capturedThisThreadOnly, isFalse);
    expect(capturedTimeStartMs, 100);
    expect(capturedTimeEndMs, 200);
    expect(capturedIncludeTagIds, const <String>['system.tag.work']);
    expect(capturedExcludeTagIds, const <String>['system.tag.personal']);
    expect(capturedStrictMode, isTrue);
    expect(capturedLocaleLanguage, 'zh');
    expect(capturedLocalDay, '2026-03-11');
  });
}
