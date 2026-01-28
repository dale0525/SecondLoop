abstract class CloudMediaBackupClient {
  Future<void> upload({
    required String attachmentSha256,
    required String desiredVariant,
  });
}
