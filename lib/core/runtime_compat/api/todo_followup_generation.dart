import '../../models/app_models.dart';
import '../../models/platform_int.dart';

Future<List<TodoFollowupGenerationJob>> dbListDueAutoTodoFollowupGenerationJobs(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListDueAutoTodoFollowupGenerationJobs');
