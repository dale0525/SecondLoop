import 'package:secondloop/core/cloud/runtime_test_client.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';

final class CloudRuntimeTestFixtureLoader {
  CloudRuntimeTestFixtureLoader({
    RuntimeTestClient? client,
  }) : _client = client ?? RuntimeTestClient();

  final RuntimeTestClient _client;

  Future<void> loadStandardWorkingSet(String vaultId) {
    const weeklyReviewTask = RuntimeTestFixtureRecord(
      kind: 'task',
      id: 'task-weekly-review',
      fields: {
        'title': '完成周报',
        'status': 'todo',
        'priority': 'high',
      },
    );
    const dentistTask = RuntimeTestFixtureRecord(
      kind: 'task',
      id: 'task-dentist',
      fields: {
        'title': '预约牙医复诊',
        'status': 'todo',
        'priority': 'medium',
      },
    );
    const morningMemory = RuntimeTestFixtureRecord(
      kind: 'memory',
      id: 'memory-morning',
      fields: {
        'title': '用户偏好上午 9 点前不开会',
      },
    );
    const runtimeMigrationSummary = RuntimeTestFixtureRecord(
      kind: 'summary',
      id: 'summary-runtime-migration',
      fields: {
        'body': '最近在推进 Cloudflare Agents 架构切换',
      },
    );

    return _client.injectWorkingSetFixtures(
      vaultId: vaultId,
      tasks: [
        weeklyReviewTask.toJson(),
        dentistTask.toJson(),
      ],
      memories: [
        morningMemory.toJson(),
      ],
      conversationSummaries: [
        runtimeMigrationSummary.toJson(),
      ],
    );
  }
}
