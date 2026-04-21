typedef FollowupUpdatedStatusBuilder = String Function({
  required String title,
  required String status,
});
typedef FollowupUpdatedSimpleBuilder = String Function({
  required String title,
});

String buildFollowupUpdateFeedbackText({
  required String title,
  required bool didUpdateStatus,
  required bool didUpdateDue,
  required String statusLabel,
  required FollowupUpdatedStatusBuilder updatedStatusBuilder,
  required FollowupUpdatedSimpleBuilder updatedDueBuilder,
  required FollowupUpdatedSimpleBuilder updatedStatusAndDueBuilder,
}) {
  if (didUpdateStatus && didUpdateDue) {
    return updatedStatusAndDueBuilder(title: title);
  }
  if (didUpdateDue) {
    return updatedDueBuilder(title: title);
  }
  return updatedStatusBuilder(title: title, status: statusLabel);
}
