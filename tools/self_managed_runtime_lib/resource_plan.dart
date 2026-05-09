final class SelfManagedRuntimeResourcePlan {
  const SelfManagedRuntimeResourcePlan({
    required this.workerNames,
    required this.bindings,
    required this.secrets,
  });

  final List<String> workerNames;
  final List<String> bindings;
  final List<String> secrets;
}

SelfManagedRuntimeResourcePlan buildSelfManagedRuntimeResourcePlan() {
  return const SelfManagedRuntimeResourcePlan(
    workerNames: [
      'secretary-runtime',
      'model-gateway',
      'vault-service',
    ],
    bindings: [
      'D1',
      'KV',
      'R2',
      'SECRETARY_AGENT',
    ],
    secrets: [
      'LLM_API_KEY',
      'EMBEDDING_API_KEY',
      'MULTIMODAL_LLM_API_KEY',
    ],
  );
}
