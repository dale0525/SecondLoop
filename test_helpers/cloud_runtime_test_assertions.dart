import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';

void expectRuntimeResponseType(
  RuntimeTestRunResult run,
  String responseType,
) {
  expect(run.metadata['response_type'], responseType);
}

void expectApprovalRequired(
  RuntimeTestRunResult run, {
  required bool value,
}) {
  expect(run.metadata['approval_required'], value);
}

void expectChangedPath(
  RuntimeTestStateDiff diff,
  String changedPath,
) {
  expect(diff.changedPaths, contains(changedPath));
}

void expectApprovalKind(
  RuntimeTestApprovalItem item,
  String kind,
) {
  expect(item.kind, kind);
}
