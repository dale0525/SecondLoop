import 'platform_int.dart';

class Attachment {
  final String sha256;
  final String mimeType;
  final String path;
  final PlatformInt64 byteLen;
  final PlatformInt64 createdAtMs;

  const Attachment({
    required this.sha256,
    required this.mimeType,
    required this.path,
    required this.byteLen,
    required this.createdAtMs,
  });

  @override
  int get hashCode =>
      sha256.hashCode ^
      mimeType.hashCode ^
      path.hashCode ^
      byteLen.hashCode ^
      createdAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attachment &&
          runtimeType == other.runtimeType &&
          sha256 == other.sha256 &&
          mimeType == other.mimeType &&
          path == other.path &&
          byteLen == other.byteLen &&
          createdAtMs == other.createdAtMs;
}

class AttachmentAnnotationJob {
  final String attachmentSha256;
  final String status;
  final String lang;
  final String? modelName;
  final PlatformInt64 attempts;
  final PlatformInt64? nextRetryAtMs;
  final String? lastError;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const AttachmentAnnotationJob({
    required this.attachmentSha256,
    required this.status,
    required this.lang,
    this.modelName,
    required this.attempts,
    this.nextRetryAtMs,
    this.lastError,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      attachmentSha256.hashCode ^
      status.hashCode ^
      lang.hashCode ^
      modelName.hashCode ^
      attempts.hashCode ^
      nextRetryAtMs.hashCode ^
      lastError.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentAnnotationJob &&
          runtimeType == other.runtimeType &&
          attachmentSha256 == other.attachmentSha256 &&
          status == other.status &&
          lang == other.lang &&
          modelName == other.modelName &&
          attempts == other.attempts &&
          nextRetryAtMs == other.nextRetryAtMs &&
          lastError == other.lastError &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class AttachmentExifMetadata {
  final PlatformInt64? capturedAtMs;
  final double? latitude;
  final double? longitude;

  const AttachmentExifMetadata({
    this.capturedAtMs,
    this.latitude,
    this.longitude,
  });

  @override
  int get hashCode =>
      capturedAtMs.hashCode ^ latitude.hashCode ^ longitude.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentExifMetadata &&
          runtimeType == other.runtimeType &&
          capturedAtMs == other.capturedAtMs &&
          latitude == other.latitude &&
          longitude == other.longitude;
}

class AttachmentMetadata {
  final String? title;
  final List<String> filenames;
  final List<String> sourceUrls;
  final PlatformInt64 titleUpdatedAtMs;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const AttachmentMetadata({
    this.title,
    required this.filenames,
    required this.sourceUrls,
    required this.titleUpdatedAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      title.hashCode ^
      filenames.hashCode ^
      sourceUrls.hashCode ^
      titleUpdatedAtMs.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentMetadata &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          filenames == other.filenames &&
          sourceUrls == other.sourceUrls &&
          titleUpdatedAtMs == other.titleUpdatedAtMs &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class AttachmentPlaceJob {
  final String attachmentSha256;
  final String status;
  final String lang;
  final PlatformInt64 attempts;
  final PlatformInt64? nextRetryAtMs;
  final String? lastError;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const AttachmentPlaceJob({
    required this.attachmentSha256,
    required this.status,
    required this.lang,
    required this.attempts,
    this.nextRetryAtMs,
    this.lastError,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      attachmentSha256.hashCode ^
      status.hashCode ^
      lang.hashCode ^
      attempts.hashCode ^
      nextRetryAtMs.hashCode ^
      lastError.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentPlaceJob &&
          runtimeType == other.runtimeType &&
          attachmentSha256 == other.attachmentSha256 &&
          status == other.status &&
          lang == other.lang &&
          attempts == other.attempts &&
          nextRetryAtMs == other.nextRetryAtMs &&
          lastError == other.lastError &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class AttachmentVariant {
  final String attachmentSha256;
  final String variant;
  final String mimeType;
  final String path;
  final PlatformInt64 byteLen;
  final PlatformInt64 createdAtMs;

  const AttachmentVariant({
    required this.attachmentSha256,
    required this.variant,
    required this.mimeType,
    required this.path,
    required this.byteLen,
    required this.createdAtMs,
  });

  @override
  int get hashCode =>
      attachmentSha256.hashCode ^
      variant.hashCode ^
      mimeType.hashCode ^
      path.hashCode ^
      byteLen.hashCode ^
      createdAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentVariant &&
          runtimeType == other.runtimeType &&
          attachmentSha256 == other.attachmentSha256 &&
          variant == other.variant &&
          mimeType == other.mimeType &&
          path == other.path &&
          byteLen == other.byteLen &&
          createdAtMs == other.createdAtMs;
}

class CloudMediaBackup {
  final String attachmentSha256;
  final String desiredVariant;
  final PlatformInt64 byteLen;
  final String status;
  final PlatformInt64 attempts;
  final PlatformInt64? nextRetryAtMs;
  final String? lastError;
  final PlatformInt64 updatedAtMs;

  const CloudMediaBackup({
    required this.attachmentSha256,
    required this.desiredVariant,
    required this.byteLen,
    required this.status,
    required this.attempts,
    this.nextRetryAtMs,
    this.lastError,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      attachmentSha256.hashCode ^
      desiredVariant.hashCode ^
      byteLen.hashCode ^
      status.hashCode ^
      attempts.hashCode ^
      nextRetryAtMs.hashCode ^
      lastError.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudMediaBackup &&
          runtimeType == other.runtimeType &&
          attachmentSha256 == other.attachmentSha256 &&
          desiredVariant == other.desiredVariant &&
          byteLen == other.byteLen &&
          status == other.status &&
          attempts == other.attempts &&
          nextRetryAtMs == other.nextRetryAtMs &&
          lastError == other.lastError &&
          updatedAtMs == other.updatedAtMs;
}

class CloudMediaBackupSummary {
  final PlatformInt64 pending;
  final PlatformInt64 failed;
  final PlatformInt64 uploaded;
  final PlatformInt64? lastUploadedAtMs;
  final String? lastError;
  final PlatformInt64? lastErrorAtMs;

  const CloudMediaBackupSummary({
    required this.pending,
    required this.failed,
    required this.uploaded,
    this.lastUploadedAtMs,
    this.lastError,
    this.lastErrorAtMs,
  });

  @override
  int get hashCode =>
      pending.hashCode ^
      failed.hashCode ^
      uploaded.hashCode ^
      lastUploadedAtMs.hashCode ^
      lastError.hashCode ^
      lastErrorAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudMediaBackupSummary &&
          runtimeType == other.runtimeType &&
          pending == other.pending &&
          failed == other.failed &&
          uploaded == other.uploaded &&
          lastUploadedAtMs == other.lastUploadedAtMs &&
          lastError == other.lastError &&
          lastErrorAtMs == other.lastErrorAtMs;
}

class ContentEnrichmentConfig {
  final bool urlFetchEnabled;
  final bool documentExtractEnabled;
  final PlatformInt64 documentKeepOriginalMaxBytes;
  final bool audioTranscribeEnabled;
  final String audioTranscribeEngine;
  final bool videoExtractEnabled;
  final bool videoProxyEnabled;
  final PlatformInt64 videoProxyMaxDurationMs;
  final PlatformInt64 videoProxyMaxBytes;
  final bool ocrEnabled;
  final String ocrEngineMode;
  final String ocrLanguageHints;
  final PlatformInt64 ocrPdfDpi;
  final PlatformInt64 ocrPdfAutoMaxPages;
  final PlatformInt64 ocrPdfMaxPages;
  final bool mobileBackgroundEnabled;
  final bool mobileBackgroundRequiresWifi;
  final bool mobileBackgroundRequiresCharging;

  const ContentEnrichmentConfig({
    required this.urlFetchEnabled,
    required this.documentExtractEnabled,
    required this.documentKeepOriginalMaxBytes,
    required this.audioTranscribeEnabled,
    required this.audioTranscribeEngine,
    required this.videoExtractEnabled,
    required this.videoProxyEnabled,
    required this.videoProxyMaxDurationMs,
    required this.videoProxyMaxBytes,
    required this.ocrEnabled,
    required this.ocrEngineMode,
    required this.ocrLanguageHints,
    required this.ocrPdfDpi,
    required this.ocrPdfAutoMaxPages,
    required this.ocrPdfMaxPages,
    required this.mobileBackgroundEnabled,
    required this.mobileBackgroundRequiresWifi,
    required this.mobileBackgroundRequiresCharging,
  });

  @override
  int get hashCode =>
      urlFetchEnabled.hashCode ^
      documentExtractEnabled.hashCode ^
      documentKeepOriginalMaxBytes.hashCode ^
      audioTranscribeEnabled.hashCode ^
      audioTranscribeEngine.hashCode ^
      videoExtractEnabled.hashCode ^
      videoProxyEnabled.hashCode ^
      videoProxyMaxDurationMs.hashCode ^
      videoProxyMaxBytes.hashCode ^
      ocrEnabled.hashCode ^
      ocrEngineMode.hashCode ^
      ocrLanguageHints.hashCode ^
      ocrPdfDpi.hashCode ^
      ocrPdfAutoMaxPages.hashCode ^
      ocrPdfMaxPages.hashCode ^
      mobileBackgroundEnabled.hashCode ^
      mobileBackgroundRequiresWifi.hashCode ^
      mobileBackgroundRequiresCharging.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentEnrichmentConfig &&
          runtimeType == other.runtimeType &&
          urlFetchEnabled == other.urlFetchEnabled &&
          documentExtractEnabled == other.documentExtractEnabled &&
          documentKeepOriginalMaxBytes == other.documentKeepOriginalMaxBytes &&
          audioTranscribeEnabled == other.audioTranscribeEnabled &&
          audioTranscribeEngine == other.audioTranscribeEngine &&
          videoExtractEnabled == other.videoExtractEnabled &&
          videoProxyEnabled == other.videoProxyEnabled &&
          videoProxyMaxDurationMs == other.videoProxyMaxDurationMs &&
          videoProxyMaxBytes == other.videoProxyMaxBytes &&
          ocrEnabled == other.ocrEnabled &&
          ocrEngineMode == other.ocrEngineMode &&
          ocrLanguageHints == other.ocrLanguageHints &&
          ocrPdfDpi == other.ocrPdfDpi &&
          ocrPdfAutoMaxPages == other.ocrPdfAutoMaxPages &&
          ocrPdfMaxPages == other.ocrPdfMaxPages &&
          mobileBackgroundEnabled == other.mobileBackgroundEnabled &&
          mobileBackgroundRequiresWifi == other.mobileBackgroundRequiresWifi &&
          mobileBackgroundRequiresCharging ==
              other.mobileBackgroundRequiresCharging;
}

class Conversation {
  final String id;
  final String title;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class EmbeddingProfile {
  final String id;
  final String name;
  final String providerType;
  final String? baseUrl;
  final String modelName;
  final bool isActive;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const EmbeddingProfile({
    required this.id,
    required this.name,
    required this.providerType,
    this.baseUrl,
    required this.modelName,
    required this.isActive,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      providerType.hashCode ^
      baseUrl.hashCode ^
      modelName.hashCode ^
      isActive.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmbeddingProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          providerType == other.providerType &&
          baseUrl == other.baseUrl &&
          modelName == other.modelName &&
          isActive == other.isActive &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class Event {
  final String id;
  final String title;
  final PlatformInt64 startAtMs;
  final PlatformInt64 endAtMs;
  final String tz;
  final String? sourceEntryId;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const Event({
    required this.id,
    required this.title,
    required this.startAtMs,
    required this.endAtMs,
    required this.tz,
    this.sourceEntryId,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      startAtMs.hashCode ^
      endAtMs.hashCode ^
      tz.hashCode ^
      sourceEntryId.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          startAtMs == other.startAtMs &&
          endAtMs == other.endAtMs &&
          tz == other.tz &&
          sourceEntryId == other.sourceEntryId &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class LlmProfile {
  final String id;
  final String name;
  final String providerType;
  final String? baseUrl;
  final String modelName;
  final bool isActive;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const LlmProfile({
    required this.id,
    required this.name,
    required this.providerType,
    this.baseUrl,
    required this.modelName,
    required this.isActive,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      providerType.hashCode ^
      baseUrl.hashCode ^
      modelName.hashCode ^
      isActive.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          providerType == other.providerType &&
          baseUrl == other.baseUrl &&
          modelName == other.modelName &&
          isActive == other.isActive &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class LlmUsageAggregate {
  final String purpose;
  final PlatformInt64 requests;
  final PlatformInt64 requestsWithUsage;
  final PlatformInt64 inputTokens;
  final PlatformInt64 outputTokens;
  final PlatformInt64 totalTokens;

  const LlmUsageAggregate({
    required this.purpose,
    required this.requests,
    required this.requestsWithUsage,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  @override
  int get hashCode =>
      purpose.hashCode ^
      requests.hashCode ^
      requestsWithUsage.hashCode ^
      inputTokens.hashCode ^
      outputTokens.hashCode ^
      totalTokens.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmUsageAggregate &&
          runtimeType == other.runtimeType &&
          purpose == other.purpose &&
          requests == other.requests &&
          requestsWithUsage == other.requestsWithUsage &&
          inputTokens == other.inputTokens &&
          outputTokens == other.outputTokens &&
          totalTokens == other.totalTokens;
}

class MediaAnnotationConfig {
  final bool annotateEnabled;
  final bool searchEnabled;
  final bool allowCellular;
  final String providerMode;
  final String? byokProfileId;
  final String? cloudModelName;

  const MediaAnnotationConfig({
    required this.annotateEnabled,
    required this.searchEnabled,
    required this.allowCellular,
    required this.providerMode,
    this.byokProfileId,
    this.cloudModelName,
  });

  @override
  int get hashCode =>
      annotateEnabled.hashCode ^
      searchEnabled.hashCode ^
      allowCellular.hashCode ^
      providerMode.hashCode ^
      byokProfileId.hashCode ^
      cloudModelName.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaAnnotationConfig &&
          runtimeType == other.runtimeType &&
          annotateEnabled == other.annotateEnabled &&
          searchEnabled == other.searchEnabled &&
          allowCellular == other.allowCellular &&
          providerMode == other.providerMode &&
          byokProfileId == other.byokProfileId &&
          cloudModelName == other.cloudModelName;
}

class MemoryPageRecord {
  final String pageId;
  final String pageType;
  final String state;
  final PlatformInt64 sourceCount;
  final String title;
  final String summary;
  final String body;
  final String primaryEvidenceJson;
  final String sourceDocumentIdsJson;
  final double confidenceLevel;
  final bool humanCorrected;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const MemoryPageRecord({
    required this.pageId,
    required this.pageType,
    required this.state,
    required this.sourceCount,
    required this.title,
    required this.summary,
    required this.body,
    required this.primaryEvidenceJson,
    required this.sourceDocumentIdsJson,
    required this.confidenceLevel,
    required this.humanCorrected,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      pageId.hashCode ^
      pageType.hashCode ^
      state.hashCode ^
      sourceCount.hashCode ^
      title.hashCode ^
      summary.hashCode ^
      body.hashCode ^
      primaryEvidenceJson.hashCode ^
      sourceDocumentIdsJson.hashCode ^
      confidenceLevel.hashCode ^
      humanCorrected.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryPageRecord &&
          runtimeType == other.runtimeType &&
          pageId == other.pageId &&
          pageType == other.pageType &&
          state == other.state &&
          sourceCount == other.sourceCount &&
          title == other.title &&
          summary == other.summary &&
          body == other.body &&
          primaryEvidenceJson == other.primaryEvidenceJson &&
          sourceDocumentIdsJson == other.sourceDocumentIdsJson &&
          confidenceLevel == other.confidenceLevel &&
          humanCorrected == other.humanCorrected &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class Message {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final PlatformInt64 createdAtMs;
  final bool isMemory;
  final String? citationsJson;

  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAtMs,
    required this.isMemory,
    this.citationsJson,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      conversationId.hashCode ^
      role.hashCode ^
      content.hashCode ^
      createdAtMs.hashCode ^
      isMemory.hashCode ^
      citationsJson.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          conversationId == other.conversationId &&
          role == other.role &&
          content == other.content &&
          createdAtMs == other.createdAtMs &&
          isMemory == other.isMemory &&
          citationsJson == other.citationsJson;
}

class PlanningOutputRecord {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String itemsJson;
  final String? sourceRefsJson;
  final String route;
  final String state;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;
  final PlatformInt64? expiresAtMs;
  final PlatformInt64? dismissedAtMs;

  const PlanningOutputRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.itemsJson,
    this.sourceRefsJson,
    required this.route,
    required this.state,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.expiresAtMs,
    this.dismissedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      kind.hashCode ^
      title.hashCode ^
      body.hashCode ^
      itemsJson.hashCode ^
      sourceRefsJson.hashCode ^
      route.hashCode ^
      state.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode ^
      expiresAtMs.hashCode ^
      dismissedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanningOutputRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          title == other.title &&
          body == other.body &&
          itemsJson == other.itemsJson &&
          sourceRefsJson == other.sourceRefsJson &&
          route == other.route &&
          state == other.state &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs &&
          expiresAtMs == other.expiresAtMs &&
          dismissedAtMs == other.dismissedAtMs;
}

class SecretaryMemoryProposalRecord {
  final String id;
  final String? sourceMessageId;
  final String kind;
  final String title;
  final String body;
  final double confidence;
  final String state;
  final String? sourceRefsJson;
  final String? actionHint;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;
  final PlatformInt64? acceptedAtMs;
  final PlatformInt64? dismissedAtMs;

  const SecretaryMemoryProposalRecord({
    required this.id,
    this.sourceMessageId,
    required this.kind,
    required this.title,
    required this.body,
    required this.confidence,
    required this.state,
    this.sourceRefsJson,
    this.actionHint,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.acceptedAtMs,
    this.dismissedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      sourceMessageId.hashCode ^
      kind.hashCode ^
      title.hashCode ^
      body.hashCode ^
      confidence.hashCode ^
      state.hashCode ^
      sourceRefsJson.hashCode ^
      actionHint.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode ^
      acceptedAtMs.hashCode ^
      dismissedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecretaryMemoryProposalRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceMessageId == other.sourceMessageId &&
          kind == other.kind &&
          title == other.title &&
          body == other.body &&
          confidence == other.confidence &&
          state == other.state &&
          sourceRefsJson == other.sourceRefsJson &&
          actionHint == other.actionHint &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs &&
          acceptedAtMs == other.acceptedAtMs &&
          dismissedAtMs == other.dismissedAtMs;
}

class SecretaryRunRecord {
  final String id;
  final String triggerKind;
  final String route;
  final String status;
  final String? inputSummary;
  final String? outputSummary;
  final String? error;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const SecretaryRunRecord({
    required this.id,
    required this.triggerKind,
    required this.route,
    required this.status,
    this.inputSummary,
    this.outputSummary,
    this.error,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      triggerKind.hashCode ^
      route.hashCode ^
      status.hashCode ^
      inputSummary.hashCode ^
      outputSummary.hashCode ^
      error.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecretaryRunRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          triggerKind == other.triggerKind &&
          route == other.route &&
          status == other.status &&
          inputSummary == other.inputSummary &&
          outputSummary == other.outputSummary &&
          error == other.error &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class SecretaryToolCallRecord {
  final String id;
  final String runId;
  final String toolName;
  final String status;
  final bool requiresConfirmation;
  final String? inputJson;
  final String? outputJson;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const SecretaryToolCallRecord({
    required this.id,
    required this.runId,
    required this.toolName,
    required this.status,
    required this.requiresConfirmation,
    this.inputJson,
    this.outputJson,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      runId.hashCode ^
      toolName.hashCode ^
      status.hashCode ^
      requiresConfirmation.hashCode ^
      inputJson.hashCode ^
      outputJson.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecretaryToolCallRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          runId == other.runId &&
          toolName == other.toolName &&
          status == other.status &&
          requiresConfirmation == other.requiresConfirmation &&
          inputJson == other.inputJson &&
          outputJson == other.outputJson &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class SemanticParseJob {
  final String messageId;
  final String status;
  final PlatformInt64 attemptId;
  final PlatformInt64 attempts;
  final PlatformInt64? nextRetryAtMs;
  final String? lastError;
  final String? appliedActionKind;
  final String? appliedTodoId;
  final String? appliedTodoTitle;
  final String? appliedPrevTodoStatus;
  final PlatformInt64? appliedPrevTodoDueAtMs;
  final bool appliedDueChanged;
  final List<String>? suggestedTags;
  final double? suggestedTagConfidence;
  final String? tagSuggestionState;
  final List<String>? appliedTagIds;
  final PlatformInt64? undoneAtMs;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const SemanticParseJob({
    required this.messageId,
    required this.status,
    required this.attemptId,
    required this.attempts,
    this.nextRetryAtMs,
    this.lastError,
    this.appliedActionKind,
    this.appliedTodoId,
    this.appliedTodoTitle,
    this.appliedPrevTodoStatus,
    this.appliedPrevTodoDueAtMs,
    required this.appliedDueChanged,
    this.suggestedTags,
    this.suggestedTagConfidence,
    this.tagSuggestionState,
    this.appliedTagIds,
    this.undoneAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      messageId.hashCode ^
      status.hashCode ^
      attemptId.hashCode ^
      attempts.hashCode ^
      nextRetryAtMs.hashCode ^
      lastError.hashCode ^
      appliedActionKind.hashCode ^
      appliedTodoId.hashCode ^
      appliedTodoTitle.hashCode ^
      appliedPrevTodoStatus.hashCode ^
      appliedPrevTodoDueAtMs.hashCode ^
      appliedDueChanged.hashCode ^
      suggestedTags.hashCode ^
      suggestedTagConfidence.hashCode ^
      tagSuggestionState.hashCode ^
      appliedTagIds.hashCode ^
      undoneAtMs.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemanticParseJob &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId &&
          status == other.status &&
          attemptId == other.attemptId &&
          attempts == other.attempts &&
          nextRetryAtMs == other.nextRetryAtMs &&
          lastError == other.lastError &&
          appliedActionKind == other.appliedActionKind &&
          appliedTodoId == other.appliedTodoId &&
          appliedTodoTitle == other.appliedTodoTitle &&
          appliedPrevTodoStatus == other.appliedPrevTodoStatus &&
          appliedPrevTodoDueAtMs == other.appliedPrevTodoDueAtMs &&
          appliedDueChanged == other.appliedDueChanged &&
          suggestedTags == other.suggestedTags &&
          suggestedTagConfidence == other.suggestedTagConfidence &&
          tagSuggestionState == other.tagSuggestionState &&
          appliedTagIds == other.appliedTagIds &&
          undoneAtMs == other.undoneAtMs &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class SimilarMessage {
  final Message message;
  final double distance;

  const SimilarMessage({
    required this.message,
    required this.distance,
  });

  @override
  int get hashCode => message.hashCode ^ distance.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimilarMessage &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          distance == other.distance;
}

class SimilarTodoThread {
  final String todoId;
  final double distance;

  const SimilarTodoThread({
    required this.todoId,
    required this.distance,
  });

  @override
  int get hashCode => todoId.hashCode ^ distance.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimilarTodoThread &&
          runtimeType == other.runtimeType &&
          todoId == other.todoId &&
          distance == other.distance;
}

class StoragePolicyConfig {
  final bool autoPurgeEnabled;
  final PlatformInt64 autoPurgeKeepRecentDays;
  final PlatformInt64 autoPurgeMaxCacheBytes;
  final PlatformInt64 autoPurgeMinCandidateBytes;
  final bool autoPurgeIncludeImages;

  const StoragePolicyConfig({
    required this.autoPurgeEnabled,
    required this.autoPurgeKeepRecentDays,
    required this.autoPurgeMaxCacheBytes,
    required this.autoPurgeMinCandidateBytes,
    required this.autoPurgeIncludeImages,
  });

  @override
  int get hashCode =>
      autoPurgeEnabled.hashCode ^
      autoPurgeKeepRecentDays.hashCode ^
      autoPurgeMaxCacheBytes.hashCode ^
      autoPurgeMinCandidateBytes.hashCode ^
      autoPurgeIncludeImages.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoragePolicyConfig &&
          runtimeType == other.runtimeType &&
          autoPurgeEnabled == other.autoPurgeEnabled &&
          autoPurgeKeepRecentDays == other.autoPurgeKeepRecentDays &&
          autoPurgeMaxCacheBytes == other.autoPurgeMaxCacheBytes &&
          autoPurgeMinCandidateBytes == other.autoPurgeMinCandidateBytes &&
          autoPurgeIncludeImages == other.autoPurgeIncludeImages;
}

class Tag {
  final String id;
  final String name;
  final String? systemKey;
  final bool isSystem;
  final String? color;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const Tag({
    required this.id,
    required this.name,
    this.systemKey,
    required this.isSystem,
    this.color,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      systemKey.hashCode ^
      isSystem.hashCode ^
      color.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          systemKey == other.systemKey &&
          isSystem == other.isSystem &&
          color == other.color &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class TagMergeSuggestion {
  final Tag sourceTag;
  final Tag targetTag;
  final String reason;
  final double score;
  final PlatformInt64 sourceUsageCount;
  final PlatformInt64 targetUsageCount;

  const TagMergeSuggestion({
    required this.sourceTag,
    required this.targetTag,
    required this.reason,
    required this.score,
    required this.sourceUsageCount,
    required this.targetUsageCount,
  });

  @override
  int get hashCode =>
      sourceTag.hashCode ^
      targetTag.hashCode ^
      reason.hashCode ^
      score.hashCode ^
      sourceUsageCount.hashCode ^
      targetUsageCount.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagMergeSuggestion &&
          runtimeType == other.runtimeType &&
          sourceTag == other.sourceTag &&
          targetTag == other.targetTag &&
          reason == other.reason &&
          score == other.score &&
          sourceUsageCount == other.sourceUsageCount &&
          targetUsageCount == other.targetUsageCount;
}

class Todo {
  final String id;
  final String title;
  final PlatformInt64? dueAtMs;
  final String status;
  final String? sourceEntryId;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;
  final PlatformInt64? reviewStage;
  final PlatformInt64? nextReviewAtMs;
  final PlatformInt64? lastReviewAtMs;
  final PlatformInt64? manualImportanceNudgeScore;
  final PlatformInt64? manualUrgencyNudgeScore;

  const Todo({
    required this.id,
    required this.title,
    this.dueAtMs,
    required this.status,
    this.sourceEntryId,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.reviewStage,
    this.nextReviewAtMs,
    this.lastReviewAtMs,
    this.manualImportanceNudgeScore,
    this.manualUrgencyNudgeScore,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      dueAtMs.hashCode ^
      status.hashCode ^
      sourceEntryId.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode ^
      reviewStage.hashCode ^
      nextReviewAtMs.hashCode ^
      lastReviewAtMs.hashCode ^
      manualImportanceNudgeScore.hashCode ^
      manualUrgencyNudgeScore.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          dueAtMs == other.dueAtMs &&
          status == other.status &&
          sourceEntryId == other.sourceEntryId &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs &&
          reviewStage == other.reviewStage &&
          nextReviewAtMs == other.nextReviewAtMs &&
          lastReviewAtMs == other.lastReviewAtMs &&
          manualImportanceNudgeScore == other.manualImportanceNudgeScore &&
          manualUrgencyNudgeScore == other.manualUrgencyNudgeScore;
}

class TodoActivity {
  final String id;
  final String todoId;
  final String activityType;
  final String? fromStatus;
  final String? toStatus;
  final String? content;
  final String? sourceMessageId;
  final PlatformInt64 createdAtMs;

  const TodoActivity({
    required this.id,
    required this.todoId,
    required this.activityType,
    this.fromStatus,
    this.toStatus,
    this.content,
    this.sourceMessageId,
    required this.createdAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      todoId.hashCode ^
      activityType.hashCode ^
      fromStatus.hashCode ^
      toStatus.hashCode ^
      content.hashCode ^
      sourceMessageId.hashCode ^
      createdAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoActivity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          todoId == other.todoId &&
          activityType == other.activityType &&
          fromStatus == other.fromStatus &&
          toStatus == other.toStatus &&
          content == other.content &&
          sourceMessageId == other.sourceMessageId &&
          createdAtMs == other.createdAtMs;
}

class TodoChecklistItem {
  final String id;
  final String todoId;
  final String content;
  final bool isDone;
  final PlatformInt64 sortOrder;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const TodoChecklistItem({
    required this.id,
    required this.todoId,
    required this.content,
    required this.isDone,
    required this.sortOrder,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      todoId.hashCode ^
      content.hashCode ^
      isDone.hashCode ^
      sortOrder.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoChecklistItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          todoId == other.todoId &&
          content == other.content &&
          isDone == other.isDone &&
          sortOrder == other.sortOrder &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class TodoChecklistProgress {
  final String todoId;
  final PlatformInt64 doneCount;
  final PlatformInt64 totalCount;

  const TodoChecklistProgress({
    required this.todoId,
    required this.doneCount,
    required this.totalCount,
  });

  @override
  int get hashCode =>
      todoId.hashCode ^ doneCount.hashCode ^ totalCount.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoChecklistProgress &&
          runtimeType == other.runtimeType &&
          todoId == other.todoId &&
          doneCount == other.doneCount &&
          totalCount == other.totalCount;
}

class TodoChecklistSuggestion {
  final String id;
  final String todoId;
  final String content;
  final PlatformInt64 sortOrder;
  final String state;
  final String source;
  final String? generationKey;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;
  final PlatformInt64? dismissedAtMs;
  final String? appliedChecklistItemId;

  const TodoChecklistSuggestion({
    required this.id,
    required this.todoId,
    required this.content,
    required this.sortOrder,
    required this.state,
    required this.source,
    this.generationKey,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.dismissedAtMs,
    this.appliedChecklistItemId,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      todoId.hashCode ^
      content.hashCode ^
      sortOrder.hashCode ^
      state.hashCode ^
      source.hashCode ^
      generationKey.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode ^
      dismissedAtMs.hashCode ^
      appliedChecklistItemId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoChecklistSuggestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          todoId == other.todoId &&
          content == other.content &&
          sortOrder == other.sortOrder &&
          state == other.state &&
          source == other.source &&
          generationKey == other.generationKey &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs &&
          dismissedAtMs == other.dismissedAtMs &&
          appliedChecklistItemId == other.appliedChecklistItemId;
}

class TodoFollowupGenerationJob {
  final String todoId;
  final String triggerKind;
  final String status;
  final PlatformInt64 attempts;
  final PlatformInt64? nextRetryAtMs;
  final String? lastError;
  final bool includeManualFollowups;
  final bool manualOverrideFollowup;
  final String? taskTypeHint;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;

  const TodoFollowupGenerationJob({
    required this.todoId,
    required this.triggerKind,
    required this.status,
    required this.attempts,
    this.nextRetryAtMs,
    this.lastError,
    required this.includeManualFollowups,
    required this.manualOverrideFollowup,
    this.taskTypeHint,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @override
  int get hashCode =>
      todoId.hashCode ^
      triggerKind.hashCode ^
      status.hashCode ^
      attempts.hashCode ^
      nextRetryAtMs.hashCode ^
      lastError.hashCode ^
      includeManualFollowups.hashCode ^
      manualOverrideFollowup.hashCode ^
      taskTypeHint.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoFollowupGenerationJob &&
          runtimeType == other.runtimeType &&
          todoId == other.todoId &&
          triggerKind == other.triggerKind &&
          status == other.status &&
          attempts == other.attempts &&
          nextRetryAtMs == other.nextRetryAtMs &&
          lastError == other.lastError &&
          includeManualFollowups == other.includeManualFollowups &&
          manualOverrideFollowup == other.manualOverrideFollowup &&
          taskTypeHint == other.taskTypeHint &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs;
}

class TodoFollowupSuggestion {
  final String id;
  final String todoId;
  final String content;
  final String state;
  final String source;
  final String generationMode;
  final String? generationKey;
  final String? citationsJson;
  final PlatformInt64 createdAtMs;
  final PlatformInt64 updatedAtMs;
  final PlatformInt64? dismissedAtMs;
  final String? appliedActivityId;

  const TodoFollowupSuggestion({
    required this.id,
    required this.todoId,
    required this.content,
    required this.state,
    required this.source,
    required this.generationMode,
    this.generationKey,
    this.citationsJson,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.dismissedAtMs,
    this.appliedActivityId,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      todoId.hashCode ^
      content.hashCode ^
      state.hashCode ^
      source.hashCode ^
      generationMode.hashCode ^
      generationKey.hashCode ^
      citationsJson.hashCode ^
      createdAtMs.hashCode ^
      updatedAtMs.hashCode ^
      dismissedAtMs.hashCode ^
      appliedActivityId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoFollowupSuggestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          todoId == other.todoId &&
          content == other.content &&
          state == other.state &&
          source == other.source &&
          generationMode == other.generationMode &&
          generationKey == other.generationKey &&
          citationsJson == other.citationsJson &&
          createdAtMs == other.createdAtMs &&
          updatedAtMs == other.updatedAtMs &&
          dismissedAtMs == other.dismissedAtMs &&
          appliedActivityId == other.appliedActivityId;
}

class TodoFollowupSuggestionDraftInput {
  final String content;
  final String generationMode;
  final String? citationsJson;

  const TodoFollowupSuggestionDraftInput({
    required this.content,
    required this.generationMode,
    this.citationsJson,
  });

  @override
  int get hashCode =>
      content.hashCode ^ generationMode.hashCode ^ citationsJson.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoFollowupSuggestionDraftInput &&
          runtimeType == other.runtimeType &&
          content == other.content &&
          generationMode == other.generationMode &&
          citationsJson == other.citationsJson;
}
