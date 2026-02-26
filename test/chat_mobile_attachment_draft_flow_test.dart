// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Android: take photo queues draft and sends on tap send',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    final oldImagePickerPlatform = ImagePickerPlatform.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final picker = _TestImagePickerPlatform(
      bytes: _tinyPngBytes(),
      filename: 'camera.png',
    );
    ImagePickerPlatform.instance = picker;

    try {
      final backend = _TestBackend();
      await tester.pumpWidget(_buildChatApp(backend));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat_attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_attach_take_photo')));
      await tester.pumpAndSettle();

      expect(picker.pickFromCameraCalls, 1);
      expect(backend.insertAttachmentCalls, 0);
      expect(backend.linkCalls, 0);
      expect(backend.insertMessageCalls, 0);
      expect(find.byType(InputChip), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkCalls >= 1);

      expect(backend.insertAttachmentCalls, 1);
      expect(backend.linkCalls, 1);
      expect(backend.insertMessageCalls, 1);
    } finally {
      ImagePickerPlatform.instance = oldImagePickerPlatform;
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets(
    'Android: record audio queues draft and sends on tap send',
    (tester) async {
      final oldPlatform = debugDefaultTargetPlatformOverride;
      final oldRecordPlatform = RecordPlatform.instance;
      final oldPathProviderPlatform = PathProviderPlatform.instance;
      final oldForceShouldSend = chatDebugForceAudioRecordingShouldSend;
      final oldSkipRecoveryStore = chatDebugSkipAudioRecoveryStore;
      final oldSkipRuntimeGuards = chatDebugSkipAudioRecordingRuntimeGuards;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pathProvider = _TestPathProviderPlatform('/tmp');
      PathProviderPlatform.instance = pathProvider;

      final recordPlatform = _TestRecordPlatform(
        recordedBytes: Uint8List.fromList(const <int>[9, 8, 7, 6, 5]),
      );
      RecordPlatform.instance = recordPlatform;
      expect(identical(RecordPlatform.instance, recordPlatform), isTrue);

      try {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        chatDebugForceAudioRecordingShouldSend = true;
        chatDebugSkipAudioRecoveryStore = true;
        chatDebugSkipAudioRecordingRuntimeGuards = true;
        final backend = _TestBackend();
        await tester.pumpWidget(_buildChatApp(backend));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('chat_attach')));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('chat_attach_record_audio')));
        await tester.pump();

        await _pumpUntil(tester, () => recordPlatform.startCalls > 0);
        final error = tester.takeException();
        expect(error, isNull, reason: 'record start error: $error');
        expect(recordPlatform.hasPermissionCalls, greaterThan(0));
        expect(pathProvider.getTemporaryPathCalls, greaterThan(0));
        expect(recordPlatform.startCalls, greaterThan(0));
        await _pumpUntil(
          tester,
          () => chatDebugForceAudioRecordingShouldSend == null,
          maxTicks: 500,
        );
        expect(chatDebugForceAudioRecordingShouldSend, isNull);

        final draftFinder =
            find.byKey(const ValueKey('chat_draft_attachment_list'));
        for (var i = 0; i < 40 && draftFinder.evaluate().isEmpty; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(
          draftFinder,
          findsOneWidget,
        );
        expect(find.byType(InputChip), findsOneWidget);

        expect(backend.insertAttachmentCalls, 0);
        expect(backend.linkCalls, 0);
        expect(backend.insertMessageCalls, 0);
      } finally {
        chatDebugForceAudioRecordingShouldSend = oldForceShouldSend;
        chatDebugSkipAudioRecoveryStore = oldSkipRecoveryStore;
        chatDebugSkipAudioRecordingRuntimeGuards = oldSkipRuntimeGuards;
        RecordPlatform.instance = oldRecordPlatform;
        PathProviderPlatform.instance = oldPathProviderPlatform;
        debugDefaultTargetPlatformOverride = oldPlatform;
      }
    },
  );
}

Widget _buildChatApp(_TestBackend backend) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const ChatPage(
            conversation: Conversation(
              id: 'c1',
              title: 'Loop',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTicks = 200,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < maxTicks; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
}

Uint8List _tinyPngBytes() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _TestImagePickerPlatform extends ImagePickerPlatform {
  _TestImagePickerPlatform({
    required this.bytes,
    required this.filename,
  });

  final Uint8List bytes;
  final String filename;
  int pickFromCameraCalls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (source != ImageSource.camera) {
      return null;
    }

    pickFromCameraCalls += 1;
    return XFile.fromData(
      bytes,
      mimeType: 'image/png',
      path: '/tmp/$filename',
    );
  }

  @override
  Future<LostDataResponse> getLostData() async {
    return LostDataResponse.empty();
  }
}

