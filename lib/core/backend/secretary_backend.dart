import 'dart:typed_data';

import '../../src/rust/db.dart';

abstract interface class SecretaryBackend {
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  });

  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  });

  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  });

  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  });

  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  });

  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  });

  Future<MemoryPageRecord> correctMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    String? reason,
    required int nowMs,
  });

  Future<MemoryPageRecord> archiveMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  });

  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  });

  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  });

  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  });
}
