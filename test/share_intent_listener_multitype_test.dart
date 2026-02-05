import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/share/share_intent_listener.dart';

void main() {
  testWidgets('ShareIntentListener enqueues file + url shares', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('secondloop/share_intent');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumePendingShares') {
        return <Map<String, Object?>>[
          {
            'type': 'file',
            'content': '/tmp/shared.bin',
            'mimeType': 'application/pdf',
            'filename': 'report.pdf',
          },
          {
            'type': 'text',
            'content': 'https://example.com',
          },
        ];
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ShareIntentListener(child: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('share_ingest_queue_v1');
    expect(queue, isNotNull);
    expect(queue!.length, 2);

    final first = jsonDecode(queue[0]) as Map;
    expect(first['type'], 'file');
    expect(first['path'], '/tmp/shared.bin');
    expect(first['mimeType'], 'application/pdf');
    expect(first['filename'], 'report.pdf');

    final second = jsonDecode(queue[1]) as Map;
    expect(second['type'], 'url');
    expect(second['content'], 'https://example.com');
  });
}
