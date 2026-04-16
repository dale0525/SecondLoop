abstract interface class WebLocalRuntimeRecovery {
  bool hasAttemptedReset({required String uid});

  void markResetAttempted({required String uid});

  void clearResetAttempted({required String uid});

  Future<void> reloadPage();
}
