import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/agent_ui/agent_recorded_audio_capture.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_editor_launcher.dart';
import 'package:secondloop/features/chat/chat_markdown_editor_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('agent composer attach button stages selected files',
      (tester) async {
    FilePicker? originalFilePicker;
    try {
      originalFilePicker = FilePicker.platform;
    } catch (_) {
      originalFilePicker = null;
    }
    final filePicker = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'qa-ocr-sample.png',
          size: 3,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ]),
    );
    FilePicker.platform = filePicker;
    addTearDown(() {
      if (originalFilePicker != null) {
        FilePicker.platform = originalFilePicker;
      }
    });

    final sender = _FakeRuntimeConversationSender();
    await _pumpManagedProAgentConversation(
      tester,
      sender: sender,
      runtimeAgentStateRepository: _FakeRuntimeAgentStateRepository(sender),
    );

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();

    expect(filePicker.pickFilesCalls, 1);
    expect(find.text('qa-ocr-sample.png'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('chat_send')),
    );
    expect(sendButton.onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const ValueKey('chat_input')),
      'Extract text from this image.',
    );
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(sender.sentMessages, <String>['Extract text from this image.']);
    expect(sender.sentMessageDisplayTexts, <String?>[null]);
    expect(sender.sentAttachmentIntents, <String?>[null]);
    expect(sender.sentUploadAttachments.single, hasLength(1));
    expect(sender.sentMessageAttachments.single, hasLength(1));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('content_base64')));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('bytes_base64')));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('data_url')));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('image_url')));
    expect(sender.sentMessageAttachments.single.single['filename'],
        'qa-ocr-sample.png');
    expect(
        sender.sentMessageAttachments.single.single['mime_type'], 'image/png');
    expect(sender.sentMessageAttachments.single.single['byte_size'], 3);
    expect(
      sender.sentMessageAttachments.single.single['attachment_id'],
      '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    );
    expect(
        sender.sentUploadAttachments.single.single['content_base64'], 'AQID');
    expect(
      sender.sentUploadAttachments.single.single['data_url'],
      'data:image/png;base64,AQID',
    );
    expect(
      find.byKey(
        const ValueKey(
          'agent_message_attachment_image_039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'agent_message_attachment_chip_039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('agent composer sends attachment-only message with display text',
      (tester) async {
    FilePicker? originalFilePicker;
    try {
      originalFilePicker = FilePicker.platform;
    } catch (_) {
      originalFilePicker = null;
    }
    final filePicker = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'qa-ocr-sample.png',
          size: 3,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ]),
    );
    FilePicker.platform = filePicker;
    addTearDown(() {
      if (originalFilePicker != null) {
        FilePicker.platform = originalFilePicker;
      }
    });

    final sender = _FakeRuntimeConversationSender();
    await _pumpManagedProAgentConversation(
      tester,
      sender: sender,
      runtimeAgentStateRepository: _FakeRuntimeAgentStateRepository(sender),
    );

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    expect(find.text('qa-ocr-sample.png'), findsOneWidget);

    tester
        .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(sender.sentMessages, <String>['']);
    expect(sender.sentMessageDisplayTexts,
        <String?>['Uploaded attachment: qa-ocr-sample.png']);
    expect(
        sender.sentAttachmentIntents, <String?>['understand_uploaded_files']);
    expect(
        sender.sentUploadAttachments.single.single['content_base64'], 'AQID');
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('content_base64')));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('bytes_base64')));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('data_url')));
    expect(sender.sentMessageAttachments.single.single.keys,
        isNot(contains('image_url')));
  });

  testWidgets('agent composer exposes restored actions on narrow layouts',
      (tester) async {
    final sender = _FakeRuntimeConversationSender();
    await _pumpManagedProAgentConversation(
      tester,
      sender: sender,
      surfaceSize: const Size(390, 720),
      capabilities: _testCapabilities(supportsAudioRecording: true),
    );

    expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_attach')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('chat_markdown_editor_open')), findsNothing);
    expect(find.byKey(const ValueKey('chat_record_audio')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_send')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat_input')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat_markdown_editor_open')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'Go');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat_send')), findsOneWidget);

    final actionsTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('chat_composer_actions')),
        )
        .dy;
    final inputBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('chat_input')),
        )
        .dy;
    final sendTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('chat_send')),
        )
        .dy;
    final sendLeft = tester
        .getTopLeft(
          find.byKey(const ValueKey('chat_send')),
        )
        .dx;
    final actionsRight = tester
        .getTopRight(
          find.byKey(const ValueKey('chat_composer_actions')),
        )
        .dx;
    expect(actionsTop, greaterThanOrEqualTo(inputBottom - 1));
    expect(sendTop, greaterThanOrEqualTo(inputBottom - 1));
    expect(sendLeft, greaterThan(actionsRight));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'agent composer keeps secondary actions before input on wide layouts',
      (tester) async {
    final sender = _FakeRuntimeConversationSender();
    await _pumpManagedProAgentConversation(
      tester,
      sender: sender,
      surfaceSize: const Size(1200, 760),
      capabilities: _testCapabilities(supportsAudioRecording: true),
    );
    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'Go');
    await tester.pumpAndSettle();

    final actionsRight = tester
        .getTopRight(
          find.byKey(const ValueKey('chat_composer_actions')),
        )
        .dx;
    final inputLeft = tester
        .getTopLeft(
          find.byKey(const ValueKey('chat_input')),
        )
        .dx;
    final inputRight = tester
        .getTopRight(
          find.byKey(const ValueKey('chat_input')),
        )
        .dx;
    final sendLeft = tester
        .getTopLeft(
          find.byKey(const ValueKey('chat_send')),
        )
        .dx;

    expect(actionsRight, lessThanOrEqualTo(inputLeft + 1));
    expect(sendLeft, greaterThanOrEqualTo(inputRight - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent composer hides recording on unsupported platforms',
      (tester) async {
    final sender = _FakeRuntimeConversationSender();
    await _pumpManagedProAgentConversation(
      tester,
      sender: sender,
      capabilities: _testCapabilities(supportsAudioRecording: false),
    );

    expect(find.byKey(const ValueKey('chat_attach')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('chat_markdown_editor_open')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat_input')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat_markdown_editor_open')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat_record_audio')), findsNothing);
  });

  testWidgets(
    'agent composer applies Markdown editor result and draft attachments',
    (tester) async {
      final sender = _FakeRuntimeConversationSender();
      await _pumpManagedProAgentConversation(
        tester,
        sender: sender,
        markdownEditorRoutePusher: (_) async {
          return ChatMarkdownEditorResult.saveWithAttachments(
            '## Edited note',
            [
              AttachmentDraftPayload(
                localId: 'markdown_draft_1',
                filename: 'markdown-image.png',
                mimeType: 'image/png',
                bytes: Uint8List.fromList(<int>[4, 5, 6]),
              ),
            ],
          );
        },
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        'draft',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_markdown_editor_open')));
      await tester.pumpAndSettle();

      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('chat_input')),
      );
      expect(input.controller?.text, '## Edited note');
      expect(find.text('markdown-image.png'), findsOneWidget);

      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(sender.sentMessages, <String>['## Edited note']);
      expect(sender.sentMessageAttachments.single.single['filename'],
          'markdown-image.png');
      expect(sender.sentMessageAttachments.single.single['mime_type'],
          'image/png');
      expect(
          sender.sentUploadAttachments.single.single['content_base64'], 'BAUG');
    },
  );

  testWidgets('agent composer records audio into attachment draft',
      (tester) async {
    final capture = _FakeAgentRecordedAudioCapture(
      bytes: Uint8List.fromList(<int>[9, 8, 7, 6]),
    );
    debugAgentRecordedAudioCaptureOverride = capture;
    addTearDown(() {
      debugAgentRecordedAudioCaptureOverride = null;
    });

    final sender = _FakeRuntimeConversationSender();
    await _pumpManagedProAgentConversation(
      tester,
      sender: sender,
      capabilities: _testCapabilities(supportsAudioRecording: true),
    );

    await tester.tap(find.byKey(const ValueKey('chat_record_audio')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat_recording_status')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_recording_cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_record_audio')), findsNothing);
    expect(capture.startCalls, 1);

    await tester.tap(find.byKey(const ValueKey('chat_recording_stop')));
    await tester.pumpAndSettle();

    expect(capture.stopCalls, 1);
    expect(capture.readPaths, <String>['/tmp/fake-recording.m4a']);
    expect(capture.deletedPaths, <String>['/tmp/fake-recording.m4a']);
    expect(find.textContaining('recording_'), findsOneWidget);

    tester
        .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(sender.sentMessages, <String>['']);
    expect(
        sender.sentAttachmentIntents, <String?>['understand_uploaded_files']);
    expect(sender.sentMessageAttachments.single.single['mime_type'],
        kAgentRecordedAudioMimeType);
    expect(sender.sentMessageAttachments.single.single['byte_size'], 4);
    expect(sender.sentUploadAttachments.single.single['content_base64'],
        'CQgHBg==');
  });

  testWidgets(
    'agent conversation restores image preview from persisted runtime metadata',
    (tester) async {
      const attachmentId =
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';
      final sender = _FakeRuntimeConversationSender()
        ..fetchedAttachmentBytes[attachmentId] = _tinyPngBytes();
      final repository = _StaticRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-user-attachment',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'user',
              'content': 'Extract text from this image.',
              'attachment_refs': [attachmentId],
              'attachments': [
                {
                  'attachment_id': attachmentId,
                  'blob_id': attachmentId,
                  'sha256': attachmentId,
                  'filename': 'qa-ocr-sample.png',
                  'mime_type': 'image/png',
                  'media_type': 'image',
                  'byte_size': 3,
                },
              ],
              'created_at_ms': 1700000000000,
            },
            {
              'turn_id': 'turn-assistant-attachment',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': 'Attachment received.',
              'created_at_ms': 1700000000100,
            },
          ],
        }),
      );

      await _pumpManagedProAgentConversation(
        tester,
        sender: sender,
        runtimeAgentStateRepository: repository,
      );

      expect(sender.fetchedAttachmentIds, [attachmentId]);
      expect(find.text('qa-ocr-sample.png'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey('agent_message_attachment_chip_$attachmentId'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('agent_message_attachment_image_$attachmentId'),
        ),
        findsOneWidget,
      );

      final imageRect = tester.getRect(
        find.byKey(
          const ValueKey('agent_message_attachment_image_$attachmentId'),
        ),
      );
      final attachmentChip = find.byKey(
        const ValueKey('agent_message_attachment_chip_$attachmentId'),
      );
      final filenameRect = tester.getRect(
        find.descendant(
          of: attachmentChip,
          matching: find.text('qa-ocr-sample.png'),
        ),
      );
      expect(imageRect.width, greaterThan(filenameRect.height));
      expect(filenameRect.top, greaterThanOrEqualTo(imageRect.bottom));

      await tester.tap(attachmentChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AttachmentViewerPage), findsOneWidget);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attachment_image_preview_surface')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    },
  );

  testWidgets(
    'agent conversation keeps successful runtime reply visible when state refresh fails',
    (tester) async {
      final sender = _FakeRuntimeConversationSender();
      final repository = _ThrowingRuntimeAgentStateRepository(
        StateError('agent_state_unavailable'),
      );

      await _pumpManagedProAgentConversation(
        tester,
        sender: sender,
        runtimeAgentStateRepository: repository,
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        'Extract text from this image.',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(sender.sentMessages, <String>['Extract text from this image.']);
      expect(find.text('Attachment received.'), findsOneWidget);
      expect(find.text('Ask AI failed. Please try again.'), findsNothing);
    },
  );
}

