export async function refreshRuntimeAfterProjectSave(options: {
  refreshRuntime?: () => Promise<void>;
  restorePreviousProject: () => Promise<void>;
}): Promise<void> {
  if (!options.refreshRuntime) return;
  try {
    await options.refreshRuntime();
    return;
  } catch {
    try {
      await options.restorePreviousProject();
    } catch {
      throw new Error(
        "The Agent runtime could not reload the developer project and the previous project could not be restored",
      );
    }
  }
  try {
    await options.refreshRuntime();
  } catch {
    throw new Error(
      "The previous developer project was restored on disk, but the Agent runtime could not restart",
    );
  }
  throw new Error(
    "The Agent runtime rejected the developer project; the previous project was restored",
  );
}