final class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.tempPath);

  final String tempPath;
  int getTemporaryPathCalls = 0;

  @override
  Future<String?> getTemporaryPath() async {
    getTemporaryPathCalls += 1;
    return tempPath;
  }
}

final class _TestRecordPlatform extends RecordPlatform {
  _TestRecordPlatform({required this.recordedBytes});

  final Uint8List recordedBytes;
  final Map<String, _RecorderState> _stateByRecorderId =
      <String, _RecorderState>{};
  int hasPermissionCalls = 0;
  int startCalls = 0;

  _RecorderState _stateOf(String recorderId) {
    return _stateByRecorderId.putIfAbsent(recorderId, _RecorderState.new);
  }

  @override
  Future<void> create(String recorderId) async {
    _stateOf(recorderId);
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    startCalls += 1;
    final state = _stateOf(recorderId);
    state.path = path;
    state.recording = true;
    state.paused = false;
    state.stateController.add(RecordState.record);
  }

  @override
  Future<String?> stop(String recorderId) async {
    final state = _stateOf(recorderId);
    final path = state.path;

    state.recording = false;
    state.paused = false;
    state.stateController.add(RecordState.stop);

    if (path == null || path.trim().isEmpty) {
      return null;
    }

    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(recordedBytes, flush: true);
    return path;
  }

  @override
  Future<void> pause(String recorderId) async {
    final state = _stateOf(recorderId);
    state.paused = true;
    state.stateController.add(RecordState.pause);
  }

  @override
  Future<void> resume(String recorderId) async {
    final state = _stateOf(recorderId);
    state.paused = false;
    state.recording = true;
    state.stateController.add(RecordState.record);
  }

  @override
  Future<bool> isRecording(String recorderId) async {
    return _stateOf(recorderId).recording;
  }

  @override
  Future<bool> isPaused(String recorderId) async {
    return _stateOf(recorderId).paused;
  }

  @override
  Future<bool> hasPermission(String recorderId) async {
    hasPermissionCalls += 1;
    return true;
  }

  @override
  Future<void> dispose(String recorderId) async {
    final state = _stateByRecorderId.remove(recorderId);
    await state?.stateController.close();
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async {
    return Amplitude(current: -8, max: -3);
  }

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async {
    return true;
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async {
    return const <InputDevice>[];
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    return _stateOf(recorderId).stateController.stream;
  }

  @override
  Future<void> cancel(String recorderId) async {
    final state = _stateOf(recorderId);
    state.recording = false;
    state.paused = false;
    state.stateController.add(RecordState.stop);
  }
}

final class _RecorderState {
  String? path;
  bool recording = false;
  bool paused = false;
  final StreamController<RecordState> stateController =
      StreamController<RecordState>.broadcast();
}

final class _TestBackend extends NativeAppBackend {
  _TestBackend() : super(appDirProvider: () async => '/tmp/secondloop_test');

  int insertAttachmentCalls = 0;
  int insertMessageCalls = 0;
  int linkCalls = 0;
  final List<String> insertedAttachmentMimeTypes = <String>[];

  int _messageSeq = 0;
  int _attachmentSeq = 0;

  final List<Message> _messages = <Message>[];
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async {
    return _messages
        .where((m) => m.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    return listMessages(key, conversationId);
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    insertMessageCalls++;
    final message = Message(
      id: 'm${++_messageSeq}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: _messageSeq,
      isMemory: true,
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => const <Todo>[];

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
  }

  @override
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    insertAttachmentCalls++;
    insertedAttachmentMimeTypes.add(mimeType);
    final sha = 'sha${++_attachmentSeq}';
    _attachmentBytesBySha[sha] = bytes;
    return Attachment(
      sha256: sha,
      mimeType: mimeType,
      path: 'attachments/$sha.bin',
      byteLen: bytes.length,
      createdAtMs: 0,
    );
  }

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {
    linkCalls++;
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    return const <Attachment>[];
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    return _attachmentBytesBySha[sha256] ?? Uint8List(0);
  }
}