Uint8List _tinyPngBytes() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

Future<void> _pumpManagedProAgentConversation(
  WidgetTester tester, {
  required _FakeRuntimeConversationSender sender,
  RuntimeAgentStateRepository? runtimeAgentStateRepository,
  Size surfaceSize = const Size(1012, 701),
  AppPlatformCapabilities capabilities = const AppPlatformCapabilities(
    supportsDesktopHotkey: true,
    supportsAudioRecording: true,
    supportsDesktopDrop: true,
    supportsDesktopBootSettings: true,
    supportsCameraCapture: false,
    usesCloudSessionModel: false,
  ),
  ChatMarkdownEditorRoutePusher? markdownEditorRoutePusher,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        home: AppBackendScope(
          backend: TestAppBackend(),
          child: AppPlatformCapabilityScope(
            capabilities: capabilities,
            child: CloudAuthScope(
              controller: _CloudAuthController(),
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.example.test',
                modelName: 'cloud',
              ),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: SubscriptionScope(
                  controller: _SubscriptionController(
                    SubscriptionStatus.entitled,
                  ),
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeConversationSender: sender,
                    runtimeAgentStateRepository: runtimeAgentStateRepository ??
                        _FakeRuntimeAgentStateRepository(sender),
                    markdownEditorRoutePusher: markdownEditorRoutePusher,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppPlatformCapabilities _testCapabilities({
  required bool supportsAudioRecording,
}) {
  return AppPlatformCapabilities(
    supportsDesktopHotkey: true,
    supportsAudioRecording: supportsAudioRecording,
    supportsDesktopDrop: true,
    supportsDesktopBootSettings: true,
    supportsCameraCapture: false,
    usesCloudSessionModel: false,
  );
}

final class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);

  final FilePickerResult? result;
  int pickFilesCalls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickFilesCalls += 1;
    return result;
  }
}

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _FakeRuntimeAgentStateRepository(this.sender);

  final _FakeRuntimeConversationSender sender;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    if (sender.sentMessages.isEmpty) {
      return RuntimeAgentState.empty(
        vaultId: vaultId,
        conversationId: conversationId,
      );
    }
    final attachments = sender.sentMessageAttachments.last;
    return RuntimeAgentState.fromJson({
      'vault_id': vaultId,
      'conversation_id': conversationId,
      'conversation_turns': [
        {
          'turn_id': 'turn-user-attachment',
          'conversation_id': conversationId,
          'vault_id': vaultId,
          'role': 'user',
          'content': sender.sentMessages.last,
          'attachment_refs': attachments
              .map((item) => item['attachment_id'] ?? item['id'])
              .toList(growable: false),
          'attachments': attachments,
          'created_at_ms': 1700000000000,
        },
        {
          'turn_id': 'turn-assistant-attachment',
          'conversation_id': conversationId,
          'vault_id': vaultId,
          'role': 'assistant',
          'content': 'Attachment received.',
          'created_at_ms': 1700000000100,
        },
      ],
    });
  }
}

