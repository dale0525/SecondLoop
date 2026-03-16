import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebAppGate requires observable auth controllers at declaration time',
      () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(
      source,
      contains('final ObservableCloudAuthController authController;'),
    );
    expect(source, isNot(contains('_requireObservableAuthController')));
  });

  test('web files refresh guards concurrent startup refreshes', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('bool _refreshing = false;'));
    expect(source, contains('bool _refreshQueued = false;'));
    expect(source, contains('Future<void> _refresh() async {'));
    expect(source, contains('if (_refreshing) {'));
    expect(source, contains('_refreshQueued = true;'));
    expect(source, contains('_refreshing = true;'));
    expect(
      source,
      contains('final idToken = await widget.authController.getIdToken();'),
    );
    expect(source, contains('} finally {'));
    expect(source, contains('_refreshing = false;'));
    expect(source, contains('final shouldRefreshAgain = _refreshQueued;'));
    expect(source, contains('unawaited(_refresh());'));
  });

  test('web files refresh stops before second vault call after unmount', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source,
        contains('final usage = await widget.service.fetchVaultUsage('));
    expect(
      source,
      contains('''if (!mounted) return;
      final items = await widget.service.listVaultAttachments('''),
    );
  });

  test('web settings recent files disable concurrent opens', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('if (_openingAttachmentSha != null) return;'));
    expect(
      source,
      contains('''_openingAttachmentSha != null
                ? null
                : () => _openAttachment(item),'''),
    );
  });

  test('web vault actions guard setState after async gaps', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source,
        contains('final picked = await FilePicker.platform.pickFiles('));
    expect(source,
        contains('if (picked == null || picked.files.isEmpty) return;'));
    expect(source, contains('final vaultId = _vaultId;'));
    expect(
      source,
      contains(
          'if (idToken == null || idToken.isEmpty || vaultId == null) return;'),
    );
    expect(source, contains('if (_deletingAttachmentSha != null) return;'));
    expect(
      source,
      contains('setState(() => _deletingAttachmentSha = item.primarySha256);'),
    );
    expect(source, contains('Future<void> _refreshRecentItems() async {'));
    expect(source, contains('if (_loadingRecent) return;'));
    expect(source, contains('_loadingRecent = true;'));
    expect(source,
        contains('final idToken = await widget.authController.getIdToken();'));
    expect(source,
        contains('if (mounted) setState(() => _loadingRecent = false);'));
  });

  test('web upload refreshes auth per file and surfaces unreadable files', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source,
        contains('final picked = await FilePicker.platform.pickFiles('));
    expect(source, contains('final vaultId = _vaultId;'));
    expect(source, contains('for (final file in picked.files) {'));
    expect(
        source, contains('final bytes = await _readPlatformFileBytes(file);'));
    expect(
        source,
        contains(
            'final freshToken = await widget.authController.getIdToken();'));
    expect(source, contains('if (freshToken == null || freshToken.isEmpty) {'));
    expect(source, contains('authFailed = true;'));
    expect(source,
        contains('final failedCount = picked.files.length - uploadCount;'));
    expect(source, contains('uploadReadFailed'));
    expect(source, contains('uploadPartial'));
    expect(source, contains('uploadAuthFailed'));
    expect(source, contains('attachmentTooLarge'));
    expect(source, contains('var authFailed = false;'));
    expect(source, contains('throw StateError('));
    expect(source,
        contains("authFailed ? 'upload_auth_failed' : 'upload_read_failed'"));
  });

  test('web main shell keeps tabs mounted across navigation', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('body: IndexedStack('));
    expect(source, contains('children: pages,'));
    expect(source, isNot(contains('body: pages[_index]')));
  });

  test('web upload disables reentry before opening the picker', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('bool _uploading = false;'));
    expect(source, contains('if (_uploading) return;'));
    expect(source, contains('_uploading = true;'));
    expect(source, contains('if (mounted) {'));
    expect(source, contains('_uploading = false;'));
  });

  test('web attachment viewer guards context after auth gap', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(
        source, contains('final idToken = await authController.getIdToken();'));
    expect(source,
        contains('final vaultId = _webVaultIdForController(authController);'));
    expect(source, contains('if (!context.mounted) return;'));
    expect(source,
        contains('final bytes = await service.fetchVaultAttachmentBytes('));
    expect(source, contains('final attachmentBytes ='));
    expect(source,
        contains('bytes is Uint8List ? bytes : Uint8List.fromList(bytes)'));
    expect(source, contains('bytes: attachmentBytes,'));
  });

  test('web files disable open while busy or uploading', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('if (_busy || _uploading) return;'));
  });

  test('web files claim delete slot before auth awaits', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(
      source,
      contains('''if (_deletingAttachmentSha != null) return;
    setState(() => _deletingAttachmentSha = item.primarySha256);
    try {
      final idToken = await widget.authController.getIdToken();'''),
    );
    expect(source, contains('if (mounted) {'));
    expect(source, contains('setState(() => _deletingAttachmentSha = null);'));
    expect(source, contains('_deletingAttachmentSha = null;'));
  });

  test('web files surface auth failures during delete and refresh', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(
      source,
      contains('''if (idToken == null || idToken.isEmpty || vaultId == null) {
        if (!mounted) return;
        final authError = context.t.chat.cloudGateway.errors.auth;
        setState(() => _error = authError);
        return;
      }'''),
    );
  });

  test('web attachment open path does not clear upload guard', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    final start = source.indexOf(
      'Future<void> _openAttachment(WebVaultAttachmentItem item) async {',
    );
    final end = source.indexOf('Future<void> _deleteAttachment', start);
    final openAttachmentBlock = source.substring(start, end);
    expect(openAttachmentBlock, isNot(contains('_uploading = false;')));
  });

  test('web settings page reuses gate-managed clients', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('billingClient: _billingClient'));
    expect(source, contains('cloudUsageClient: _cloudUsageClient'));
    expect(source, contains('vaultUsageClient: _vaultUsageClient'));
    expect(source, contains('vaultAttachmentsClient: _vaultAttachmentsClient'));
    expect(source, contains('vaultConfigStore: _vaultConfigStore'));
    expect(source, contains('_deletingAttachmentSha != null'));
    expect(
      source,
      isNot(contains('late final CloudUsageClient _cloudUsageClient =')),
    );
    expect(
      source,
      isNot(contains('late final VaultUsageClient _vaultUsageClient =')),
    );
    expect(
      source,
      isNot(
        contains(
          'late final VaultAttachmentsClient _vaultAttachmentsClient =',
        ),
      ),
    );
  });
}
