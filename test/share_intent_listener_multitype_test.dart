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

  testWidgets('ShareIntentListener falls back mimeType for file share',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('secondloop/share_intent');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumePendingShares') {
        return <Map<String, Object?>>[
          {
            'type': 'file',
            'content': '/tmp/shared-no-mime.bin',
            'filename': 'shared-no-mime.bin',
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
    expect(queue!.length, 1);

    final first = jsonDecode(queue[0]) as Map;
    expect(first['type'], 'file');
    expect(first['path'], '/tmp/shared-no-mime.bin');
    expect(first['mimeType'], 'application/octet-stream');
    expect(first['filename'], 'shared-no-mime.bin');
  });

  testWidgets('ShareIntentListener keeps filename for image shares',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('secondloop/share_intent');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumePendingShares') {
        return <Map<String, Object?>>[
          {
            'type': 'image',
            'content': '/tmp/shared-image.bin',
            'mimeType': 'image/jpeg',
            'filename': 'camera-roll.jpg',
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
    expect(queue!.length, 1);

    final first = jsonDecode(queue[0]) as Map;
    expect(first['type'], 'image');
    expect(first['path'], '/tmp/shared-image.bin');
    expect(first['mimeType'], 'image/jpeg');
    expect(first['filename'], 'camera-roll.jpg');
  });
}