final class _StaticRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  const _StaticRuntimeAgentStateRepository(this.state);

  final RuntimeAgentState state;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async =>
      state;
}

final class _ThrowingRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  const _ThrowingRuntimeAgentStateRepository(this.error);

  final Object error;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    throw error;
  }
}

final class _FakeRuntimeConversationSender
    implements
        ChatRuntimeConversationSender,
        ChatRuntimeConversationAttachmentSender,
        ChatRuntimeAttachmentContentFetcher {
  final List<String> sentMessages = <String>[];
  final List<String?> sentMessageDisplayTexts = <String?>[];
  final List<String?> sentAttachmentIntents = <String?>[];
  final List<List<Map<String, Object?>>> sentUploadAttachments =
      <List<Map<String, Object?>>>[];
  final List<List<Map<String, Object?>>> sentMessageAttachments =
      <List<Map<String, Object?>>>[];
  final Map<String, Uint8List> fetchedAttachmentBytes = <String, Uint8List>{};
  final List<String> fetchedAttachmentIds = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    return sendWithAttachments(
      vaultId: vaultId,
      conversationId: conversationId,
      message: message,
      uploadAttachments: const <Map<String, Object?>>[],
      messageAttachments: const <Map<String, Object?>>[],
    );
  }

  @override
  Future<SecretaryRuntimeConversationResult> sendWithAttachments({
    required String vaultId,
    required String conversationId,
    required String message,
    String? messageDisplayText,
    String? attachmentIntent,
    List<Map<String, Object?>> uploadAttachments =
        const <Map<String, Object?>>[],
    required List<Map<String, Object?>> messageAttachments,
  }) async {
    sentMessages.add(message);
    sentMessageDisplayTexts.add(messageDisplayText);
    sentAttachmentIntents.add(attachmentIntent);
    sentUploadAttachments.add(uploadAttachments);
    sentMessageAttachments.add(messageAttachments);
    return SecretaryRuntimeConversationResult.fromJson({
      'run_id': 'run-attachment',
      'conversation_id': conversationId,
      'assistant': const {'content': 'Attachment received.'},
      'metadata': {
        'run_id': 'run-attachment',
        'turn_id': 'turn-attachment',
        'conversation_id': conversationId,
        'vault_id': vaultId,
        'response_type': 'assistant_message',
        'run_status': 'completed',
        'approval_required': false,
      },
    });
  }

  @override
  Future<Uint8List?> fetchAttachmentBytes({
    required String vaultId,
    required String attachmentId,
  }) async {
    fetchedAttachmentIds.add(attachmentId);
    return fetchedAttachmentBytes[attachmentId];
  }
}

final class _FakeAgentRecordedAudioCapture
    implements AgentRecordedAudioCapture {
  _FakeAgentRecordedAudioCapture({required this.bytes});

  final Uint8List bytes;
  final List<String> readPaths = <String>[];
  final List<String> deletedPaths = <String>[];
  int startCalls = 0;
  int stopCalls = 0;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<String> start({required DateTime startedAt}) async {
    startCalls += 1;
    return '/tmp/fake-recording.m4a';
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    return '/tmp/fake-recording.m4a';
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    readPaths.add(path);
    return bytes;
  }

  @override
  Future<void> deleteFile(String path) async {
    deletedPaths.add(path);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _SubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _SubscriptionController(this.status);

  @override
  final SubscriptionStatus status;
}

final class _CloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'qa@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'id-token';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
