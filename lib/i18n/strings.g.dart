/// Generated file. Do not edit.
///
/// Original: lib/i18n
/// To regenerate, run: `dart run slang`
///
/// Locales: 2
/// Strings: 1604 (802 per locale)
///
/// Built on 2026-02-20 at 02:51 UTC

// coverage:ignore-file
// ignore_for_file: type=lint

import 'package:flutter/widgets.dart';
import 'package:slang/builder/model/node.dart';
import 'package:slang_flutter/slang_flutter.dart';
export 'package:slang_flutter/slang_flutter.dart';

const AppLocale _baseLocale = AppLocale.en;

/// Supported locales, see extension methods below.
///
/// Usage:
/// - LocaleSettings.setLocale(AppLocale.en) // set locale
/// - Locale locale = AppLocale.en.flutterLocale // get flutter locale from enum
/// - if (LocaleSettings.currentLocale == AppLocale.en) // locale check
enum AppLocale with BaseAppLocale<AppLocale, Translations> {
  en(languageCode: 'en', build: Translations.build),
  zhCn(languageCode: 'zh', countryCode: 'CN', build: _StringsZhCn.build);

  const AppLocale(
      {required this.languageCode,
      this.scriptCode,
      this.countryCode,
      required this.build}); // ignore: unused_element

  @override
  final String languageCode;
  @override
  final String? scriptCode;
  @override
  final String? countryCode;
  @override
  final TranslationBuilder<AppLocale, Translations> build;

  /// Gets current instance managed by [LocaleSettings].
  Translations get translations =>
      LocaleSettings.instance.translationMap[this]!;
}

/// Method A: Simple
///
/// No rebuild after locale change.
/// Translation happens during initialization of the widget (call of t).
/// Configurable via 'translate_var'.
///
/// Usage:
/// String a = t.someKey.anotherKey;
/// String b = t['someKey.anotherKey']; // Only for edge cases!
Translations get t => LocaleSettings.instance.currentTranslations;

/// Method B: Advanced
///
/// All widgets using this method will trigger a rebuild when locale changes.
/// Use this if you have e.g. a settings page where the user can select the locale during runtime.
///
/// Step 1:
/// wrap your App with
/// TranslationProvider(
/// 	child: MyApp()
/// );
///
/// Step 2:
/// final t = Translations.of(context); // Get t variable.
/// String a = t.someKey.anotherKey; // Use t variable.
/// String b = t['someKey.anotherKey']; // Only for edge cases!
class TranslationProvider
    extends BaseTranslationProvider<AppLocale, Translations> {
  TranslationProvider({required super.child})
      : super(settings: LocaleSettings.instance);

  static InheritedLocaleData<AppLocale, Translations> of(
          BuildContext context) =>
      InheritedLocaleData.of<AppLocale, Translations>(context);
}

/// Method B shorthand via [BuildContext] extension method.
/// Configurable via 'translate_var'.
///
/// Usage (e.g. in a widget's build method):
/// context.t.someKey.anotherKey
extension BuildContextTranslationsExtension on BuildContext {
  Translations get t => TranslationProvider.of(this).translations;
}

/// Manages all translation instances and the current locale
class LocaleSettings
    extends BaseFlutterLocaleSettings<AppLocale, Translations> {
  LocaleSettings._() : super(utils: AppLocaleUtils.instance);

  static final instance = LocaleSettings._();

  // static aliases (checkout base methods for documentation)
  static AppLocale get currentLocale => instance.currentLocale;
  static Stream<AppLocale> getLocaleStream() => instance.getLocaleStream();
  static AppLocale setLocale(AppLocale locale,
          {bool? listenToDeviceLocale = false}) =>
      instance.setLocale(locale, listenToDeviceLocale: listenToDeviceLocale);
  static AppLocale setLocaleRaw(String rawLocale,
          {bool? listenToDeviceLocale = false}) =>
      instance.setLocaleRaw(rawLocale,
          listenToDeviceLocale: listenToDeviceLocale);
  static AppLocale useDeviceLocale() => instance.useDeviceLocale();
  @Deprecated('Use [AppLocaleUtils.supportedLocales]')
  static List<Locale> get supportedLocales => instance.supportedLocales;
  @Deprecated('Use [AppLocaleUtils.supportedLocalesRaw]')
  static List<String> get supportedLocalesRaw => instance.supportedLocalesRaw;
  static void setPluralResolver(
          {String? language,
          AppLocale? locale,
          PluralResolver? cardinalResolver,
          PluralResolver? ordinalResolver}) =>
      instance.setPluralResolver(
        language: language,
        locale: locale,
        cardinalResolver: cardinalResolver,
        ordinalResolver: ordinalResolver,
      );
}

/// Provides utility functions without any side effects.
class AppLocaleUtils extends BaseAppLocaleUtils<AppLocale, Translations> {
  AppLocaleUtils._()
      : super(baseLocale: _baseLocale, locales: AppLocale.values);

  static final instance = AppLocaleUtils._();

  // static aliases (checkout base methods for documentation)
  static AppLocale parse(String rawLocale) => instance.parse(rawLocale);
  static AppLocale parseLocaleParts(
          {required String languageCode,
          String? scriptCode,
          String? countryCode}) =>
      instance.parseLocaleParts(
          languageCode: languageCode,
          scriptCode: scriptCode,
          countryCode: countryCode);
  static AppLocale findDeviceLocale() => instance.findDeviceLocale();
  static List<Locale> get supportedLocales => instance.supportedLocales;
  static List<String> get supportedLocalesRaw => instance.supportedLocalesRaw;
}

// translations

// Path: <root>
class Translations implements BaseTranslations<AppLocale, Translations> {
  /// Returns the current translations of the given [context].
  ///
  /// Usage:
  /// final t = Translations.of(context);
  static Translations of(BuildContext context) =>
      InheritedLocaleData.of<AppLocale, Translations>(context).translations;

  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  Translations.build(
      {Map<String, Node>? overrides,
      PluralResolver? cardinalResolver,
      PluralResolver? ordinalResolver})
      : assert(overrides == null,
            'Set "translation_overrides: true" in order to enable this feature.'),
        $meta = TranslationMetadata(
          locale: AppLocale.en,
          overrides: overrides ?? {},
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        ) {
    $meta.setFlatMapFunction(_flatMapFunction);
  }

  /// Metadata for the translations of <en>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  /// Access flat map
  dynamic operator [](String key) => $meta.getTranslation(key);

  late final Translations _root = this; // ignore: unused_field

  // Translations
  late final _StringsAppEn app = _StringsAppEn._(_root);
  late final _StringsCommonEn common = _StringsCommonEn._(_root);
  late final _StringsErrorsEn errors = _StringsErrorsEn._(_root);
  late final _StringsActionsEn actions = _StringsActionsEn._(_root);
  late final _StringsSettingsEn settings = _StringsSettingsEn._(_root);
  late final _StringsLockEn lock = _StringsLockEn._(_root);
  late final _StringsChatEn chat = _StringsChatEn._(_root);
  late final _StringsAttachmentsEn attachments = _StringsAttachmentsEn._(_root);
  late final _StringsSemanticSearchEn semanticSearch =
      _StringsSemanticSearchEn._(_root);
  late final _StringsSemanticSearchDebugEn semanticSearchDebug =
      _StringsSemanticSearchDebugEn._(_root);
  late final _StringsSyncEn sync = _StringsSyncEn._(_root);
  late final _StringsLlmProfilesEn llmProfiles = _StringsLlmProfilesEn._(_root);
  late final _StringsEmbeddingProfilesEn embeddingProfiles =
      _StringsEmbeddingProfilesEn._(_root);
  late final _StringsInboxEn inbox = _StringsInboxEn._(_root);
}

// Path: app
class _StringsAppEn {
  _StringsAppEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'SecondLoop';
  late final _StringsAppTabsEn tabs = _StringsAppTabsEn._(_root);
}

// Path: common
class _StringsCommonEn {
  _StringsCommonEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsCommonActionsEn actions = _StringsCommonActionsEn._(_root);
  late final _StringsCommonFieldsEn fields = _StringsCommonFieldsEn._(_root);
  late final _StringsCommonLabelsEn labels = _StringsCommonLabelsEn._(_root);
}

// Path: errors
class _StringsErrorsEn {
  _StringsErrorsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String initFailed({required Object error}) => 'Init failed: ${error}';
  String loadFailed({required Object error}) => 'Load failed: ${error}';
  String saveFailed({required Object error}) => 'Save failed: ${error}';
  String lockGateError({required Object error}) => 'LockGate error: ${error}';
  String get missingMainStream => 'Missing Main Stream';
}

// Path: actions
class _StringsActionsEn {
  _StringsActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsActionsCaptureEn capture =
      _StringsActionsCaptureEn._(_root);
  late final _StringsActionsReviewQueueEn reviewQueue =
      _StringsActionsReviewQueueEn._(_root);
  late final _StringsActionsTodoStatusEn todoStatus =
      _StringsActionsTodoStatusEn._(_root);
  late final _StringsActionsTodoLinkEn todoLink =
      _StringsActionsTodoLinkEn._(_root);
  late final _StringsActionsTodoNoteLinkEn todoNoteLink =
      _StringsActionsTodoNoteLinkEn._(_root);
  late final _StringsActionsTodoAutoEn todoAuto =
      _StringsActionsTodoAutoEn._(_root);
  late final _StringsActionsTodoDetailEn todoDetail =
      _StringsActionsTodoDetailEn._(_root);
  late final _StringsActionsTodoDeleteEn todoDelete =
      _StringsActionsTodoDeleteEn._(_root);
  late final _StringsActionsTodoRecurrenceEditScopeEn todoRecurrenceEditScope =
      _StringsActionsTodoRecurrenceEditScopeEn._(_root);
  late final _StringsActionsTodoRecurrenceRuleEn todoRecurrenceRule =
      _StringsActionsTodoRecurrenceRuleEn._(_root);
  late final _StringsActionsHistoryEn history =
      _StringsActionsHistoryEn._(_root);
  late final _StringsActionsAgendaEn agenda = _StringsActionsAgendaEn._(_root);
  late final _StringsActionsCalendarEn calendar =
      _StringsActionsCalendarEn._(_root);
}

// Path: settings
class _StringsSettingsEn {
  _StringsSettingsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Settings';
  late final _StringsSettingsSectionsEn sections =
      _StringsSettingsSectionsEn._(_root);
  late final _StringsSettingsActionsReviewEn actionsReview =
      _StringsSettingsActionsReviewEn._(_root);
  late final _StringsSettingsQuickCaptureHotkeyEn quickCaptureHotkey =
      _StringsSettingsQuickCaptureHotkeyEn._(_root);
  late final _StringsSettingsDesktopBootEn desktopBoot =
      _StringsSettingsDesktopBootEn._(_root);
  late final _StringsSettingsDesktopTrayEn desktopTray =
      _StringsSettingsDesktopTrayEn._(_root);
  late final _StringsSettingsLanguageEn language =
      _StringsSettingsLanguageEn._(_root);
  late final _StringsSettingsThemeEn theme = _StringsSettingsThemeEn._(_root);
  late final _StringsSettingsAutoLockEn autoLock =
      _StringsSettingsAutoLockEn._(_root);
  late final _StringsSettingsSystemUnlockEn systemUnlock =
      _StringsSettingsSystemUnlockEn._(_root);
  late final _StringsSettingsLockNowEn lockNow =
      _StringsSettingsLockNowEn._(_root);
  late final _StringsSettingsLlmProfilesEn llmProfiles =
      _StringsSettingsLlmProfilesEn._(_root);
  late final _StringsSettingsEmbeddingProfilesEn embeddingProfiles =
      _StringsSettingsEmbeddingProfilesEn._(_root);
  late final _StringsSettingsAiSelectionEn aiSelection =
      _StringsSettingsAiSelectionEn._(_root);
  late final _StringsSettingsSemanticParseAutoActionsEn
      semanticParseAutoActions =
      _StringsSettingsSemanticParseAutoActionsEn._(_root);
  late final _StringsSettingsMediaAnnotationEn mediaAnnotation =
      _StringsSettingsMediaAnnotationEn._(_root);
  late final _StringsSettingsCloudEmbeddingsEn cloudEmbeddings =
      _StringsSettingsCloudEmbeddingsEn._(_root);
  late final _StringsSettingsCloudAccountEn cloudAccount =
      _StringsSettingsCloudAccountEn._(_root);
  late final _StringsSettingsCloudUsageEn cloudUsage =
      _StringsSettingsCloudUsageEn._(_root);
  late final _StringsSettingsVaultUsageEn vaultUsage =
      _StringsSettingsVaultUsageEn._(_root);
  late final _StringsSettingsDiagnosticsEn diagnostics =
      _StringsSettingsDiagnosticsEn._(_root);
  late final _StringsSettingsByokUsageEn byokUsage =
      _StringsSettingsByokUsageEn._(_root);
  late final _StringsSettingsSubscriptionEn subscription =
      _StringsSettingsSubscriptionEn._(_root);
  late final _StringsSettingsSyncEn sync = _StringsSettingsSyncEn._(_root);
  late final _StringsSettingsResetLocalDataThisDeviceOnlyEn
      resetLocalDataThisDeviceOnly =
      _StringsSettingsResetLocalDataThisDeviceOnlyEn._(_root);
  late final _StringsSettingsResetLocalDataAllDevicesEn
      resetLocalDataAllDevices =
      _StringsSettingsResetLocalDataAllDevicesEn._(_root);
  late final _StringsSettingsDebugResetLocalDataThisDeviceOnlyEn
      debugResetLocalDataThisDeviceOnly =
      _StringsSettingsDebugResetLocalDataThisDeviceOnlyEn._(_root);
  late final _StringsSettingsDebugResetLocalDataAllDevicesEn
      debugResetLocalDataAllDevices =
      _StringsSettingsDebugResetLocalDataAllDevicesEn._(_root);
  late final _StringsSettingsDebugSemanticSearchEn debugSemanticSearch =
      _StringsSettingsDebugSemanticSearchEn._(_root);
}

// Path: lock
class _StringsLockEn {
  _StringsLockEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get masterPasswordRequired => 'Master password required';
  String get passwordsDoNotMatch => 'Passwords do not match';
  String get setupTitle => 'Set master password';
  String get unlockTitle => 'Unlock';
  String get unlockReason => 'Unlock SecondLoop';
  String get missingSavedSessionKey =>
      'Missing saved session key. Unlock with master password once.';
  String get creating => 'Creating…';
  String get unlocking => 'Unlocking…';
}

// Path: chat
class _StringsChatEn {
  _StringsChatEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get mainStreamTitle => 'Main Stream';
  String get attachTooltip => 'Add attachment';
  String get attachPickMedia => 'Choose media';
  String get attachTakePhoto => 'Take photo';
  String get attachRecordAudio => 'Record audio';
  String get switchToVoiceInput => 'Switch to voice';
  String get switchToKeyboardInput => 'Switch to keyboard';
  String get holdToTalk => 'Hold to talk';
  String get releaseToConvert => 'Release to convert to text';
  String get recordingInProgress => 'Recording…';
  String get recordingHint => 'Tap Stop to send audio, or Cancel to discard.';
  String get cameraTooltip => 'Take photo';
  String get photoMessage => 'Photo';
  String get editMessageTitle => 'Edit message';
  String get messageUpdated => 'Message updated';
  String get messageDeleted => 'Message deleted';
  late final _StringsChatDeleteMessageDialogEn deleteMessageDialog =
      _StringsChatDeleteMessageDialogEn._(_root);
  String photoFailed({required Object error}) => 'Photo failed: ${error}';
  String get audioRecordPermissionDenied =>
      'Microphone permission is required to record audio.';
  String audioRecordFailed({required Object error}) =>
      'Audio record failed: ${error}';
  String editFailed({required Object error}) => 'Edit failed: ${error}';
  String deleteFailed({required Object error}) => 'Delete failed: ${error}';
  String get noMessagesYet => 'No messages yet';
  String get viewFull => 'View full';
  late final _StringsChatMessageActionsEn messageActions =
      _StringsChatMessageActionsEn._(_root);
  late final _StringsChatMessageViewerEn messageViewer =
      _StringsChatMessageViewerEn._(_root);
  late final _StringsChatMarkdownEditorEn markdownEditor =
      _StringsChatMarkdownEditorEn._(_root);
  late final _StringsChatFocusEn focus = _StringsChatFocusEn._(_root);
  late final _StringsChatAskAiSetupEn askAiSetup =
      _StringsChatAskAiSetupEn._(_root);
  late final _StringsChatCloudGatewayEn cloudGateway =
      _StringsChatCloudGatewayEn._(_root);
  String get askAiFailedTemporary => 'Ask AI failed. Please try again.';
  late final _StringsChatAskAiConsentEn askAiConsent =
      _StringsChatAskAiConsentEn._(_root);
  late final _StringsChatEmbeddingsConsentEn embeddingsConsent =
      _StringsChatEmbeddingsConsentEn._(_root);
  String get semanticParseStatusRunning => 'AI analyzing…';
  String get semanticParseStatusSlow =>
      'AI is taking longer. Continuing in background…';
  String get attachmentAnnotationNeedsSetup => 'Image annotations need setup';
  String get semanticParseStatusFailed => 'AI analysis failed';
  String get semanticParseStatusCanceled => 'AI analysis canceled';
  String semanticParseStatusCreated({required Object title}) =>
      'Created task: ${title}';
  String semanticParseStatusUpdated({required Object title}) =>
      'Updated task: ${title}';
  String get semanticParseStatusUpdatedGeneric => 'Updated task';
  String get semanticParseStatusUndone => 'Undid auto action';
  String get askAiRecoveredDetached => 'Recovered the completed cloud answer.';
  late final _StringsChatTopicThreadEn topicThread =
      _StringsChatTopicThreadEn._(_root);
  late final _StringsChatTagFilterEn tagFilter =
      _StringsChatTagFilterEn._(_root);
  late final _StringsChatTagPickerEn tagPicker =
      _StringsChatTagPickerEn._(_root);
  late final _StringsChatAskScopeEmptyEn askScopeEmpty =
      _StringsChatAskScopeEmptyEn._(_root);
}

// Path: attachments
class _StringsAttachmentsEn {
  _StringsAttachmentsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsAttachmentsMetadataEn metadata =
      _StringsAttachmentsMetadataEn._(_root);
  late final _StringsAttachmentsUrlEn url = _StringsAttachmentsUrlEn._(_root);
  late final _StringsAttachmentsContentEn content =
      _StringsAttachmentsContentEn._(_root);
}

// Path: semanticSearch
class _StringsSemanticSearchEn {
  _StringsSemanticSearchEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get preparing => 'Preparing semantic search…';
  String indexingMessages({required Object count}) =>
      'Indexing messages… (${count} indexed)';
}

// Path: semanticSearchDebug
class _StringsSemanticSearchDebugEn {
  _StringsSemanticSearchDebugEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Semantic Search (Debug)';
  String get embeddingModelLoading => 'Embedding model: (loading...)';
  String embeddingModel({required Object model}) => 'Embedding model: ${model}';
  String get switchedModelReindex =>
      'Switched embedding model; re-index pending';
  String get modelAlreadyActive => 'Embedding model already active';
  String processedPending({required Object count}) =>
      'Processed ${count} pending embeddings';
  String rebuilt({required Object count}) =>
      'Rebuilt embeddings for ${count} messages';
  String get runSearchToSeeResults => 'Run a search to see results';
  String get noResults => 'No results';
  String resultSubtitle(
          {required Object distance,
          required Object role,
          required Object conversationId}) =>
      'distance=${distance} • role=${role} • convo=${conversationId}';
}

// Path: sync
class _StringsSyncEn {
  _StringsSyncEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Sync settings';
  late final _StringsSyncProgressDialogEn progressDialog =
      _StringsSyncProgressDialogEn._(_root);
  late final _StringsSyncSectionsEn sections = _StringsSyncSectionsEn._(_root);
  late final _StringsSyncAutoSyncEn autoSync = _StringsSyncAutoSyncEn._(_root);
  late final _StringsSyncMediaPreviewEn mediaPreview =
      _StringsSyncMediaPreviewEn._(_root);
  late final _StringsSyncMediaBackupEn mediaBackup =
      _StringsSyncMediaBackupEn._(_root);
  late final _StringsSyncLocalCacheEn localCache =
      _StringsSyncLocalCacheEn._(_root);
  String get backendLabel => 'Sync method';
  String get backendWebdav => 'WebDAV (your server)';
  String get backendLocalDir => 'Folder on this computer (desktop)';
  String get backendManagedVault => 'SecondLoop Cloud';
  late final _StringsSyncCloudManagedVaultEn cloudManagedVault =
      _StringsSyncCloudManagedVaultEn._(_root);
  String get remoteRootRequired => 'Folder name is required';
  String get baseUrlRequired => 'Server address is required';
  String get localDirRequired => 'Folder path is required';
  String get connectionOk => 'Connection OK';
  String connectionFailed({required Object error}) =>
      'Connection failed: ${error}';
  String saveFailed({required Object error}) => 'Save failed: ${error}';
  String get missingSyncKey => 'Enter your sync passphrase and tap Save first.';
  String pushedOps({required Object count}) => 'Uploaded ${count} changes';
  String pulledOps({required Object count}) => 'Downloaded ${count} changes';
  String get noNewChanges => 'No new changes';
  String pushFailed({required Object error}) => 'Upload failed: ${error}';
  String pullFailed({required Object error}) => 'Download failed: ${error}';
  late final _StringsSyncFieldsEn fields = _StringsSyncFieldsEn._(_root);
}

// Path: llmProfiles
class _StringsLlmProfilesEn {
  _StringsLlmProfilesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'AI profiles';
  String get refreshTooltip => 'Refresh';
  String get activeProfileHelp =>
      'The active profile is reused as the general LLM API profile across intelligence features.';
  String get noProfilesYet => 'No profiles yet.';
  String get addProfile => 'Add profile';
  String get deleted => 'AI profile deleted';
  String get validationError => 'Name, API key, and model are required.';
  late final _StringsLlmProfilesDeleteDialogEn deleteDialog =
      _StringsLlmProfilesDeleteDialogEn._(_root);
  late final _StringsLlmProfilesFieldsEn fields =
      _StringsLlmProfilesFieldsEn._(_root);
  late final _StringsLlmProfilesProvidersEn providers =
      _StringsLlmProfilesProvidersEn._(_root);
  String get savedActivated => 'AI profile saved and activated';
  late final _StringsLlmProfilesActionsEn actions =
      _StringsLlmProfilesActionsEn._(_root);
}

// Path: embeddingProfiles
class _StringsEmbeddingProfilesEn {
  _StringsEmbeddingProfilesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Embedding profiles';
  String get refreshTooltip => 'Refresh';
  String get activeProfileHelp =>
      'Active profile is used for embeddings (semantic search / RAG).';
  String get noProfilesYet => 'No profiles yet.';
  String get addProfile => 'Add profile';
  String get deleted => 'Embedding profile deleted';
  String get validationError => 'Name, API key, and model are required.';
  late final _StringsEmbeddingProfilesReindexDialogEn reindexDialog =
      _StringsEmbeddingProfilesReindexDialogEn._(_root);
  late final _StringsEmbeddingProfilesDeleteDialogEn deleteDialog =
      _StringsEmbeddingProfilesDeleteDialogEn._(_root);
  late final _StringsEmbeddingProfilesFieldsEn fields =
      _StringsEmbeddingProfilesFieldsEn._(_root);
  late final _StringsEmbeddingProfilesProvidersEn providers =
      _StringsEmbeddingProfilesProvidersEn._(_root);
  String get savedActivated => 'Embedding profile saved and activated';
  late final _StringsEmbeddingProfilesActionsEn actions =
      _StringsEmbeddingProfilesActionsEn._(_root);
}

// Path: inbox
class _StringsInboxEn {
  _StringsInboxEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get defaultTitle => 'Inbox';
  String get noConversationsYet => 'No conversations yet';
}

// Path: app.tabs
class _StringsAppTabsEn {
  _StringsAppTabsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get main => 'Main';
  String get settings => 'Settings';
}

// Path: common.actions
class _StringsCommonActionsEn {
  _StringsCommonActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get cancel => 'Cancel';
  String get notNow => 'Not now';
  String get allow => 'Allow';
  String get save => 'Save';
  String get copy => 'Copy';
  String get reset => 'Reset';
  String get continueLabel => 'Continue';
  String get send => 'Send';
  String get askAi => 'Ask AI';
  String get configureAi => 'Configure AI';
  String get stop => 'Stop';
  String get stopping => 'Stopping…';
  String get edit => 'Edit';
  String get delete => 'Delete';
  String get undo => 'Undo';
  String get open => 'Open';
  String get retry => 'Retry';
  String get ignore => 'Ignore';
  String get refresh => 'Refresh';
  String get share => 'Share';
  String get search => 'Search';
  String get useModel => 'Use model';
  String get processPending => 'Process pending';
  String get rebuildEmbeddings => 'Rebuild embeddings';
  String get push => 'Upload';
  String get pull => 'Download';
  String get lockNow => 'Lock now';
}

// Path: common.fields
class _StringsCommonFieldsEn {
  _StringsCommonFieldsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get masterPassword => 'Master password';
  String get confirm => 'Confirm';
  String get message => 'Message';
  String get quickCapture => 'Quick capture';
  String get query => 'Query';
}

// Path: common.labels
class _StringsCommonLabelsEn {
  _StringsCommonLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String elapsedSeconds({required Object seconds}) => 'Elapsed: ${seconds}s';
  String get topK => 'Top‑K:';
}

// Path: actions.capture
class _StringsActionsCaptureEn {
  _StringsActionsCaptureEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Turn this into a reminder?';
  String get pickTime => 'Pick a time';
  String get reviewLater => 'Remind me to confirm later';
  String get justSave => 'Just save as note';
}

// Path: actions.reviewQueue
class _StringsActionsReviewQueueEn {
  _StringsActionsReviewQueueEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Needs confirmation';
  String banner({required Object count}) => '${count} items need confirmation';
  String get empty => 'No items to confirm';
  String snoozedUntil({required Object when}) => 'Snoozed until ${when}';
  late final _StringsActionsReviewQueueInAppFallbackEn inAppFallback =
      _StringsActionsReviewQueueInAppFallbackEn._(_root);
  late final _StringsActionsReviewQueueActionsEn actions =
      _StringsActionsReviewQueueActionsEn._(_root);
}

// Path: actions.todoStatus
class _StringsActionsTodoStatusEn {
  _StringsActionsTodoStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get inbox => 'Needs confirmation';
  String get open => 'Not started';
  String get inProgress => 'In progress';
  String get done => 'Done';
  String get dismissed => 'Deleted';
}

// Path: actions.todoLink
class _StringsActionsTodoLinkEn {
  _StringsActionsTodoLinkEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Update a task?';
  String subtitle({required Object status}) => 'Mark as: ${status}';
  String updated({required Object title, required Object status}) =>
      'Updated "${title}" → ${status}';
}

// Path: actions.todoNoteLink
class _StringsActionsTodoNoteLinkEn {
  _StringsActionsTodoNoteLinkEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get action => 'Link to task';
  String get actionShort => 'Link';
  String get title => 'Link to which task?';
  String get subtitle => 'Add this message as a follow-up note';
  String get noMatches => 'No matching tasks';
  String get suggest => 'Link this message to a task?';
  String linked({required Object title}) => 'Linked to "${title}"';
}

// Path: actions.todoAuto
class _StringsActionsTodoAutoEn {
  _StringsActionsTodoAutoEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String created({required Object title}) => 'Created "${title}"';
}

// Path: actions.todoDetail
class _StringsActionsTodoDetailEn {
  _StringsActionsTodoDetailEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Task';
  String get emptyTimeline => 'No updates yet';
  String get noteHint => 'Add a note…';
  String get addNote => 'Add';
  String get attach => 'Attach';
  String get pickAttachment => 'Choose an attachment';
  String get noAttachments => 'No attachments yet';
  String get attachmentNoteDefault => 'Added attachment';
}

// Path: actions.todoDelete
class _StringsActionsTodoDeleteEn {
  _StringsActionsTodoDeleteEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsActionsTodoDeleteDialogEn dialog =
      _StringsActionsTodoDeleteDialogEn._(_root);
}

// Path: actions.todoRecurrenceEditScope
class _StringsActionsTodoRecurrenceEditScopeEn {
  _StringsActionsTodoRecurrenceEditScopeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Apply changes to recurring task';
  String get message => 'How should this change be applied?';
  String get thisOnly => 'This occurrence only';
  String get thisAndFuture => 'This and future';
  String get wholeSeries => 'Whole series';
}

// Path: actions.todoRecurrenceRule
class _StringsActionsTodoRecurrenceRuleEn {
  _StringsActionsTodoRecurrenceRuleEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Edit recurrence';
  String get edit => 'Recurrence';
  String get frequencyLabel => 'Frequency';
  String get intervalLabel => 'Interval';
  String get daily => 'Daily';
  String get weekly => 'Weekly';
  String get monthly => 'Monthly';
  String get yearly => 'Yearly';
}

// Path: actions.history
class _StringsActionsHistoryEn {
  _StringsActionsHistoryEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'History';
  String get empty => 'No activity in this range';
  late final _StringsActionsHistoryPresetsEn presets =
      _StringsActionsHistoryPresetsEn._(_root);
  late final _StringsActionsHistoryActionsEn actions =
      _StringsActionsHistoryActionsEn._(_root);
  late final _StringsActionsHistorySectionsEn sections =
      _StringsActionsHistorySectionsEn._(_root);
}

// Path: actions.agenda
class _StringsActionsAgendaEn {
  _StringsActionsAgendaEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Tasks';
  String summary({required Object due, required Object overdue}) =>
      'Today ${due} • Overdue ${overdue}';
  String upcomingSummary({required Object count}) => 'Upcoming ${count}';
  String get viewAll => 'View all';
  String get empty => 'No scheduled tasks';
}

// Path: actions.calendar
class _StringsActionsCalendarEn {
  _StringsActionsCalendarEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Add to calendar?';
  String get pickTime => 'Pick a start time';
  String get noAutoTime => 'No suggested time found';
  String get pickCustom => 'Pick date & time';
}

// Path: settings.sections
class _StringsSettingsSectionsEn {
  _StringsSettingsSectionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get appearance => 'Appearance';
  String get security => 'Security';
  String get cloud => 'SecondLoop Cloud';
  String get aiAdvanced => 'Advanced (API keys)';
  String get storage => 'Sync & storage';
  String get actions => 'Actions';
  String get support => 'Help & support';
  String get debug => 'Debug';
}

// Path: settings.actionsReview
class _StringsSettingsActionsReviewEn {
  _StringsSettingsActionsReviewEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsActionsReviewMorningTimeEn morningTime =
      _StringsSettingsActionsReviewMorningTimeEn._(_root);
  late final _StringsSettingsActionsReviewDayEndTimeEn dayEndTime =
      _StringsSettingsActionsReviewDayEndTimeEn._(_root);
  late final _StringsSettingsActionsReviewWeeklyTimeEn weeklyTime =
      _StringsSettingsActionsReviewWeeklyTimeEn._(_root);
  late final _StringsSettingsActionsReviewInAppFallbackEn inAppFallback =
      _StringsSettingsActionsReviewInAppFallbackEn._(_root);
}

// Path: settings.quickCaptureHotkey
class _StringsSettingsQuickCaptureHotkeyEn {
  _StringsSettingsQuickCaptureHotkeyEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Quick capture shortcut';
  String get subtitle => 'Global shortcut to open Quick capture';
  String get dialogTitle => 'Quick capture shortcut';
  String get dialogBody => 'Press a key combination to record a new shortcut.';
  String get saved => 'Quick capture shortcut updated';
  late final _StringsSettingsQuickCaptureHotkeyActionsEn actions =
      _StringsSettingsQuickCaptureHotkeyActionsEn._(_root);
  late final _StringsSettingsQuickCaptureHotkeyValidationEn validation =
      _StringsSettingsQuickCaptureHotkeyValidationEn._(_root);
  late final _StringsSettingsQuickCaptureHotkeyConflictsEn conflicts =
      _StringsSettingsQuickCaptureHotkeyConflictsEn._(_root);
}

// Path: settings.desktopBoot
class _StringsSettingsDesktopBootEn {
  _StringsSettingsDesktopBootEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsDesktopBootStartWithSystemEn startWithSystem =
      _StringsSettingsDesktopBootStartWithSystemEn._(_root);
  late final _StringsSettingsDesktopBootSilentStartupEn silentStartup =
      _StringsSettingsDesktopBootSilentStartupEn._(_root);
  late final _StringsSettingsDesktopBootKeepRunningInBackgroundEn
      keepRunningInBackground =
      _StringsSettingsDesktopBootKeepRunningInBackgroundEn._(_root);
}

// Path: settings.desktopTray
class _StringsSettingsDesktopTrayEn {
  _StringsSettingsDesktopTrayEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsDesktopTrayMenuEn menu =
      _StringsSettingsDesktopTrayMenuEn._(_root);
  late final _StringsSettingsDesktopTrayProEn pro =
      _StringsSettingsDesktopTrayProEn._(_root);
}

// Path: settings.language
class _StringsSettingsLanguageEn {
  _StringsSettingsLanguageEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Language';
  String get subtitle => 'Follow system or choose a language';
  String get dialogTitle => 'Language';
  late final _StringsSettingsLanguageOptionsEn options =
      _StringsSettingsLanguageOptionsEn._(_root);
}

// Path: settings.theme
class _StringsSettingsThemeEn {
  _StringsSettingsThemeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Theme';
  String get subtitle => 'Follow system, or choose light/dark';
  String get dialogTitle => 'Theme';
  late final _StringsSettingsThemeOptionsEn options =
      _StringsSettingsThemeOptionsEn._(_root);
}

// Path: settings.autoLock
class _StringsSettingsAutoLockEn {
  _StringsSettingsAutoLockEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto lock';
  String get subtitle => 'Require unlock to access the app';
}

// Path: settings.systemUnlock
class _StringsSettingsSystemUnlockEn {
  _StringsSettingsSystemUnlockEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get titleMobile => 'Use biometrics';
  String get titleDesktop => 'Use system unlock';
  String get subtitleMobile =>
      'Unlock with biometrics instead of master password';
  String get subtitleDesktop =>
      'Unlock with Touch ID / Windows Hello instead of master password';
}

// Path: settings.lockNow
class _StringsSettingsLockNowEn {
  _StringsSettingsLockNowEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Lock now';
  String get subtitle => 'Return to the unlock screen';
}

// Path: settings.llmProfiles
class _StringsSettingsLlmProfilesEn {
  _StringsSettingsLlmProfilesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API keys (Ask AI)';
  String get subtitle => 'Advanced: use your own provider and key';
}

// Path: settings.embeddingProfiles
class _StringsSettingsEmbeddingProfilesEn {
  _StringsSettingsEmbeddingProfilesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API keys (Semantic search)';
  String get subtitle => 'Advanced: use your own provider and key';
}

// Path: settings.aiSelection
class _StringsSettingsAiSelectionEn {
  _StringsSettingsAiSelectionEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Intelligence';
  String get subtitle =>
      'Unified settings for Ask AI, embeddings, OCR, speech recognition, and image understanding.';
  late final _StringsSettingsAiSelectionAskAiEn askAi =
      _StringsSettingsAiSelectionAskAiEn._(_root);
  late final _StringsSettingsAiSelectionEmbeddingsEn embeddings =
      _StringsSettingsAiSelectionEmbeddingsEn._(_root);
  late final _StringsSettingsAiSelectionMediaUnderstandingEn
      mediaUnderstanding =
      _StringsSettingsAiSelectionMediaUnderstandingEn._(_root);
}

// Path: settings.semanticParseAutoActions
class _StringsSettingsSemanticParseAutoActionsEn {
  _StringsSettingsSemanticParseAutoActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Smarter semantic analysis';
  String get subtitleEnabled =>
      'Enhanced mode is on. Local semantic analysis stays on, and Cloud/BYOK improves automation quality.';
  String get subtitleDisabled =>
      'Enhanced mode is off. Local semantic analysis remains active.';
  String get subtitleUnset =>
      'Not set. Enhanced mode is off by default (local semantic analysis remains active).';
  String get subtitleRequiresSetup =>
      'Sign in with SecondLoop Pro or configure an API key (BYOK) to enable enhanced mode.';
  String get dialogTitle => 'Enable smarter semantic analysis?';
  String get dialogBody =>
      'Local semantic analysis is always on. When enhanced mode is enabled, SecondLoop may send message text to AI for smarter semantic parsing on top of local analysis.\n\nThe text is processed confidentially (not logged or stored). Your vault key and sync key are never uploaded.\n\nThis may use Cloud quota or your own provider quota.';
  late final _StringsSettingsSemanticParseAutoActionsDialogActionsEn
      dialogActions =
      _StringsSettingsSemanticParseAutoActionsDialogActionsEn._(_root);
}

// Path: settings.mediaAnnotation
class _StringsSettingsMediaAnnotationEn {
  _StringsSettingsMediaAnnotationEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Media understanding';
  String get subtitle =>
      'Optional: OCR, image captions, and audio transcripts for better search/storage';
  late final _StringsSettingsMediaAnnotationRoutingGuideEn routingGuide =
      _StringsSettingsMediaAnnotationRoutingGuideEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrEn documentOcr =
      _StringsSettingsMediaAnnotationDocumentOcrEn._(_root);
  late final _StringsSettingsMediaAnnotationAudioTranscribeEn audioTranscribe =
      _StringsSettingsMediaAnnotationAudioTranscribeEn._(_root);
  late final _StringsSettingsMediaAnnotationImageCaptionEn imageCaption =
      _StringsSettingsMediaAnnotationImageCaptionEn._(_root);
  late final _StringsSettingsMediaAnnotationProviderSettingsEn
      providerSettings =
      _StringsSettingsMediaAnnotationProviderSettingsEn._(_root);
  late final _StringsSettingsMediaAnnotationSetupRequiredEn setupRequired =
      _StringsSettingsMediaAnnotationSetupRequiredEn._(_root);
  late final _StringsSettingsMediaAnnotationAnnotateEnabledEn annotateEnabled =
      _StringsSettingsMediaAnnotationAnnotateEnabledEn._(_root);
  late final _StringsSettingsMediaAnnotationSearchEnabledEn searchEnabled =
      _StringsSettingsMediaAnnotationSearchEnabledEn._(_root);
  late final _StringsSettingsMediaAnnotationSearchToggleConfirmEn
      searchToggleConfirm =
      _StringsSettingsMediaAnnotationSearchToggleConfirmEn._(_root);
  late final _StringsSettingsMediaAnnotationAdvancedEn advanced =
      _StringsSettingsMediaAnnotationAdvancedEn._(_root);
  late final _StringsSettingsMediaAnnotationProviderModeEn providerMode =
      _StringsSettingsMediaAnnotationProviderModeEn._(_root);
  late final _StringsSettingsMediaAnnotationCloudModelNameEn cloudModelName =
      _StringsSettingsMediaAnnotationCloudModelNameEn._(_root);
  late final _StringsSettingsMediaAnnotationByokProfileEn byokProfile =
      _StringsSettingsMediaAnnotationByokProfileEn._(_root);
  late final _StringsSettingsMediaAnnotationAllowCellularEn allowCellular =
      _StringsSettingsMediaAnnotationAllowCellularEn._(_root);
  late final _StringsSettingsMediaAnnotationAllowCellularConfirmEn
      allowCellularConfirm =
      _StringsSettingsMediaAnnotationAllowCellularConfirmEn._(_root);
}

// Path: settings.cloudEmbeddings
class _StringsSettingsCloudEmbeddingsEn {
  _StringsSettingsCloudEmbeddingsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Smarter search';
  String get subtitleEnabled => 'On. Improves search. Uses your Cloud quota.';
  String get subtitleDisabled => 'Off. Search runs without cloud processing.';
  String get subtitleUnset => 'Not set. We\'ll ask when it\'s first needed.';
  String get subtitleRequiresPro => 'Requires SecondLoop Pro.';
  String get dialogTitle => 'Turn on smarter search?';
  String get dialogBody =>
      'To improve search and memory recall, SecondLoop can send small pieces of text (message previews, todo titles, follow‑ups) to SecondLoop Cloud to generate search data.\n\nThe text is processed confidentially (not logged or stored). Your vault key and sync key are never uploaded.\n\nThis uses your Cloud quota.';
  late final _StringsSettingsCloudEmbeddingsDialogActionsEn dialogActions =
      _StringsSettingsCloudEmbeddingsDialogActionsEn._(_root);
}

// Path: settings.cloudAccount
class _StringsSettingsCloudAccountEn {
  _StringsSettingsCloudAccountEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Cloud account';
  String get subtitle => 'Sign in to SecondLoop Cloud';
  String signedInAs({required Object email}) => 'Signed in as ${email}';
  late final _StringsSettingsCloudAccountBenefitsEn benefits =
      _StringsSettingsCloudAccountBenefitsEn._(_root);
  late final _StringsSettingsCloudAccountErrorsEn errors =
      _StringsSettingsCloudAccountErrorsEn._(_root);
  late final _StringsSettingsCloudAccountFieldsEn fields =
      _StringsSettingsCloudAccountFieldsEn._(_root);
  late final _StringsSettingsCloudAccountActionsEn actions =
      _StringsSettingsCloudAccountActionsEn._(_root);
  late final _StringsSettingsCloudAccountEmailVerificationEn emailVerification =
      _StringsSettingsCloudAccountEmailVerificationEn._(_root);
}

// Path: settings.cloudUsage
class _StringsSettingsCloudUsageEn {
  _StringsSettingsCloudUsageEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Cloud usage';
  String get subtitle => 'Usage for current billing period';
  late final _StringsSettingsCloudUsageActionsEn actions =
      _StringsSettingsCloudUsageActionsEn._(_root);
  late final _StringsSettingsCloudUsageLabelsEn labels =
      _StringsSettingsCloudUsageLabelsEn._(_root);
}

// Path: settings.vaultUsage
class _StringsSettingsVaultUsageEn {
  _StringsSettingsVaultUsageEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Vault storage';
  String get subtitle => 'Storage used by your synced data';
  late final _StringsSettingsVaultUsageActionsEn actions =
      _StringsSettingsVaultUsageActionsEn._(_root);
  late final _StringsSettingsVaultUsageLabelsEn labels =
      _StringsSettingsVaultUsageLabelsEn._(_root);
}

// Path: settings.diagnostics
class _StringsSettingsDiagnosticsEn {
  _StringsSettingsDiagnosticsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Diagnostics';
  String get subtitle => 'Share a diagnostics report with support';
  String get privacyNote =>
      'This report does not include your notes or API keys.';
  String get loading => 'Loading diagnostics…';
  late final _StringsSettingsDiagnosticsMessagesEn messages =
      _StringsSettingsDiagnosticsMessagesEn._(_root);
}

// Path: settings.byokUsage
class _StringsSettingsByokUsageEn {
  _StringsSettingsByokUsageEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API key usage';
  String get subtitle => 'Active profile • requests and tokens (if available)';
  String get loading => 'Loading…';
  String get noData => 'No data';
  late final _StringsSettingsByokUsageErrorsEn errors =
      _StringsSettingsByokUsageErrorsEn._(_root);
  late final _StringsSettingsByokUsageSectionsEn sections =
      _StringsSettingsByokUsageSectionsEn._(_root);
  late final _StringsSettingsByokUsageLabelsEn labels =
      _StringsSettingsByokUsageLabelsEn._(_root);
  late final _StringsSettingsByokUsagePurposesEn purposes =
      _StringsSettingsByokUsagePurposesEn._(_root);
}

// Path: settings.subscription
class _StringsSettingsSubscriptionEn {
  _StringsSettingsSubscriptionEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Subscription';
  String get subtitle => 'Manage SecondLoop Pro';
  late final _StringsSettingsSubscriptionBenefitsEn benefits =
      _StringsSettingsSubscriptionBenefitsEn._(_root);
  late final _StringsSettingsSubscriptionStatusEn status =
      _StringsSettingsSubscriptionStatusEn._(_root);
  late final _StringsSettingsSubscriptionActionsEn actions =
      _StringsSettingsSubscriptionActionsEn._(_root);
  late final _StringsSettingsSubscriptionLabelsEn labels =
      _StringsSettingsSubscriptionLabelsEn._(_root);
}

// Path: settings.sync
class _StringsSettingsSyncEn {
  _StringsSettingsSyncEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Sync';
  String get subtitle =>
      'Choose where your data syncs (Cloud / WebDAV / folder)';
}

// Path: settings.resetLocalDataThisDeviceOnly
class _StringsSettingsResetLocalDataThisDeviceOnlyEn {
  _StringsSettingsResetLocalDataThisDeviceOnlyEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get dialogTitle => 'Reset local data?';
  String get dialogBody =>
      'This will delete local messages and clear synced remote data for this device only. It will NOT delete your master password or your AI/sync settings. You will need to unlock again.';
  String failed({required Object error}) => 'Reset failed: ${error}';
}

// Path: settings.resetLocalDataAllDevices
class _StringsSettingsResetLocalDataAllDevicesEn {
  _StringsSettingsResetLocalDataAllDevicesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get dialogTitle => 'Reset local data?';
  String get dialogBody =>
      'This will delete local messages and clear all synced remote data. It will NOT delete your master password or your AI/sync settings. You will need to unlock again.';
  String failed({required Object error}) => 'Reset failed: ${error}';
}

// Path: settings.debugResetLocalDataThisDeviceOnly
class _StringsSettingsDebugResetLocalDataThisDeviceOnlyEn {
  _StringsSettingsDebugResetLocalDataThisDeviceOnlyEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Debug: Reset local data (this device)';
  String get subtitle =>
      'Delete local messages + clear remote data for this device only';
}

// Path: settings.debugResetLocalDataAllDevices
class _StringsSettingsDebugResetLocalDataAllDevicesEn {
  _StringsSettingsDebugResetLocalDataAllDevicesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Debug: Reset local data (all devices)';
  String get subtitle => 'Delete local messages + clear all remote data';
}

// Path: settings.debugSemanticSearch
class _StringsSettingsDebugSemanticSearchEn {
  _StringsSettingsDebugSemanticSearchEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Debug: Semantic search';
  String get subtitle => 'Search similar messages + rebuild embeddings index';
}

// Path: chat.deleteMessageDialog
class _StringsChatDeleteMessageDialogEn {
  _StringsChatDeleteMessageDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Delete message?';
  String get message =>
      'This will permanently delete this message and its attachments.';
}

// Path: chat.messageActions
class _StringsChatMessageActionsEn {
  _StringsChatMessageActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get convertToTodo => 'Convert to task';
  String get convertTodoToInfo => 'Convert to note';
  String get convertTodoToInfoConfirmTitle => 'Convert to note?';
  String get convertTodoToInfoConfirmBody =>
      'This will remove the task, but keep the original message.';
  String get openTodo => 'Jump to task';
  String get linkOtherTodo => 'Link to another task';
}

// Path: chat.messageViewer
class _StringsChatMessageViewerEn {
  _StringsChatMessageViewerEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Message';
}

// Path: chat.markdownEditor
class _StringsChatMarkdownEditorEn {
  _StringsChatMarkdownEditorEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get openButton => 'Markdown';
  String get title => 'Markdown editor';
  String get apply => 'Apply';
  String get editorLabel => 'Editor';
  String get previewLabel => 'Preview';
  String get emptyPreview => 'Preview will appear as you type.';
  String get shortcutHint => 'Tip: Cmd/Ctrl + Enter applies changes instantly.';
  String get listContinuationHint =>
      'Press Enter in a list item to continue it automatically.';
  String get quickActionsLabel => 'Quick formatting';
  String get themeLabel => 'Preview theme';
  String get themeStudio => 'Studio';
  String get themePaper => 'Paper';
  String get themeOcean => 'Ocean';
  String get themeNight => 'Night';
  String get exportMenu => 'Export preview';
  String get exportPng => 'Export as PNG';
  String get exportPdf => 'Export as PDF';
  String exportDone({required Object format}) => 'Exported as ${format}';
  String exportSavedPath({required Object path}) => 'Saved to ${path}';
  String exportFailed({required Object error}) => 'Export failed: ${error}';
  String stats({required Object lines, required Object characters}) =>
      '${lines} lines · ${characters} chars';
  String get simpleInput => 'Simple input';
  late final _StringsChatMarkdownEditorActionsEn actions =
      _StringsChatMarkdownEditorActionsEn._(_root);
}

// Path: chat.focus
class _StringsChatFocusEn {
  _StringsChatFocusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get tooltip => 'Focus';
  String get allMemories => 'Focus: All memories';
  String get thisThread => 'Focus: This thread';
}

// Path: chat.askAiSetup
class _StringsChatAskAiSetupEn {
  _StringsChatAskAiSetupEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Ask AI setup required';
  String get body =>
      'To use Ask AI, add your own API key (AI profile) or subscribe to SecondLoop Cloud.';
  late final _StringsChatAskAiSetupActionsEn actions =
      _StringsChatAskAiSetupActionsEn._(_root);
}

// Path: chat.cloudGateway
class _StringsChatCloudGatewayEn {
  _StringsChatCloudGatewayEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get emailNotVerified =>
      'Email not verified. Verify your email to use SecondLoop Cloud Ask AI.';
  late final _StringsChatCloudGatewayFallbackEn fallback =
      _StringsChatCloudGatewayFallbackEn._(_root);
  late final _StringsChatCloudGatewayErrorsEn errors =
      _StringsChatCloudGatewayErrorsEn._(_root);
}

// Path: chat.askAiConsent
class _StringsChatAskAiConsentEn {
  _StringsChatAskAiConsentEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Before we use AI';
  String get body =>
      'SecondLoop may send the text you type and a few relevant snippets to your chosen AI provider to power AI features.\n\nIt will not upload your master password or your full history.';
  String get dontShowAgain => 'Don\'t show again';
}

// Path: chat.embeddingsConsent
class _StringsChatEmbeddingsConsentEn {
  _StringsChatEmbeddingsConsentEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Use cloud embeddings for semantic search?';
  String get body =>
      'Benefits:\n- Better cross-language recall\n- Better todo linking suggestions\n\nPrivacy:\n- We only upload the minimum text needed to generate embeddings\n- The snippets are sent to SecondLoop Cloud Gateway and kept confidential (not logged or stored)\n- We never upload your vault key or sync key\n\nUsage:\n- Cloud embeddings count toward your cloud usage quota';
  String get dontShowAgain => 'Remember my choice';
  late final _StringsChatEmbeddingsConsentActionsEn actions =
      _StringsChatEmbeddingsConsentActionsEn._(_root);
}

// Path: chat.topicThread
class _StringsChatTopicThreadEn {
  _StringsChatTopicThreadEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get filterTooltip => 'Topic thread filter';
  String get actionLabel => 'Topic thread';
  String get create => 'Create topic thread';
  String get clearFilter => 'Clear topic thread filter';
  String get clear => 'Clear thread';
  String get manage => 'Manage thread';
  String get rename => 'Rename thread';
  String get delete => 'Delete thread';
  late final _StringsChatTopicThreadDeleteDialogEn deleteDialog =
      _StringsChatTopicThreadDeleteDialogEn._(_root);
  String get addMessage => 'Add this message';
  String get removeMessage => 'Remove this message';
  String get createDialogTitle => 'Create topic thread';
  String get renameDialogTitle => 'Rename topic thread';
  String get titleFieldLabel => 'Thread title (optional)';
  String get untitled => 'Untitled topic thread';
}

// Path: chat.tagFilter
class _StringsChatTagFilterEn {
  _StringsChatTagFilterEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get tooltip => 'Tag filter';
  String get clearFilter => 'Clear tag filter';
  late final _StringsChatTagFilterSheetEn sheet =
      _StringsChatTagFilterSheetEn._(_root);
}

// Path: chat.tagPicker
class _StringsChatTagPickerEn {
  _StringsChatTagPickerEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Manage tags';
  String get suggested => 'Suggested tags';
  String get mergeSuggestions => 'Merge suggestions';
  String get mergeAction => 'Merge';
  String get mergeDismissAction => 'Dismiss';
  String get mergeLaterAction => 'Later';
  String mergeSuggestionMessages({required Object count}) =>
      'Affects ${count} tagged messages';
  String get mergeReasonSystemDomain => 'Matches system domain';
  String get mergeReasonNameCompact => 'Likely duplicate name';
  String get mergeReasonNameContains => 'Very similar name';
  late final _StringsChatTagPickerMergeDialogEn mergeDialog =
      _StringsChatTagPickerMergeDialogEn._(_root);
  String mergeApplied({required Object count}) => 'Merged ${count} messages';
  String get mergeDismissed => 'Merge suggestion dismissed';
  String get mergeSavedForLater => 'Merge suggestion saved for later';
  String get all => 'All tags';
  String get inputHint => 'Type a tag name';
  String get add => 'Add';
  String get save => 'Save';
  String get tagActionLabel => 'Tags';
}

// Path: chat.askScopeEmpty
class _StringsChatAskScopeEmptyEn {
  _StringsChatAskScopeEmptyEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'No results in current scope';
  late final _StringsChatAskScopeEmptyActionsEn actions =
      _StringsChatAskScopeEmptyActionsEn._(_root);
}

// Path: attachments.metadata
class _StringsAttachmentsMetadataEn {
  _StringsAttachmentsMetadataEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get format => 'Format';
  String get size => 'Size';
  String get capturedAt => 'Captured';
  String get location => 'Location';
}

// Path: attachments.url
class _StringsAttachmentsUrlEn {
  _StringsAttachmentsUrlEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get originalUrl => 'Original URL';
  String get canonicalUrl => 'Canonical URL';
}

// Path: attachments.content
class _StringsAttachmentsContentEn {
  _StringsAttachmentsContentEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get summary => 'Summary';
  String get excerpt => 'Excerpt';
  String get fullText => 'Full text';
  String get ocrTitle => 'OCR';
  String get needsOcrTitle => 'OCR required';
  String get needsOcrSubtitle =>
      'This PDF appears to contain no selectable text.';
  String get runOcr => 'Run OCR';
  String get rerunOcr => 'Re-run OCR';
  String get ocrRunning => 'OCR in progress…';
  String get ocrReadySubtitle =>
      'Text is available. You can re-run OCR if needed.';
  String get keepForegroundHint =>
      'Keep the app in foreground while OCR is running.';
  String get openWithSystem => 'Open with system app';
  String get previewUnavailable => 'Preview unavailable';
  String get ocrFinished => 'OCR finished. Refreshing preview…';
  String get ocrFailed => 'OCR failed on this device.';
  late final _StringsAttachmentsContentSpeechTranscribeIssueEn
      speechTranscribeIssue =
      _StringsAttachmentsContentSpeechTranscribeIssueEn._(_root);
  late final _StringsAttachmentsContentVideoInsightsEn videoInsights =
      _StringsAttachmentsContentVideoInsightsEn._(_root);
}

// Path: sync.progressDialog
class _StringsSyncProgressDialogEn {
  _StringsSyncProgressDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Syncing…';
  String get preparing => 'Preparing…';
  String get pulling => 'Downloading changes…';
  String get pushing => 'Uploading changes…';
  String get uploadingMedia => 'Uploading media…';
  String get finalizing => 'Finalizing…';
}

// Path: sync.sections
class _StringsSyncSectionsEn {
  _StringsSyncSectionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get automation => 'Auto sync';
  String get backend => 'Sync method';
  String get mediaPreview => 'Media downloads';
  String get mediaBackup => 'Media uploads';
  String get securityActions => 'Security & manual sync';
}

// Path: sync.autoSync
class _StringsSyncAutoSyncEn {
  _StringsSyncAutoSyncEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto sync';
  String get subtitle => 'Keeps your devices in sync automatically.';
  String get wifiOnlyTitle => 'Auto sync on Wi‑Fi only';
  String get wifiOnlySubtitle =>
      'Save mobile data by syncing automatically only on Wi‑Fi';
}

// Path: sync.mediaPreview
class _StringsSyncMediaPreviewEn {
  _StringsSyncMediaPreviewEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get chatThumbnailsWifiOnlyTitle =>
      'Download media files on Wi‑Fi only';
  String get chatThumbnailsWifiOnlySubtitle =>
      'If an attachment isn\'t on this device yet, download it only on Wi‑Fi';
}

// Path: sync.mediaBackup
class _StringsSyncMediaBackupEn {
  _StringsSyncMediaBackupEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Media uploads';
  String get subtitle =>
      'Uploads encrypted images for cross‑device viewing and memory recall';
  String get wifiOnlyTitle => 'Upload on Wi‑Fi only';
  String get wifiOnlySubtitle => 'Avoid using mobile data for large uploads';
  String get description =>
      'Uploads encrypted image attachments to your sync storage. Images are downloaded on demand when viewing on another device.';
  String stats(
          {required Object pending,
          required Object failed,
          required Object uploaded}) =>
      'Queued ${pending} · Failed ${failed} · Uploaded ${uploaded}';
  String lastUploaded({required Object at}) => 'Last upload: ${at}';
  String lastError({required Object error}) => 'Last error: ${error}';
  String lastErrorWithTime({required Object at, required Object error}) =>
      'Last error (${at}): ${error}';
  String get backfillButton => 'Queue existing images';
  String get uploadNowButton => 'Upload now';
  String backfillEnqueued({required Object count}) =>
      'Queued ${count} images for upload';
  String backfillFailed({required Object error}) =>
      'Couldn\'t queue existing images: ${error}';
  String get notEnabled => 'Turn on Media uploads first.';
  String get managedVaultOnly =>
      'Media uploads are available with WebDAV or SecondLoop Cloud sync.';
  String get wifiOnlyBlocked =>
      'Wi‑Fi only is on. Connect to Wi‑Fi, or allow mobile data just this once.';
  String get uploaded => 'Upload complete';
  String get nothingToUpload => 'Nothing to upload';
  String uploadFailed({required Object error}) => 'Upload failed: ${error}';
  late final _StringsSyncMediaBackupCellularDialogEn cellularDialog =
      _StringsSyncMediaBackupCellularDialogEn._(_root);
}

// Path: sync.localCache
class _StringsSyncLocalCacheEn {
  _StringsSyncLocalCacheEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get button => 'Clear local storage';
  String get subtitle =>
      'Deletes cached attachment files on this device (remote copies are kept and can be re-downloaded). Make sure sync/upload has completed.';
  String get cleared => 'Cleared local cache';
  String failed({required Object error}) => 'Clear failed: ${error}';
  late final _StringsSyncLocalCacheDialogEn dialog =
      _StringsSyncLocalCacheDialogEn._(_root);
}

// Path: sync.cloudManagedVault
class _StringsSyncCloudManagedVaultEn {
  _StringsSyncCloudManagedVaultEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get signInRequired => 'Sign in to use SecondLoop Cloud sync.';
  String get paymentRequired =>
      'Cloud sync is paused. Renew your subscription to continue syncing.';
  String graceReadonlyUntil({required Object until}) =>
      'Cloud sync is read-only until ${until}.';
  String get storageQuotaExceeded =>
      'Cloud storage is full. Uploads are paused.';
  String storageQuotaExceededWithUsage(
          {required Object used, required Object limit}) =>
      'Cloud storage is full (${used} / ${limit}). Uploads are paused.';
  late final _StringsSyncCloudManagedVaultSwitchDialogEn switchDialog =
      _StringsSyncCloudManagedVaultSwitchDialogEn._(_root);
  late final _StringsSyncCloudManagedVaultSetPassphraseDialogEn
      setPassphraseDialog =
      _StringsSyncCloudManagedVaultSetPassphraseDialogEn._(_root);
}

// Path: sync.fields
class _StringsSyncFieldsEn {
  _StringsSyncFieldsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSyncFieldsBaseUrlEn baseUrl =
      _StringsSyncFieldsBaseUrlEn._(_root);
  late final _StringsSyncFieldsUsernameEn username =
      _StringsSyncFieldsUsernameEn._(_root);
  late final _StringsSyncFieldsPasswordEn password =
      _StringsSyncFieldsPasswordEn._(_root);
  late final _StringsSyncFieldsLocalDirEn localDir =
      _StringsSyncFieldsLocalDirEn._(_root);
  late final _StringsSyncFieldsManagedVaultBaseUrlEn managedVaultBaseUrl =
      _StringsSyncFieldsManagedVaultBaseUrlEn._(_root);
  late final _StringsSyncFieldsVaultIdEn vaultId =
      _StringsSyncFieldsVaultIdEn._(_root);
  late final _StringsSyncFieldsRemoteRootEn remoteRoot =
      _StringsSyncFieldsRemoteRootEn._(_root);
  late final _StringsSyncFieldsPassphraseEn passphrase =
      _StringsSyncFieldsPassphraseEn._(_root);
}

// Path: llmProfiles.deleteDialog
class _StringsLlmProfilesDeleteDialogEn {
  _StringsLlmProfilesDeleteDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Delete profile?';
  String message({required Object name}) =>
      'Delete "${name}"? This removes it from this device.';
}

// Path: llmProfiles.fields
class _StringsLlmProfilesFieldsEn {
  _StringsLlmProfilesFieldsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get name => 'Name';
  String get provider => 'Provider';
  String get baseUrlOptional => 'API endpoint (optional)';
  String get modelName => 'Model';
  String get apiKey => 'API key';
}

// Path: llmProfiles.providers
class _StringsLlmProfilesProvidersEn {
  _StringsLlmProfilesProvidersEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get openaiCompatible => 'OpenAI-compatible';
  String get geminiCompatible => 'Gemini';
  String get anthropicCompatible => 'Anthropic';
}

// Path: llmProfiles.actions
class _StringsLlmProfilesActionsEn {
  _StringsLlmProfilesActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get saveActivate => 'Save & Activate';
  String get cancel => 'Cancel';
  String get delete => 'Delete';
}

// Path: embeddingProfiles.reindexDialog
class _StringsEmbeddingProfilesReindexDialogEn {
  _StringsEmbeddingProfilesReindexDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Rebuild embeddings index?';
  String get message =>
      'Activating this profile may rebuild your local embeddings index using your API key/credits. This may take a while and can incur costs.';
  late final _StringsEmbeddingProfilesReindexDialogActionsEn actions =
      _StringsEmbeddingProfilesReindexDialogActionsEn._(_root);
}

// Path: embeddingProfiles.deleteDialog
class _StringsEmbeddingProfilesDeleteDialogEn {
  _StringsEmbeddingProfilesDeleteDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Delete profile?';
  String message({required Object name}) =>
      'Delete "${name}"? This removes it from this device.';
}

// Path: embeddingProfiles.fields
class _StringsEmbeddingProfilesFieldsEn {
  _StringsEmbeddingProfilesFieldsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get name => 'Name';
  String get provider => 'Provider';
  String get baseUrlOptional => 'API endpoint (optional)';
  String get modelName => 'Model';
  String get apiKey => 'API key';
}

// Path: embeddingProfiles.providers
class _StringsEmbeddingProfilesProvidersEn {
  _StringsEmbeddingProfilesProvidersEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get openaiCompatible => 'OpenAI-compatible';
}

// Path: embeddingProfiles.actions
class _StringsEmbeddingProfilesActionsEn {
  _StringsEmbeddingProfilesActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get saveActivate => 'Save & Activate';
  String get cancel => 'Cancel';
  String get delete => 'Delete';
}

// Path: actions.reviewQueue.inAppFallback
class _StringsActionsReviewQueueInAppFallbackEn {
  _StringsActionsReviewQueueInAppFallbackEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String message({required Object count}) =>
      '${count} items are waiting in your review queue';
  String get open => 'Open review queue';
  String get dismiss => 'Dismiss';
}

// Path: actions.reviewQueue.actions
class _StringsActionsReviewQueueActionsEn {
  _StringsActionsReviewQueueActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get schedule => 'Schedule';
  String get snooze => 'Tomorrow morning';
  String get start => 'Start';
  String get done => 'Done';
  String get dismiss => 'Dismiss';
}

// Path: actions.todoDelete.dialog
class _StringsActionsTodoDeleteDialogEn {
  _StringsActionsTodoDeleteDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Delete task?';
  String get message =>
      'This will permanently delete this task and all linked chat messages.';
  String get confirm => 'Delete';
}

// Path: actions.history.presets
class _StringsActionsHistoryPresetsEn {
  _StringsActionsHistoryPresetsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get thisWeek => 'This week';
  String get lastWeek => 'Last week';
  String get lastTwoWeeks => 'Last 2 weeks';
  String get custom => 'Custom range';
}

// Path: actions.history.actions
class _StringsActionsHistoryActionsEn {
  _StringsActionsHistoryActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get copy => 'Copy';
  String get copied => 'Copied';
}

// Path: actions.history.sections
class _StringsActionsHistorySectionsEn {
  _StringsActionsHistorySectionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get created => 'Created';
  String get started => 'Started';
  String get done => 'Done';
  String get dismissed => 'Dismissed';
}

// Path: settings.actionsReview.morningTime
class _StringsSettingsActionsReviewMorningTimeEn {
  _StringsSettingsActionsReviewMorningTimeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Morning review time';
  String get subtitle => 'Default reminder time for unplanned tasks';
}

// Path: settings.actionsReview.dayEndTime
class _StringsSettingsActionsReviewDayEndTimeEn {
  _StringsSettingsActionsReviewDayEndTimeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Day end time';
  String get subtitle => 'If not handled by this time, reminders back off';
}

// Path: settings.actionsReview.weeklyTime
class _StringsSettingsActionsReviewWeeklyTimeEn {
  _StringsSettingsActionsReviewWeeklyTimeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Weekly review time';
  String get subtitle => 'Weekly reminder time (Sunday)';
}

// Path: settings.actionsReview.inAppFallback
class _StringsSettingsActionsReviewInAppFallbackEn {
  _StringsSettingsActionsReviewInAppFallbackEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'In-app reminders';
  String get subtitle => 'Show todo notifications in app';
}

// Path: settings.quickCaptureHotkey.actions
class _StringsSettingsQuickCaptureHotkeyActionsEn {
  _StringsSettingsQuickCaptureHotkeyActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get resetDefault => 'Reset to default';
}

// Path: settings.quickCaptureHotkey.validation
class _StringsSettingsQuickCaptureHotkeyValidationEn {
  _StringsSettingsQuickCaptureHotkeyValidationEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get missingModifier =>
      'Use at least one modifier key (Ctrl/Alt/Shift/etc.)';
  String get modifierOnly => 'Shortcut must include a non-modifier key.';
  String systemConflict({required Object name}) =>
      'Conflicts with system shortcut: ${name}';
}

// Path: settings.quickCaptureHotkey.conflicts
class _StringsSettingsQuickCaptureHotkeyConflictsEn {
  _StringsSettingsQuickCaptureHotkeyConflictsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get macosSpotlight => 'Spotlight';
  String get macosFinderSearch => 'Finder search';
  String get macosInputSourceSwitch => 'Switch input source';
  String get macosEmojiPicker => 'Emoji & Symbols';
  String get macosScreenshot => 'Screenshot';
  String get macosAppSwitcher => 'App switcher';
  String get macosForceQuit => 'Force Quit';
  String get macosLockScreen => 'Lock screen';
  String get windowsLock => 'Lock screen';
  String get windowsShowDesktop => 'Show desktop';
  String get windowsFileExplorer => 'File Explorer';
  String get windowsRun => 'Run';
  String get windowsSearch => 'Search';
  String get windowsSettings => 'Settings';
  String get windowsTaskView => 'Task view';
  String get windowsLanguageSwitch => 'Switch input language';
  String get windowsAppSwitcher => 'App switcher';
}

// Path: settings.desktopBoot.startWithSystem
class _StringsSettingsDesktopBootStartWithSystemEn {
  _StringsSettingsDesktopBootStartWithSystemEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Start with system';
  String get subtitle => 'Launch SecondLoop automatically after sign-in';
}

// Path: settings.desktopBoot.silentStartup
class _StringsSettingsDesktopBootSilentStartupEn {
  _StringsSettingsDesktopBootSilentStartupEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Silent startup';
  String get subtitle =>
      'When auto-starting, run in background without showing a window';
}

// Path: settings.desktopBoot.keepRunningInBackground
class _StringsSettingsDesktopBootKeepRunningInBackgroundEn {
  _StringsSettingsDesktopBootKeepRunningInBackgroundEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Keep running in background';
  String get subtitle =>
      'When closing the window, minimize to tray instead of quitting';
}

// Path: settings.desktopTray.menu
class _StringsSettingsDesktopTrayMenuEn {
  _StringsSettingsDesktopTrayMenuEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get hide => 'Hide';
  String get quit => 'Quit';
}

// Path: settings.desktopTray.pro
class _StringsSettingsDesktopTrayProEn {
  _StringsSettingsDesktopTrayProEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get signedIn => 'Signed in';
  String get aiUsage => 'AI usage';
  String get storageUsage => 'Storage usage';
}

// Path: settings.language.options
class _StringsSettingsLanguageOptionsEn {
  _StringsSettingsLanguageOptionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get system => 'System';
  String systemWithValue({required Object value}) => 'System (${value})';
  String get en => 'English';
  String get zhCn => 'Simplified Chinese';
}

// Path: settings.theme.options
class _StringsSettingsThemeOptionsEn {
  _StringsSettingsThemeOptionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get system => 'System';
  String get light => 'Light';
  String get dark => 'Dark';
}

// Path: settings.aiSelection.askAi
class _StringsSettingsAiSelectionAskAiEn {
  _StringsSettingsAiSelectionAskAiEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Ask AI';
  String get description =>
      'Chat assistant provider for your messages and memory.';
  String get setupHint =>
      'Ask AI is not configured yet. Open Cloud account or add an API key profile to continue.';
  String get preferenceUnavailableHint =>
      'The selected Ask AI source is unavailable. Open Cloud account or API keys to finish setup.';
  late final _StringsSettingsAiSelectionAskAiStatusEn status =
      _StringsSettingsAiSelectionAskAiStatusEn._(_root);
  late final _StringsSettingsAiSelectionAskAiPreferenceEn preference =
      _StringsSettingsAiSelectionAskAiPreferenceEn._(_root);
  late final _StringsSettingsAiSelectionAskAiActionsEn actions =
      _StringsSettingsAiSelectionAskAiActionsEn._(_root);
}

// Path: settings.aiSelection.embeddings
class _StringsSettingsAiSelectionEmbeddingsEn {
  _StringsSettingsAiSelectionEmbeddingsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Semantic search & embeddings';
  String get description =>
      'Used for recall, todo linking, and Ask AI retrieval quality.';
  String get preferenceUnavailableHint =>
      'Selected embeddings source is unavailable. Running on fallback route.';
  late final _StringsSettingsAiSelectionEmbeddingsStatusEn status =
      _StringsSettingsAiSelectionEmbeddingsStatusEn._(_root);
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceEn preference =
      _StringsSettingsAiSelectionEmbeddingsPreferenceEn._(_root);
  late final _StringsSettingsAiSelectionEmbeddingsActionsEn actions =
      _StringsSettingsAiSelectionEmbeddingsActionsEn._(_root);
}

// Path: settings.aiSelection.mediaUnderstanding
class _StringsSettingsAiSelectionMediaUnderstandingEn {
  _StringsSettingsAiSelectionMediaUnderstandingEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Media understanding';
  String get description =>
      'OCR, captions, and audio transcription source selection.';
  String get preferenceUnavailableHint =>
      'Selected media source is unavailable. Running on fallback route.';
  late final _StringsSettingsAiSelectionMediaUnderstandingStatusEn status =
      _StringsSettingsAiSelectionMediaUnderstandingStatusEn._(_root);
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceEn
      preference =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceEn._(_root);
  late final _StringsSettingsAiSelectionMediaUnderstandingActionsEn actions =
      _StringsSettingsAiSelectionMediaUnderstandingActionsEn._(_root);
}

// Path: settings.semanticParseAutoActions.dialogActions
class _StringsSettingsSemanticParseAutoActionsDialogActionsEn {
  _StringsSettingsSemanticParseAutoActionsDialogActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get enable => 'Enable';
}

// Path: settings.mediaAnnotation.routingGuide
class _StringsSettingsMediaAnnotationRoutingGuideEn {
  _StringsSettingsMediaAnnotationRoutingGuideEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Choose your AI source';
  String get pro => 'Pro + signed in: uses SecondLoop Cloud by default.';
  String get byok =>
      'Free/BYOK: add an OpenAI-compatible profile in Ask AI settings, then set it active.';
}

// Path: settings.mediaAnnotation.documentOcr
class _StringsSettingsMediaAnnotationDocumentOcrEn {
  _StringsSettingsMediaAnnotationDocumentOcrEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Document OCR';
  late final _StringsSettingsMediaAnnotationDocumentOcrEnabledEn enabled =
      _StringsSettingsMediaAnnotationDocumentOcrEnabledEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsEn
      languageHints =
      _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesEn
      pdfAutoMaxPages =
      _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrPdfDpiEn pdfDpi =
      _StringsSettingsMediaAnnotationDocumentOcrPdfDpiEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsEn
      linuxModels =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsEn._(_root);
}

// Path: settings.mediaAnnotation.audioTranscribe
class _StringsSettingsMediaAnnotationAudioTranscribeEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Audio transcription';
  late final _StringsSettingsMediaAnnotationAudioTranscribeEnabledEn enabled =
      _StringsSettingsMediaAnnotationAudioTranscribeEnabledEn._(_root);
  late final _StringsSettingsMediaAnnotationAudioTranscribeEngineEn engine =
      _StringsSettingsMediaAnnotationAudioTranscribeEngineEn._(_root);
  late final _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiEn
      configureApi =
      _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiEn._(_root);
}

// Path: settings.mediaAnnotation.imageCaption
class _StringsSettingsMediaAnnotationImageCaptionEn {
  _StringsSettingsMediaAnnotationImageCaptionEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Image captions';
}

// Path: settings.mediaAnnotation.providerSettings
class _StringsSettingsMediaAnnotationProviderSettingsEn {
  _StringsSettingsMediaAnnotationProviderSettingsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Image caption provider';
}

// Path: settings.mediaAnnotation.setupRequired
class _StringsSettingsMediaAnnotationSetupRequiredEn {
  _StringsSettingsMediaAnnotationSetupRequiredEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Image annotations setup required';
  String get body => 'To annotate images, SecondLoop needs a multimodal model.';
  late final _StringsSettingsMediaAnnotationSetupRequiredReasonsEn reasons =
      _StringsSettingsMediaAnnotationSetupRequiredReasonsEn._(_root);
}

// Path: settings.mediaAnnotation.annotateEnabled
class _StringsSettingsMediaAnnotationAnnotateEnabledEn {
  _StringsSettingsMediaAnnotationAnnotateEnabledEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Annotate images';
  String get subtitle =>
      'When you add a photo, SecondLoop may send it to AI to generate an encrypted caption.';
}

// Path: settings.mediaAnnotation.searchEnabled
class _StringsSettingsMediaAnnotationSearchEnabledEn {
  _StringsSettingsMediaAnnotationSearchEnabledEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Use annotations for search';
  String get subtitle => 'Include image captions when building search data.';
}

// Path: settings.mediaAnnotation.searchToggleConfirm
class _StringsSettingsMediaAnnotationSearchToggleConfirmEn {
  _StringsSettingsMediaAnnotationSearchToggleConfirmEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Update search index?';
  String get bodyEnable =>
      'Turning this on will rebuild search data so image captions become searchable.';
  String get bodyDisable =>
      'Turning this off will rebuild search data to remove image captions from search.';
}

// Path: settings.mediaAnnotation.advanced
class _StringsSettingsMediaAnnotationAdvancedEn {
  _StringsSettingsMediaAnnotationAdvancedEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Advanced';
}

// Path: settings.mediaAnnotation.providerMode
class _StringsSettingsMediaAnnotationProviderModeEn {
  _StringsSettingsMediaAnnotationProviderModeEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Multimodal model';
  String get subtitle => 'Use a different provider/model for image captions.';
  late final _StringsSettingsMediaAnnotationProviderModeLabelsEn labels =
      _StringsSettingsMediaAnnotationProviderModeLabelsEn._(_root);
  late final _StringsSettingsMediaAnnotationProviderModeDescriptionsEn
      descriptions =
      _StringsSettingsMediaAnnotationProviderModeDescriptionsEn._(_root);
}

// Path: settings.mediaAnnotation.cloudModelName
class _StringsSettingsMediaAnnotationCloudModelNameEn {
  _StringsSettingsMediaAnnotationCloudModelNameEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Cloud model name';
  String get subtitle => 'Override the cloud multimodal model name (optional).';
  String get hint => 'e.g. gpt-4o-mini';
  String get followAskAi => 'Follow Ask AI';
}

// Path: settings.mediaAnnotation.byokProfile
class _StringsSettingsMediaAnnotationByokProfileEn {
  _StringsSettingsMediaAnnotationByokProfileEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API key profile';
  String get subtitle => 'Pick which profile to use for image captions.';
  String get unset => 'Not set';
  String get missingBackend => 'Not available in this build.';
  String get noOpenAiCompatibleProfiles =>
      'No OpenAI‑compatible profiles found. Add one in API keys.';
}

// Path: settings.mediaAnnotation.allowCellular
class _StringsSettingsMediaAnnotationAllowCellularEn {
  _StringsSettingsMediaAnnotationAllowCellularEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Allow cellular data';
  String get subtitle =>
      'Use mobile data to annotate images. (Wi‑Fi only by default.)';
}

// Path: settings.mediaAnnotation.allowCellularConfirm
class _StringsSettingsMediaAnnotationAllowCellularConfirmEn {
  _StringsSettingsMediaAnnotationAllowCellularConfirmEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Use cellular data for image annotations?';
  String get body =>
      'Annotating images may upload photos to your chosen AI provider and can use significant data.';
}

// Path: settings.cloudEmbeddings.dialogActions
class _StringsSettingsCloudEmbeddingsDialogActionsEn {
  _StringsSettingsCloudEmbeddingsDialogActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get enable => 'Enable';
}

// Path: settings.cloudAccount.benefits
class _StringsSettingsCloudAccountBenefitsEn {
  _StringsSettingsCloudAccountBenefitsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Create a cloud account to subscribe';
  late final _StringsSettingsCloudAccountBenefitsItemsEn items =
      _StringsSettingsCloudAccountBenefitsItemsEn._(_root);
}

// Path: settings.cloudAccount.errors
class _StringsSettingsCloudAccountErrorsEn {
  _StringsSettingsCloudAccountErrorsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get missingWebApiKey =>
      'Cloud sign-in isn\'t available in this build. If you\'re running from source, run `pixi run init-env` (or copy `.env.example` → `.env.local`), set `SECONDLOOP_FIREBASE_WEB_API_KEY`, then restart the app.';
}

// Path: settings.cloudAccount.fields
class _StringsSettingsCloudAccountFieldsEn {
  _StringsSettingsCloudAccountFieldsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get email => 'Email';
  String get password => 'Password';
}

// Path: settings.cloudAccount.actions
class _StringsSettingsCloudAccountActionsEn {
  _StringsSettingsCloudAccountActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get signIn => 'Sign in';
  String get signUp => 'Create account';
  String get signOut => 'Sign out';
}

// Path: settings.cloudAccount.emailVerification
class _StringsSettingsCloudAccountEmailVerificationEn {
  _StringsSettingsCloudAccountEmailVerificationEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Email verification';
  late final _StringsSettingsCloudAccountEmailVerificationStatusEn status =
      _StringsSettingsCloudAccountEmailVerificationStatusEn._(_root);
  late final _StringsSettingsCloudAccountEmailVerificationLabelsEn labels =
      _StringsSettingsCloudAccountEmailVerificationLabelsEn._(_root);
  late final _StringsSettingsCloudAccountEmailVerificationActionsEn actions =
      _StringsSettingsCloudAccountEmailVerificationActionsEn._(_root);
  late final _StringsSettingsCloudAccountEmailVerificationMessagesEn messages =
      _StringsSettingsCloudAccountEmailVerificationMessagesEn._(_root);
}

// Path: settings.cloudUsage.actions
class _StringsSettingsCloudUsageActionsEn {
  _StringsSettingsCloudUsageActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get refresh => 'Refresh';
}

// Path: settings.cloudUsage.labels
class _StringsSettingsCloudUsageLabelsEn {
  _StringsSettingsCloudUsageLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get gatewayNotConfigured =>
      'Cloud usage isn\'t available in this build.';
  String get signInRequired => 'Sign in to view usage.';
  String get usage => 'Usage:';
  String get askAiUsage => 'Ask AI:';
  String get embeddingsUsage => 'Smarter search:';
  String get inputTokensUsed30d => 'Input tokens (30d):';
  String get outputTokensUsed30d => 'Output tokens (30d):';
  String get tokensUsed30d => 'Tokens (30d):';
  String get requestsUsed30d => 'Requests (30d):';
  String get resetAt => 'Resets on:';
  String get paymentRequired => 'Subscription required to view cloud usage.';
  String loadFailed({required Object error}) => 'Failed to load: ${error}';
}

// Path: settings.vaultUsage.actions
class _StringsSettingsVaultUsageActionsEn {
  _StringsSettingsVaultUsageActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get refresh => 'Refresh';
}

// Path: settings.vaultUsage.labels
class _StringsSettingsVaultUsageLabelsEn {
  _StringsSettingsVaultUsageLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get notConfigured => 'Vault storage isn\'t available in this build.';
  String get signInRequired => 'Sign in to view vault storage.';
  String get used => 'Used:';
  String get limit => 'Limit:';
  String get attachments => 'Photos & files:';
  String get ops => 'Sync history:';
  String loadFailed({required Object error}) => 'Failed to load: ${error}';
}

// Path: settings.diagnostics.messages
class _StringsSettingsDiagnosticsMessagesEn {
  _StringsSettingsDiagnosticsMessagesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get copied => 'Diagnostics copied to clipboard';
  String copyFailed({required Object error}) =>
      'Failed to copy diagnostics: ${error}';
  String shareFailed({required Object error}) =>
      'Failed to share diagnostics: ${error}';
}

// Path: settings.byokUsage.errors
class _StringsSettingsByokUsageErrorsEn {
  _StringsSettingsByokUsageErrorsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String unavailable({required Object error}) => 'Usage unavailable: ${error}';
}

// Path: settings.byokUsage.sections
class _StringsSettingsByokUsageSectionsEn {
  _StringsSettingsByokUsageSectionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String today({required Object day}) => 'Today (${day})';
  String last30d({required Object start, required Object end}) =>
      'Last 30 days (${start} → ${end})';
}

// Path: settings.byokUsage.labels
class _StringsSettingsByokUsageLabelsEn {
  _StringsSettingsByokUsageLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String requests({required Object purpose}) => '${purpose} requests';
  String tokens({required Object purpose}) =>
      '${purpose} tokens (in/out/total)';
}

// Path: settings.byokUsage.purposes
class _StringsSettingsByokUsagePurposesEn {
  _StringsSettingsByokUsagePurposesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get semanticParse => 'Semantic parse';
  String get mediaAnnotation => 'Image annotations';
}

// Path: settings.subscription.benefits
class _StringsSettingsSubscriptionBenefitsEn {
  _StringsSettingsSubscriptionBenefitsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'SecondLoop Pro unlocks';
  late final _StringsSettingsSubscriptionBenefitsItemsEn items =
      _StringsSettingsSubscriptionBenefitsItemsEn._(_root);
}

// Path: settings.subscription.status
class _StringsSettingsSubscriptionStatusEn {
  _StringsSettingsSubscriptionStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get unknown => 'Unknown';
  String get entitled => 'Active';
  String get notEntitled => 'Inactive';
}

// Path: settings.subscription.actions
class _StringsSettingsSubscriptionActionsEn {
  _StringsSettingsSubscriptionActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get purchase => 'Subscribe';
}

// Path: settings.subscription.labels
class _StringsSettingsSubscriptionLabelsEn {
  _StringsSettingsSubscriptionLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get status => 'Status:';
  String get purchaseUnavailable => 'Purchases are not available yet.';
  String loadFailed({required Object error}) => 'Failed to load: ${error}';
}

// Path: chat.markdownEditor.actions
class _StringsChatMarkdownEditorActionsEn {
  _StringsChatMarkdownEditorActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get heading => 'Heading';
  String headingLevel({required Object level}) => 'Heading ${level}';
  String get bold => 'Bold';
  String get italic => 'Italic';
  String get strike => 'Strikethrough';
  String get code => 'Inline code';
  String get link => 'Insert link';
  String get blockquote => 'Blockquote';
  String get bulletList => 'Bullet list';
  String get orderedList => 'Ordered list';
  String get taskList => 'Task list';
  String get codeBlock => 'Code block';
}

// Path: chat.askAiSetup.actions
class _StringsChatAskAiSetupActionsEn {
  _StringsChatAskAiSetupActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get subscribe => 'Subscribe';
  String get configureByok => 'Add API key';
}

// Path: chat.cloudGateway.fallback
class _StringsChatCloudGatewayFallbackEn {
  _StringsChatCloudGatewayFallbackEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get auth =>
      'Cloud sign-in required. Using your API key for this request.';
  String get entitlement =>
      'Cloud subscription required. Using your API key for this request.';
  String get rateLimited =>
      'Cloud is busy. Using your API key for this request.';
  String get generic =>
      'Cloud request failed. Using your API key for this request.';
}

// Path: chat.cloudGateway.errors
class _StringsChatCloudGatewayErrorsEn {
  _StringsChatCloudGatewayErrorsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get auth =>
      'Cloud sign-in required. Open Cloud account and sign in again.';
  String get entitlement =>
      'Cloud subscription required. Add an API key or try again later.';
  String get rateLimited => 'Cloud is rate limited. Please try again later.';
  String get generic => 'Cloud request failed.';
}

// Path: chat.embeddingsConsent.actions
class _StringsChatEmbeddingsConsentActionsEn {
  _StringsChatEmbeddingsConsentActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get useLocal => 'Use local';
  String get enableCloud => 'Enable cloud embeddings';
}

// Path: chat.topicThread.deleteDialog
class _StringsChatTopicThreadDeleteDialogEn {
  _StringsChatTopicThreadDeleteDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Delete topic thread?';
  String get message =>
      'Deleting removes this thread and its message memberships.';
  String get confirm => 'Delete';
}

// Path: chat.tagFilter.sheet
class _StringsChatTagFilterSheetEn {
  _StringsChatTagFilterSheetEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Filter by tags';
  String get apply => 'Apply';
  String get clear => 'Clear';
  String get includeHint => 'Tap: Include';
  String get excludeHint => 'Tap again: Exclude';
  String get empty => 'No tags yet';
}

// Path: chat.tagPicker.mergeDialog
class _StringsChatTagPickerMergeDialogEn {
  _StringsChatTagPickerMergeDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Merge tags?';
  String message({required Object source, required Object target}) =>
      'Merge "${source}" into "${target}"? This updates existing message tags.';
  String get confirm => 'Merge';
}

// Path: chat.askScopeEmpty.actions
class _StringsChatAskScopeEmptyActionsEn {
  _StringsChatAskScopeEmptyActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get expandTimeWindow => 'Expand time window';
  String get removeIncludeTags => 'Remove include tags';
  String get switchScopeToAll => 'Switch scope to All';
}

// Path: attachments.content.speechTranscribeIssue
class _StringsAttachmentsContentSpeechTranscribeIssueEn {
  _StringsAttachmentsContentSpeechTranscribeIssueEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Speech transcription unavailable';
  String get openSettings => 'Open settings';
  String get openSettingsFailed =>
      'Unable to open system settings automatically. Please check speech permission and Dictation manually.';
  String get permissionDenied =>
      'Speech permission was denied. Tap Retry to request it again, or open system settings if it remains blocked.';
  String get permissionRestricted =>
      'Speech recognition is restricted by system policy. Check Screen Time or device management policy.';
  String get serviceDisabled =>
      'Siri and Dictation are disabled. Please enable them before retrying.';
  String get runtimeUnavailable =>
      'Speech runtime is currently unavailable on this device. Please retry later.';
  String get permissionRequest =>
      'Local speech transcription needs speech permission. Tap Retry and allow the system permission prompt.';
  String get offlineUnavailable =>
      'On-device offline speech recognition is unavailable for this device or language. Install speech packs or switch to cloud transcription.';
}

// Path: attachments.content.videoInsights
class _StringsAttachmentsContentVideoInsightsEn {
  _StringsAttachmentsContentVideoInsightsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsAttachmentsContentVideoInsightsContentKindEn contentKind =
      _StringsAttachmentsContentVideoInsightsContentKindEn._(_root);
  late final _StringsAttachmentsContentVideoInsightsDetailEn detail =
      _StringsAttachmentsContentVideoInsightsDetailEn._(_root);
  late final _StringsAttachmentsContentVideoInsightsFieldsEn fields =
      _StringsAttachmentsContentVideoInsightsFieldsEn._(_root);
}

// Path: sync.mediaBackup.cellularDialog
class _StringsSyncMediaBackupCellularDialogEn {
  _StringsSyncMediaBackupCellularDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Use mobile data?';
  String get message =>
      'Wi‑Fi only is on. Uploading over mobile data may use a lot of data.';
  String get confirm => 'Use mobile data';
}

// Path: sync.localCache.dialog
class _StringsSyncLocalCacheDialogEn {
  _StringsSyncLocalCacheDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Clear local storage?';
  String get message =>
      'This deletes cached photos and files on this device to save space. Your remote sync storage keeps a copy; items will be re-downloaded on demand when viewed again.';
  String get confirm => 'Clear';
}

// Path: sync.cloudManagedVault.switchDialog
class _StringsSyncCloudManagedVaultSwitchDialogEn {
  _StringsSyncCloudManagedVaultSwitchDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Switch to SecondLoop Cloud sync?';
  String get message =>
      'Your subscription is active. Switch your sync method to SecondLoop Cloud? You can change this anytime.';
  String get cancel => 'Not now';
  String get confirm => 'Switch';
}

// Path: sync.cloudManagedVault.setPassphraseDialog
class _StringsSyncCloudManagedVaultSetPassphraseDialogEn {
  _StringsSyncCloudManagedVaultSetPassphraseDialogEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Set sync passphrase';
  String get confirm => 'Save passphrase';
}

// Path: sync.fields.baseUrl
class _StringsSyncFieldsBaseUrlEn {
  _StringsSyncFieldsBaseUrlEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Server address';
  String get hint => 'https://example.com/dav';
}

// Path: sync.fields.username
class _StringsSyncFieldsUsernameEn {
  _StringsSyncFieldsUsernameEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Username (optional)';
}

// Path: sync.fields.password
class _StringsSyncFieldsPasswordEn {
  _StringsSyncFieldsPasswordEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Password (optional)';
}

// Path: sync.fields.localDir
class _StringsSyncFieldsLocalDirEn {
  _StringsSyncFieldsLocalDirEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Folder path';
  String get hint => '/Users/me/SecondLoopVault';
  String get helper =>
      'Best for desktop; mobile platforms may not support this path.';
}

// Path: sync.fields.managedVaultBaseUrl
class _StringsSyncFieldsManagedVaultBaseUrlEn {
  _StringsSyncFieldsManagedVaultBaseUrlEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Cloud server address (advanced)';
  String get hint => 'https://vault.example.com';
}

// Path: sync.fields.vaultId
class _StringsSyncFieldsVaultIdEn {
  _StringsSyncFieldsVaultIdEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Cloud account ID';
  String get hint => 'Auto';
}

// Path: sync.fields.remoteRoot
class _StringsSyncFieldsRemoteRootEn {
  _StringsSyncFieldsRemoteRootEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Folder name';
  String get hint => 'SecondLoop';
}

// Path: sync.fields.passphrase
class _StringsSyncFieldsPassphraseEn {
  _StringsSyncFieldsPassphraseEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Sync passphrase';
  String get helper =>
      'Use the same passphrase on all devices. It’s never uploaded.';
}

// Path: embeddingProfiles.reindexDialog.actions
class _StringsEmbeddingProfilesReindexDialogActionsEn {
  _StringsEmbeddingProfilesReindexDialogActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get continueLabel => 'Continue';
}

// Path: settings.aiSelection.askAi.status
class _StringsSettingsAiSelectionAskAiStatusEn {
  _StringsSettingsAiSelectionAskAiStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get loading => 'Checking current route...';
  String get cloud => 'Current route: SecondLoop Cloud';
  String get byok => 'Current route: API key profile (BYOK)';
  String get notConfigured => 'Current route: setup required';
}

// Path: settings.aiSelection.askAi.preference
class _StringsSettingsAiSelectionAskAiPreferenceEn {
  _StringsSettingsAiSelectionAskAiPreferenceEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsAiSelectionAskAiPreferenceAutoEn auto =
      _StringsSettingsAiSelectionAskAiPreferenceAutoEn._(_root);
  late final _StringsSettingsAiSelectionAskAiPreferenceCloudEn cloud =
      _StringsSettingsAiSelectionAskAiPreferenceCloudEn._(_root);
  late final _StringsSettingsAiSelectionAskAiPreferenceByokEn byok =
      _StringsSettingsAiSelectionAskAiPreferenceByokEn._(_root);
}

// Path: settings.aiSelection.askAi.actions
class _StringsSettingsAiSelectionAskAiActionsEn {
  _StringsSettingsAiSelectionAskAiActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get openCloud => 'Open Cloud account';
  String get openByok => 'Open API keys';
}

// Path: settings.aiSelection.embeddings.status
class _StringsSettingsAiSelectionEmbeddingsStatusEn {
  _StringsSettingsAiSelectionEmbeddingsStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get loading => 'Checking current route...';
  String get cloud => 'Current route: SecondLoop Cloud';
  String get byok => 'Current route: Embedding API key (BYOK)';
  String get local => 'Current route: Local embeddings runtime';
}

// Path: settings.aiSelection.embeddings.preference
class _StringsSettingsAiSelectionEmbeddingsPreferenceEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceAutoEn auto =
      _StringsSettingsAiSelectionEmbeddingsPreferenceAutoEn._(_root);
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceCloudEn cloud =
      _StringsSettingsAiSelectionEmbeddingsPreferenceCloudEn._(_root);
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceByokEn byok =
      _StringsSettingsAiSelectionEmbeddingsPreferenceByokEn._(_root);
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceLocalEn local =
      _StringsSettingsAiSelectionEmbeddingsPreferenceLocalEn._(_root);
}

// Path: settings.aiSelection.embeddings.actions
class _StringsSettingsAiSelectionEmbeddingsActionsEn {
  _StringsSettingsAiSelectionEmbeddingsActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get openEmbeddingProfiles => 'Open embedding API keys';
  String get openCloudAccount => 'Open Cloud account';
}

// Path: settings.aiSelection.mediaUnderstanding.status
class _StringsSettingsAiSelectionMediaUnderstandingStatusEn {
  _StringsSettingsAiSelectionMediaUnderstandingStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get loading => 'Checking current route...';
  String get cloud => 'Current route: SecondLoop Cloud';
  String get byok => 'Current route: API key profile (BYOK)';
  String get local => 'Current route: Local runtime/native capabilities';
}

// Path: settings.aiSelection.mediaUnderstanding.preference
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoEn
      auto =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoEn._(_root);
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudEn
      cloud =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudEn._(_root);
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokEn
      byok =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokEn._(_root);
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalEn
      local =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalEn._(_root);
}

// Path: settings.aiSelection.mediaUnderstanding.actions
class _StringsSettingsAiSelectionMediaUnderstandingActionsEn {
  _StringsSettingsAiSelectionMediaUnderstandingActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get openSettings => 'Open media understanding settings';
  String get openCloudAccount => 'Open Cloud account';
  String get openByok => 'Open API keys';
}

// Path: settings.mediaAnnotation.documentOcr.enabled
class _StringsSettingsMediaAnnotationDocumentOcrEnabledEn {
  _StringsSettingsMediaAnnotationDocumentOcrEnabledEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Enable OCR';
  String get subtitle =>
      'Run OCR for scanned PDFs and video keyframes when text extraction is insufficient.';
}

// Path: settings.mediaAnnotation.documentOcr.languageHints
class _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Language hints';
  String get subtitle => 'Choose preferred languages for OCR recognition.';
  late final _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsEn
      labels =
      _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsEn._(_root);
}

// Path: settings.mediaAnnotation.documentOcr.pdfAutoMaxPages
class _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesEn {
  _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto OCR page limit';
  String get subtitle =>
      'PDFs above this limit stay in needs-OCR state until you run OCR manually in viewer.';
  String get manualOnly => 'Manual only';
  String pages({required Object count}) => '${count} pages';
}

// Path: settings.mediaAnnotation.documentOcr.pdfDpi
class _StringsSettingsMediaAnnotationDocumentOcrPdfDpiEn {
  _StringsSettingsMediaAnnotationDocumentOcrPdfDpiEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'OCR DPI';
  String get subtitle =>
      'Higher DPI may improve accuracy but costs more processing time.';
  String value({required Object dpi}) => '${dpi} dpi';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Desktop OCR models';
  String get subtitle =>
      'Download local OCR model files for desktop (Linux/macOS/Windows).';
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusEn
      status =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsEn
      actions =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsEn._(_root);
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteEn
      confirmDelete =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteEn._(
          _root);
}

// Path: settings.mediaAnnotation.audioTranscribe.enabled
class _StringsSettingsMediaAnnotationAudioTranscribeEnabledEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEnabledEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Transcribe audio attachments';
  String get subtitle =>
      'When you add audio, SecondLoop can transcribe it and save encrypted transcript text for playback and search.';
}

// Path: settings.mediaAnnotation.audioTranscribe.engine
class _StringsSettingsMediaAnnotationAudioTranscribeEngineEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEngineEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Transcription engine';
  String get subtitle => 'Choose which engine to use for audio transcription.';
  String get notAvailable => 'Unavailable';
  late final _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsEn
      labels =
      _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsEn._(_root);
  late final _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsEn
      descriptions =
      _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsEn._(
          _root);
}

// Path: settings.mediaAnnotation.audioTranscribe.configureApi
class _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiEn {
  _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Configure transcription API';
  String get subtitle =>
      'Pro users can use SecondLoop Cloud. Free users can use an OpenAI-compatible API key profile from Ask AI settings.';
  String get body =>
      'Audio transcription can run with SecondLoop Cloud (requires Pro + sign-in) or an OpenAI-compatible API key profile from Ask AI settings.';
  String get openCloud => 'Open Cloud account';
  String get openApiKeys => 'Open API keys';
}

// Path: settings.mediaAnnotation.setupRequired.reasons
class _StringsSettingsMediaAnnotationSetupRequiredReasonsEn {
  _StringsSettingsMediaAnnotationSetupRequiredReasonsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get cloudUnavailable =>
      'SecondLoop Cloud is not available in this build.';
  String get cloudRequiresPro => 'SecondLoop Cloud requires Pro.';
  String get cloudSignIn =>
      'Sign in to SecondLoop Cloud to use the Cloud model.';
  String get byokOpenAiCompatible =>
      'Add an OpenAI‑compatible API key profile.';
  String get followAskAi =>
      'Ask AI must use an OpenAI‑compatible profile, or choose a different multimodal model in Advanced.';
}

// Path: settings.mediaAnnotation.providerMode.labels
class _StringsSettingsMediaAnnotationProviderModeLabelsEn {
  _StringsSettingsMediaAnnotationProviderModeLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get followAskAi => 'Follow Ask AI';
  String get cloudGateway => 'SecondLoop Cloud';
  String get byokProfile => 'API key (profile)';
}

// Path: settings.mediaAnnotation.providerMode.descriptions
class _StringsSettingsMediaAnnotationProviderModeDescriptionsEn {
  _StringsSettingsMediaAnnotationProviderModeDescriptionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get followAskAi => 'Use the same setup as Ask AI. (Recommended)';
  String get cloudGateway =>
      'Use SecondLoop Cloud when available. (Requires Pro)';
  String get byokProfile =>
      'Use a specific API key profile (OpenAI‑compatible).';
}

// Path: settings.cloudAccount.benefits.items
class _StringsSettingsCloudAccountBenefitsItemsEn {
  _StringsSettingsCloudAccountBenefitsItemsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsCloudAccountBenefitsItemsPurchaseEn purchase =
      _StringsSettingsCloudAccountBenefitsItemsPurchaseEn._(_root);
}

// Path: settings.cloudAccount.emailVerification.status
class _StringsSettingsCloudAccountEmailVerificationStatusEn {
  _StringsSettingsCloudAccountEmailVerificationStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get unknown => 'Unknown';
  String get verified => 'Verified';
  String get notVerified => 'Not verified';
}

// Path: settings.cloudAccount.emailVerification.labels
class _StringsSettingsCloudAccountEmailVerificationLabelsEn {
  _StringsSettingsCloudAccountEmailVerificationLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get status => 'Status:';
  String get help => 'Verify your email to use SecondLoop Cloud Ask AI.';
  String get verifiedHelp =>
      'Email is verified. You can continue to subscribe.';
  String loadFailed({required Object error}) => 'Failed to load: ${error}';
}

// Path: settings.cloudAccount.emailVerification.actions
class _StringsSettingsCloudAccountEmailVerificationActionsEn {
  _StringsSettingsCloudAccountEmailVerificationActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get resend => 'Resend verification email';
  String resendCooldown({required Object seconds}) => 'Resend in ${seconds}s';
}

// Path: settings.cloudAccount.emailVerification.messages
class _StringsSettingsCloudAccountEmailVerificationMessagesEn {
  _StringsSettingsCloudAccountEmailVerificationMessagesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get verificationEmailSent => 'Verification email sent';
  String get verificationAlreadyDone => 'Email is already verified.';
  String get signUpVerificationPrompt =>
      'Account created. Please verify your email before subscribing.';
  String verificationEmailSendFailed({required Object error}) =>
      'Failed to send verification email: ${error}';
}

// Path: settings.subscription.benefits.items
class _StringsSettingsSubscriptionBenefitsItemsEn {
  _StringsSettingsSubscriptionBenefitsItemsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsSettingsSubscriptionBenefitsItemsNoSetupEn noSetup =
      _StringsSettingsSubscriptionBenefitsItemsNoSetupEn._(_root);
  late final _StringsSettingsSubscriptionBenefitsItemsCloudSyncEn cloudSync =
      _StringsSettingsSubscriptionBenefitsItemsCloudSyncEn._(_root);
  late final _StringsSettingsSubscriptionBenefitsItemsMobileSearchEn
      mobileSearch =
      _StringsSettingsSubscriptionBenefitsItemsMobileSearchEn._(_root);
}

// Path: attachments.content.videoInsights.contentKind
class _StringsAttachmentsContentVideoInsightsContentKindEn {
  _StringsAttachmentsContentVideoInsightsContentKindEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get knowledge => 'Knowledge video';
  String get nonKnowledge => 'Non-knowledge video';
  String get unknown => 'Unknown';
}

// Path: attachments.content.videoInsights.detail
class _StringsAttachmentsContentVideoInsightsDetailEn {
  _StringsAttachmentsContentVideoInsightsDetailEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get knowledgeMarkdown => 'Knowledge markdown';
  String get videoDescription => 'Video description';
  String get extractedContent => 'Extracted content';
}

// Path: attachments.content.videoInsights.fields
class _StringsAttachmentsContentVideoInsightsFieldsEn {
  _StringsAttachmentsContentVideoInsightsFieldsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get contentType => 'Content type';
  String get segments => 'Segments';
  String get summary => 'Video summary';
}

// Path: settings.aiSelection.askAi.preference.auto
class _StringsSettingsAiSelectionAskAiPreferenceAutoEn {
  _StringsSettingsAiSelectionAskAiPreferenceAutoEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto';
  String get description => 'Prefer Cloud when available, otherwise use BYOK.';
}

// Path: settings.aiSelection.askAi.preference.cloud
class _StringsSettingsAiSelectionAskAiPreferenceCloudEn {
  _StringsSettingsAiSelectionAskAiPreferenceCloudEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'SecondLoop Cloud';
  String get description =>
      'Use Cloud only. Ask AI stays unavailable until Cloud is ready.';
}

// Path: settings.aiSelection.askAi.preference.byok
class _StringsSettingsAiSelectionAskAiPreferenceByokEn {
  _StringsSettingsAiSelectionAskAiPreferenceByokEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API key (BYOK)';
  String get description =>
      'Use BYOK only. Ask AI stays unavailable until an active profile exists.';
}

// Path: settings.aiSelection.embeddings.preference.auto
class _StringsSettingsAiSelectionEmbeddingsPreferenceAutoEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceAutoEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto';
  String get description => 'Prefer Cloud, then BYOK, then local runtime.';
}

// Path: settings.aiSelection.embeddings.preference.cloud
class _StringsSettingsAiSelectionEmbeddingsPreferenceCloudEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceCloudEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'SecondLoop Cloud';
  String get description =>
      'Prefer Cloud. If unavailable, fallback to BYOK or local runtime.';
}

// Path: settings.aiSelection.embeddings.preference.byok
class _StringsSettingsAiSelectionEmbeddingsPreferenceByokEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceByokEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API key (BYOK)';
  String get description =>
      'Prefer BYOK. Automatically fallback to local runtime on failure.';
}

// Path: settings.aiSelection.embeddings.preference.local
class _StringsSettingsAiSelectionEmbeddingsPreferenceLocalEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceLocalEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Local runtime';
  String get description =>
      'Run embeddings only on local runtime when available.';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.auto
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto';
  String get description => 'Prefer Cloud, then BYOK, then local capabilities.';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.cloud
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'SecondLoop Cloud';
  String get description =>
      'Prefer Cloud. If unavailable, fallback to BYOK or local capabilities.';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.byok
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'API key (BYOK)';
  String get description =>
      'Prefer BYOK. Automatically fallback to local capabilities on failure.';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.local
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Local capabilities';
  String get description =>
      'Prefer local runtime/native media understanding only.';
}

// Path: settings.mediaAnnotation.documentOcr.languageHints.labels
class _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get devicePlusEn => 'Device language + English';
  String get en => 'English';
  String get zhEn => 'Chinese + English';
  String get jaEn => 'Japanese + English';
  String get koEn => 'Korean + English';
  String get frEn => 'French + English';
  String get deEn => 'German + English';
  String get esEn => 'Spanish + English';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels.status
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get notInstalled => 'Not installed';
  String get runtimeMissing =>
      'Models are downloaded, but OCR runtime is not ready';
  String get downloading => 'Downloading...';
  String installed({required Object count, required Object size}) =>
      'Installed: ${count} files (${size})';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels.actions
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get download => 'Download models';
  String get redownload => 'Re-download';
  String get delete => 'Delete models';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteEn._(
      this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Delete downloaded OCR models?';
  String get body =>
      'Local desktop OCR may stop working until models are downloaded again.';
  String get confirm => 'Delete';
}

// Path: settings.mediaAnnotation.audioTranscribe.engine.labels
class _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get whisper => 'Whisper';
  String get multimodalLlm => 'Multimodal LLM';
  String get auto => 'Auto';
}

// Path: settings.mediaAnnotation.audioTranscribe.engine.descriptions
class _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsEn._(
      this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get whisper =>
      'Stable default for speech transcription. (Recommended)';
  String get multimodalLlm => 'Use a multimodal chat model when available.';
  String get auto => 'Let SecondLoop choose the best available engine.';
}

// Path: settings.cloudAccount.benefits.items.purchase
class _StringsSettingsCloudAccountBenefitsItemsPurchaseEn {
  _StringsSettingsCloudAccountBenefitsItemsPurchaseEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Subscribe to SecondLoop Pro';
  String get body => 'A cloud account is required to purchase a subscription.';
}

// Path: settings.subscription.benefits.items.noSetup
class _StringsSettingsSubscriptionBenefitsItemsNoSetupEn {
  _StringsSettingsSubscriptionBenefitsItemsNoSetupEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'AI without setup';
  String get body => 'No setup. Subscribe and start using built-in AI.';
}

// Path: settings.subscription.benefits.items.cloudSync
class _StringsSettingsSubscriptionBenefitsItemsCloudSyncEn {
  _StringsSettingsSubscriptionBenefitsItemsCloudSyncEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Cloud storage + sync';
  String get body => 'Your data stays in sync across devices.';
}

// Path: settings.subscription.benefits.items.mobileSearch
class _StringsSettingsSubscriptionBenefitsItemsMobileSearchEn {
  _StringsSettingsSubscriptionBenefitsItemsMobileSearchEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Smarter search on mobile';
  String get body => 'Find things even if you remember different words.';
}

// Path: <root>
class _StringsZhCn extends Translations {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  _StringsZhCn.build(
      {Map<String, Node>? overrides,
      PluralResolver? cardinalResolver,
      PluralResolver? ordinalResolver})
      : assert(overrides == null,
            'Set "translation_overrides: true" in order to enable this feature.'),
        $meta = TranslationMetadata(
          locale: AppLocale.zhCn,
          overrides: overrides ?? {},
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        ),
        super.build(
            cardinalResolver: cardinalResolver,
            ordinalResolver: ordinalResolver) {
    super.$meta.setFlatMapFunction(
        $meta.getTranslation); // copy base translations to super.$meta
    $meta.setFlatMapFunction(_flatMapFunction);
  }

  /// Metadata for the translations of <zh-CN>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  /// Access flat map
  @override
  dynamic operator [](String key) =>
      $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

  @override
  late final _StringsZhCn _root = this; // ignore: unused_field

  // Translations
  @override
  late final _StringsAppZhCn app = _StringsAppZhCn._(_root);
  @override
  late final _StringsCommonZhCn common = _StringsCommonZhCn._(_root);
  @override
  late final _StringsErrorsZhCn errors = _StringsErrorsZhCn._(_root);
  @override
  late final _StringsActionsZhCn actions = _StringsActionsZhCn._(_root);
  @override
  late final _StringsSettingsZhCn settings = _StringsSettingsZhCn._(_root);
  @override
  late final _StringsLockZhCn lock = _StringsLockZhCn._(_root);
  @override
  late final _StringsChatZhCn chat = _StringsChatZhCn._(_root);
  @override
  late final _StringsAttachmentsZhCn attachments =
      _StringsAttachmentsZhCn._(_root);
  @override
  late final _StringsSemanticSearchZhCn semanticSearch =
      _StringsSemanticSearchZhCn._(_root);
  @override
  late final _StringsSemanticSearchDebugZhCn semanticSearchDebug =
      _StringsSemanticSearchDebugZhCn._(_root);
  @override
  late final _StringsSyncZhCn sync = _StringsSyncZhCn._(_root);
  @override
  late final _StringsLlmProfilesZhCn llmProfiles =
      _StringsLlmProfilesZhCn._(_root);
  @override
  late final _StringsEmbeddingProfilesZhCn embeddingProfiles =
      _StringsEmbeddingProfilesZhCn._(_root);
  @override
  late final _StringsInboxZhCn inbox = _StringsInboxZhCn._(_root);
}

// Path: app
class _StringsAppZhCn extends _StringsAppEn {
  _StringsAppZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'SecondLoop';
  @override
  late final _StringsAppTabsZhCn tabs = _StringsAppTabsZhCn._(_root);
}

// Path: common
class _StringsCommonZhCn extends _StringsCommonEn {
  _StringsCommonZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsCommonActionsZhCn actions =
      _StringsCommonActionsZhCn._(_root);
  @override
  late final _StringsCommonFieldsZhCn fields =
      _StringsCommonFieldsZhCn._(_root);
  @override
  late final _StringsCommonLabelsZhCn labels =
      _StringsCommonLabelsZhCn._(_root);
}

// Path: errors
class _StringsErrorsZhCn extends _StringsErrorsEn {
  _StringsErrorsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String initFailed({required Object error}) => '初始化失败：${error}';
  @override
  String loadFailed({required Object error}) => '加载失败：${error}';
  @override
  String saveFailed({required Object error}) => '保存失败：${error}';
  @override
  String lockGateError({required Object error}) => '锁定流程错误：${error}';
  @override
  String get missingMainStream => '缺少主线对话';
}

// Path: actions
class _StringsActionsZhCn extends _StringsActionsEn {
  _StringsActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsActionsCaptureZhCn capture =
      _StringsActionsCaptureZhCn._(_root);
  @override
  late final _StringsActionsReviewQueueZhCn reviewQueue =
      _StringsActionsReviewQueueZhCn._(_root);
  @override
  late final _StringsActionsTodoStatusZhCn todoStatus =
      _StringsActionsTodoStatusZhCn._(_root);
  @override
  late final _StringsActionsTodoLinkZhCn todoLink =
      _StringsActionsTodoLinkZhCn._(_root);
  @override
  late final _StringsActionsTodoNoteLinkZhCn todoNoteLink =
      _StringsActionsTodoNoteLinkZhCn._(_root);
  @override
  late final _StringsActionsTodoAutoZhCn todoAuto =
      _StringsActionsTodoAutoZhCn._(_root);
  @override
  late final _StringsActionsTodoDetailZhCn todoDetail =
      _StringsActionsTodoDetailZhCn._(_root);
  @override
  late final _StringsActionsTodoDeleteZhCn todoDelete =
      _StringsActionsTodoDeleteZhCn._(_root);
  @override
  late final _StringsActionsTodoRecurrenceEditScopeZhCn
      todoRecurrenceEditScope =
      _StringsActionsTodoRecurrenceEditScopeZhCn._(_root);
  @override
  late final _StringsActionsTodoRecurrenceRuleZhCn todoRecurrenceRule =
      _StringsActionsTodoRecurrenceRuleZhCn._(_root);
  @override
  late final _StringsActionsHistoryZhCn history =
      _StringsActionsHistoryZhCn._(_root);
  @override
  late final _StringsActionsAgendaZhCn agenda =
      _StringsActionsAgendaZhCn._(_root);
  @override
  late final _StringsActionsCalendarZhCn calendar =
      _StringsActionsCalendarZhCn._(_root);
}

// Path: settings
class _StringsSettingsZhCn extends _StringsSettingsEn {
  _StringsSettingsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '设置';
  @override
  late final _StringsSettingsSectionsZhCn sections =
      _StringsSettingsSectionsZhCn._(_root);
  @override
  late final _StringsSettingsActionsReviewZhCn actionsReview =
      _StringsSettingsActionsReviewZhCn._(_root);
  @override
  late final _StringsSettingsQuickCaptureHotkeyZhCn quickCaptureHotkey =
      _StringsSettingsQuickCaptureHotkeyZhCn._(_root);
  @override
  late final _StringsSettingsDesktopBootZhCn desktopBoot =
      _StringsSettingsDesktopBootZhCn._(_root);
  @override
  late final _StringsSettingsDesktopTrayZhCn desktopTray =
      _StringsSettingsDesktopTrayZhCn._(_root);
  @override
  late final _StringsSettingsLanguageZhCn language =
      _StringsSettingsLanguageZhCn._(_root);
  @override
  late final _StringsSettingsThemeZhCn theme =
      _StringsSettingsThemeZhCn._(_root);
  @override
  late final _StringsSettingsAutoLockZhCn autoLock =
      _StringsSettingsAutoLockZhCn._(_root);
  @override
  late final _StringsSettingsSystemUnlockZhCn systemUnlock =
      _StringsSettingsSystemUnlockZhCn._(_root);
  @override
  late final _StringsSettingsLockNowZhCn lockNow =
      _StringsSettingsLockNowZhCn._(_root);
  @override
  late final _StringsSettingsLlmProfilesZhCn llmProfiles =
      _StringsSettingsLlmProfilesZhCn._(_root);
  @override
  late final _StringsSettingsEmbeddingProfilesZhCn embeddingProfiles =
      _StringsSettingsEmbeddingProfilesZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionZhCn aiSelection =
      _StringsSettingsAiSelectionZhCn._(_root);
  @override
  late final _StringsSettingsSemanticParseAutoActionsZhCn
      semanticParseAutoActions =
      _StringsSettingsSemanticParseAutoActionsZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationZhCn mediaAnnotation =
      _StringsSettingsMediaAnnotationZhCn._(_root);
  @override
  late final _StringsSettingsCloudEmbeddingsZhCn cloudEmbeddings =
      _StringsSettingsCloudEmbeddingsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountZhCn cloudAccount =
      _StringsSettingsCloudAccountZhCn._(_root);
  @override
  late final _StringsSettingsCloudUsageZhCn cloudUsage =
      _StringsSettingsCloudUsageZhCn._(_root);
  @override
  late final _StringsSettingsVaultUsageZhCn vaultUsage =
      _StringsSettingsVaultUsageZhCn._(_root);
  @override
  late final _StringsSettingsDiagnosticsZhCn diagnostics =
      _StringsSettingsDiagnosticsZhCn._(_root);
  @override
  late final _StringsSettingsByokUsageZhCn byokUsage =
      _StringsSettingsByokUsageZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionZhCn subscription =
      _StringsSettingsSubscriptionZhCn._(_root);
  @override
  late final _StringsSettingsSyncZhCn sync = _StringsSettingsSyncZhCn._(_root);
  @override
  late final _StringsSettingsResetLocalDataThisDeviceOnlyZhCn
      resetLocalDataThisDeviceOnly =
      _StringsSettingsResetLocalDataThisDeviceOnlyZhCn._(_root);
  @override
  late final _StringsSettingsResetLocalDataAllDevicesZhCn
      resetLocalDataAllDevices =
      _StringsSettingsResetLocalDataAllDevicesZhCn._(_root);
  @override
  late final _StringsSettingsDebugResetLocalDataThisDeviceOnlyZhCn
      debugResetLocalDataThisDeviceOnly =
      _StringsSettingsDebugResetLocalDataThisDeviceOnlyZhCn._(_root);
  @override
  late final _StringsSettingsDebugResetLocalDataAllDevicesZhCn
      debugResetLocalDataAllDevices =
      _StringsSettingsDebugResetLocalDataAllDevicesZhCn._(_root);
  @override
  late final _StringsSettingsDebugSemanticSearchZhCn debugSemanticSearch =
      _StringsSettingsDebugSemanticSearchZhCn._(_root);
}

// Path: lock
class _StringsLockZhCn extends _StringsLockEn {
  _StringsLockZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get masterPasswordRequired => '需要主密码';
  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致';
  @override
  String get setupTitle => '设置主密码';
  @override
  String get unlockTitle => '解锁';
  @override
  String get unlockReason => '解锁 SecondLoop';
  @override
  String get missingSavedSessionKey => '缺少已保存的会话密钥。请先用主密码解锁一次。';
  @override
  String get creating => '正在创建…';
  @override
  String get unlocking => '正在解锁…';
}

// Path: chat
class _StringsChatZhCn extends _StringsChatEn {
  _StringsChatZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get mainStreamTitle => '主线';
  @override
  String get attachTooltip => '添加附件';
  @override
  String get attachPickMedia => '选择媒体文件';
  @override
  String get attachTakePhoto => '拍照';
  @override
  String get attachRecordAudio => '录音';
  @override
  String get switchToVoiceInput => '切换到语音输入';
  @override
  String get switchToKeyboardInput => '切换到键盘输入';
  @override
  String get holdToTalk => '按住说话';
  @override
  String get releaseToConvert => '松开后转为文字';
  @override
  String get recordingInProgress => '正在录音…';
  @override
  String get recordingHint => '点击停止发送音频，或点击取消放弃。';
  @override
  String get cameraTooltip => '拍照';
  @override
  String get photoMessage => '照片';
  @override
  String get editMessageTitle => '编辑消息';
  @override
  String get messageUpdated => '消息已更新';
  @override
  String get messageDeleted => '消息已删除';
  @override
  late final _StringsChatDeleteMessageDialogZhCn deleteMessageDialog =
      _StringsChatDeleteMessageDialogZhCn._(_root);
  @override
  String photoFailed({required Object error}) => '拍照失败：${error}';
  @override
  String get audioRecordPermissionDenied => '需要麦克风权限才能录音。';
  @override
  String audioRecordFailed({required Object error}) => '录音失败：${error}';
  @override
  String editFailed({required Object error}) => '编辑失败：${error}';
  @override
  String deleteFailed({required Object error}) => '删除失败：${error}';
  @override
  String get noMessagesYet => '暂无消息';
  @override
  String get viewFull => '查看全文';
  @override
  late final _StringsChatMessageActionsZhCn messageActions =
      _StringsChatMessageActionsZhCn._(_root);
  @override
  late final _StringsChatMessageViewerZhCn messageViewer =
      _StringsChatMessageViewerZhCn._(_root);
  @override
  late final _StringsChatMarkdownEditorZhCn markdownEditor =
      _StringsChatMarkdownEditorZhCn._(_root);
  @override
  late final _StringsChatFocusZhCn focus = _StringsChatFocusZhCn._(_root);
  @override
  late final _StringsChatAskAiSetupZhCn askAiSetup =
      _StringsChatAskAiSetupZhCn._(_root);
  @override
  late final _StringsChatCloudGatewayZhCn cloudGateway =
      _StringsChatCloudGatewayZhCn._(_root);
  @override
  String get askAiFailedTemporary => 'AI 对话失败了，请重试。';
  @override
  late final _StringsChatAskAiConsentZhCn askAiConsent =
      _StringsChatAskAiConsentZhCn._(_root);
  @override
  late final _StringsChatEmbeddingsConsentZhCn embeddingsConsent =
      _StringsChatEmbeddingsConsentZhCn._(_root);
  @override
  String get semanticParseStatusRunning => 'AI 分析中…';
  @override
  String get semanticParseStatusSlow => 'AI 分析较慢，后台继续…';
  @override
  String get attachmentAnnotationNeedsSetup => '图片注释需要先配置';
  @override
  String get semanticParseStatusFailed => 'AI 分析失败';
  @override
  String get semanticParseStatusCanceled => '已取消 AI 分析';
  @override
  String semanticParseStatusCreated({required Object title}) =>
      '已创建待办：${title}';
  @override
  String semanticParseStatusUpdated({required Object title}) =>
      '已更新待办：${title}';
  @override
  String get semanticParseStatusUpdatedGeneric => '已更新待办';
  @override
  String get semanticParseStatusUndone => '已撤销自动动作';
  @override
  String get askAiRecoveredDetached => '已恢复已完成的云端回答。';
  @override
  late final _StringsChatTopicThreadZhCn topicThread =
      _StringsChatTopicThreadZhCn._(_root);
  @override
  late final _StringsChatTagFilterZhCn tagFilter =
      _StringsChatTagFilterZhCn._(_root);
  @override
  late final _StringsChatTagPickerZhCn tagPicker =
      _StringsChatTagPickerZhCn._(_root);
  @override
  late final _StringsChatAskScopeEmptyZhCn askScopeEmpty =
      _StringsChatAskScopeEmptyZhCn._(_root);
}

// Path: attachments
class _StringsAttachmentsZhCn extends _StringsAttachmentsEn {
  _StringsAttachmentsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsAttachmentsMetadataZhCn metadata =
      _StringsAttachmentsMetadataZhCn._(_root);
  @override
  late final _StringsAttachmentsUrlZhCn url =
      _StringsAttachmentsUrlZhCn._(_root);
  @override
  late final _StringsAttachmentsContentZhCn content =
      _StringsAttachmentsContentZhCn._(_root);
}

// Path: semanticSearch
class _StringsSemanticSearchZhCn extends _StringsSemanticSearchEn {
  _StringsSemanticSearchZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => '正在准备语义检索…';
  @override
  String indexingMessages({required Object count}) => '正在索引消息…（已索引 ${count} 条）';
}

// Path: semanticSearchDebug
class _StringsSemanticSearchDebugZhCn extends _StringsSemanticSearchDebugEn {
  _StringsSemanticSearchDebugZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '语义检索（调试）';
  @override
  String get embeddingModelLoading => '向量模型：（加载中…）';
  @override
  String embeddingModel({required Object model}) => '向量模型：${model}';
  @override
  String get switchedModelReindex => '已切换向量模型；待重新索引';
  @override
  String get modelAlreadyActive => '向量模型已处于激活状态';
  @override
  String processedPending({required Object count}) => '已处理 ${count} 条待处理向量';
  @override
  String rebuilt({required Object count}) => '已为 ${count} 条消息重建向量';
  @override
  String get runSearchToSeeResults => '运行一次搜索以查看结果';
  @override
  String get noResults => '没有结果';
  @override
  String resultSubtitle(
          {required Object distance,
          required Object role,
          required Object conversationId}) =>
      'distance=${distance} • role=${role} • convo=${conversationId}';
}

// Path: sync
class _StringsSyncZhCn extends _StringsSyncEn {
  _StringsSyncZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '同步设置';
  @override
  late final _StringsSyncProgressDialogZhCn progressDialog =
      _StringsSyncProgressDialogZhCn._(_root);
  @override
  late final _StringsSyncSectionsZhCn sections =
      _StringsSyncSectionsZhCn._(_root);
  @override
  late final _StringsSyncAutoSyncZhCn autoSync =
      _StringsSyncAutoSyncZhCn._(_root);
  @override
  late final _StringsSyncMediaPreviewZhCn mediaPreview =
      _StringsSyncMediaPreviewZhCn._(_root);
  @override
  late final _StringsSyncMediaBackupZhCn mediaBackup =
      _StringsSyncMediaBackupZhCn._(_root);
  @override
  late final _StringsSyncLocalCacheZhCn localCache =
      _StringsSyncLocalCacheZhCn._(_root);
  @override
  String get backendLabel => '同步方式';
  @override
  String get backendWebdav => 'WebDAV（你自己的服务器）';
  @override
  String get backendLocalDir => '本机文件夹（桌面端）';
  @override
  String get backendManagedVault => 'SecondLoop Cloud';
  @override
  late final _StringsSyncCloudManagedVaultZhCn cloudManagedVault =
      _StringsSyncCloudManagedVaultZhCn._(_root);
  @override
  String get remoteRootRequired => '必须填写文件夹名称';
  @override
  String get baseUrlRequired => '必须填写服务器地址';
  @override
  String get localDirRequired => '必须填写文件夹路径';
  @override
  String get connectionOk => '连接成功';
  @override
  String connectionFailed({required Object error}) => '连接失败：${error}';
  @override
  String saveFailed({required Object error}) => '保存失败：${error}';
  @override
  String get missingSyncKey => '缺少同步口令。请先输入口令并点击保存。';
  @override
  String pushedOps({required Object count}) => '已上传 ${count} 个更改';
  @override
  String pulledOps({required Object count}) => '已下载 ${count} 个更改';
  @override
  String get noNewChanges => '已是最新';
  @override
  String pushFailed({required Object error}) => '上传失败：${error}';
  @override
  String pullFailed({required Object error}) => '下载失败：${error}';
  @override
  late final _StringsSyncFieldsZhCn fields = _StringsSyncFieldsZhCn._(_root);
}

// Path: llmProfiles
class _StringsLlmProfilesZhCn extends _StringsLlmProfilesEn {
  _StringsLlmProfilesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'AI 配置';
  @override
  String get refreshTooltip => '刷新';
  @override
  String get activeProfileHelp => '当前选择的配置会作为通用 LLM API 配置，被多项智能能力复用。';
  @override
  String get noProfilesYet => '暂无配置。';
  @override
  String get addProfile => '添加配置';
  @override
  String get deleted => '配置已删除';
  @override
  String get validationError => '名称、API Key 和模型名称为必填项。';
  @override
  late final _StringsLlmProfilesDeleteDialogZhCn deleteDialog =
      _StringsLlmProfilesDeleteDialogZhCn._(_root);
  @override
  late final _StringsLlmProfilesFieldsZhCn fields =
      _StringsLlmProfilesFieldsZhCn._(_root);
  @override
  late final _StringsLlmProfilesProvidersZhCn providers =
      _StringsLlmProfilesProvidersZhCn._(_root);
  @override
  String get savedActivated => '已保存并设为当前配置';
  @override
  late final _StringsLlmProfilesActionsZhCn actions =
      _StringsLlmProfilesActionsZhCn._(_root);
}

// Path: embeddingProfiles
class _StringsEmbeddingProfilesZhCn extends _StringsEmbeddingProfilesEn {
  _StringsEmbeddingProfilesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '向量配置';
  @override
  String get refreshTooltip => '刷新';
  @override
  String get activeProfileHelp => '当前选择的配置将用于 embeddings（语义检索 / RAG）。';
  @override
  String get noProfilesYet => '暂无配置。';
  @override
  String get addProfile => '添加配置';
  @override
  String get deleted => '向量配置已删除';
  @override
  String get validationError => '名称、API Key 和模型名称为必填项。';
  @override
  late final _StringsEmbeddingProfilesReindexDialogZhCn reindexDialog =
      _StringsEmbeddingProfilesReindexDialogZhCn._(_root);
  @override
  late final _StringsEmbeddingProfilesDeleteDialogZhCn deleteDialog =
      _StringsEmbeddingProfilesDeleteDialogZhCn._(_root);
  @override
  late final _StringsEmbeddingProfilesFieldsZhCn fields =
      _StringsEmbeddingProfilesFieldsZhCn._(_root);
  @override
  late final _StringsEmbeddingProfilesProvidersZhCn providers =
      _StringsEmbeddingProfilesProvidersZhCn._(_root);
  @override
  String get savedActivated => '已保存并设为当前配置';
  @override
  late final _StringsEmbeddingProfilesActionsZhCn actions =
      _StringsEmbeddingProfilesActionsZhCn._(_root);
}

// Path: inbox
class _StringsInboxZhCn extends _StringsInboxEn {
  _StringsInboxZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get defaultTitle => '收件箱';
  @override
  String get noConversationsYet => '暂无会话';
}

// Path: app.tabs
class _StringsAppTabsZhCn extends _StringsAppTabsEn {
  _StringsAppTabsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get main => '主线';
  @override
  String get settings => '设置';
}

// Path: common.actions
class _StringsCommonActionsZhCn extends _StringsCommonActionsEn {
  _StringsCommonActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get cancel => '取消';
  @override
  String get notNow => '暂不';
  @override
  String get allow => '允许';
  @override
  String get save => '保存';
  @override
  String get copy => '复制';
  @override
  String get reset => '重置';
  @override
  String get continueLabel => '继续';
  @override
  String get send => '发送';
  @override
  String get askAi => 'AI 对话';
  @override
  String get configureAi => '配置 AI';
  @override
  String get stop => '停止';
  @override
  String get stopping => '正在停止…';
  @override
  String get edit => '编辑';
  @override
  String get delete => '删除';
  @override
  String get undo => '撤销';
  @override
  String get open => '打开';
  @override
  String get retry => '重试';
  @override
  String get ignore => '忽略';
  @override
  String get refresh => '刷新';
  @override
  String get share => '分享';
  @override
  String get search => '搜索';
  @override
  String get useModel => '使用模型';
  @override
  String get processPending => '处理待处理';
  @override
  String get rebuildEmbeddings => '重建向量索引';
  @override
  String get push => '上传';
  @override
  String get pull => '下载';
  @override
  String get lockNow => '立即锁定';
}

// Path: common.fields
class _StringsCommonFieldsZhCn extends _StringsCommonFieldsEn {
  _StringsCommonFieldsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get masterPassword => '主密码';
  @override
  String get confirm => '确认';
  @override
  String get message => '消息';
  @override
  String get quickCapture => '快速记录';
  @override
  String get query => '查询';
}

// Path: common.labels
class _StringsCommonLabelsZhCn extends _StringsCommonLabelsEn {
  _StringsCommonLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String elapsedSeconds({required Object seconds}) => '耗时：${seconds}s';
  @override
  String get topK => 'Top‑K：';
}

// Path: actions.capture
class _StringsActionsCaptureZhCn extends _StringsActionsCaptureEn {
  _StringsActionsCaptureZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '要把它变成提醒吗？';
  @override
  String get pickTime => '选择时间';
  @override
  String get reviewLater => '先放着，之后提醒我确认';
  @override
  String get justSave => '只保存为记录';
}

// Path: actions.reviewQueue
class _StringsActionsReviewQueueZhCn extends _StringsActionsReviewQueueEn {
  _StringsActionsReviewQueueZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '待确认';
  @override
  String banner({required Object count}) => '有 ${count} 条待确认事项';
  @override
  String get empty => '没有需要确认的事项';
  @override
  String snoozedUntil({required Object when}) => '已延期到 ${when}';
  @override
  late final _StringsActionsReviewQueueInAppFallbackZhCn inAppFallback =
      _StringsActionsReviewQueueInAppFallbackZhCn._(_root);
  @override
  late final _StringsActionsReviewQueueActionsZhCn actions =
      _StringsActionsReviewQueueActionsZhCn._(_root);
}

// Path: actions.todoStatus
class _StringsActionsTodoStatusZhCn extends _StringsActionsTodoStatusEn {
  _StringsActionsTodoStatusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get inbox => '待确认';
  @override
  String get open => '未开始';
  @override
  String get inProgress => '进行中';
  @override
  String get done => '已完成';
  @override
  String get dismissed => '已删除';
}

// Path: actions.todoLink
class _StringsActionsTodoLinkZhCn extends _StringsActionsTodoLinkEn {
  _StringsActionsTodoLinkZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '要更新哪个待办？';
  @override
  String subtitle({required Object status}) => '默认标记为：${status}';
  @override
  String updated({required Object title, required Object status}) =>
      '已更新「${title}」为：${status}';
}

// Path: actions.todoNoteLink
class _StringsActionsTodoNoteLinkZhCn extends _StringsActionsTodoNoteLinkEn {
  _StringsActionsTodoNoteLinkZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get action => '关联到待办';
  @override
  String get actionShort => '关联';
  @override
  String get title => '要关联到哪个待办？';
  @override
  String get subtitle => '将这条消息作为跟进记录添加';
  @override
  String get noMatches => '没有匹配的待办';
  @override
  String get suggest => '要把这条消息关联到待办吗？';
  @override
  String linked({required Object title}) => '已关联到「${title}」';
}

// Path: actions.todoAuto
class _StringsActionsTodoAutoZhCn extends _StringsActionsTodoAutoEn {
  _StringsActionsTodoAutoZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String created({required Object title}) => '已创建「${title}」';
}

// Path: actions.todoDetail
class _StringsActionsTodoDetailZhCn extends _StringsActionsTodoDetailEn {
  _StringsActionsTodoDetailZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '待办详情';
  @override
  String get emptyTimeline => '暂无跟进记录';
  @override
  String get noteHint => '补充跟进…';
  @override
  String get addNote => '添加';
  @override
  String get attach => '添加附件';
  @override
  String get pickAttachment => '选择附件';
  @override
  String get noAttachments => '暂无附件';
  @override
  String get attachmentNoteDefault => '添加了附件';
}

// Path: actions.todoDelete
class _StringsActionsTodoDeleteZhCn extends _StringsActionsTodoDeleteEn {
  _StringsActionsTodoDeleteZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsActionsTodoDeleteDialogZhCn dialog =
      _StringsActionsTodoDeleteDialogZhCn._(_root);
}

// Path: actions.todoRecurrenceEditScope
class _StringsActionsTodoRecurrenceEditScopeZhCn
    extends _StringsActionsTodoRecurrenceEditScopeEn {
  _StringsActionsTodoRecurrenceEditScopeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '重复任务如何应用修改';
  @override
  String get message => '这次更改要如何应用？';
  @override
  String get thisOnly => '仅本次';
  @override
  String get thisAndFuture => '本次及以后';
  @override
  String get wholeSeries => '整个系列';
}

// Path: actions.todoRecurrenceRule
class _StringsActionsTodoRecurrenceRuleZhCn
    extends _StringsActionsTodoRecurrenceRuleEn {
  _StringsActionsTodoRecurrenceRuleZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '编辑重复规则';
  @override
  String get edit => '重复';
  @override
  String get frequencyLabel => '频率';
  @override
  String get intervalLabel => '间隔';
  @override
  String get daily => '每天';
  @override
  String get weekly => '每周';
  @override
  String get monthly => '每月';
  @override
  String get yearly => '每年';
}

// Path: actions.history
class _StringsActionsHistoryZhCn extends _StringsActionsHistoryEn {
  _StringsActionsHistoryZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '回溯';
  @override
  String get empty => '该时间范围内没有记录';
  @override
  late final _StringsActionsHistoryPresetsZhCn presets =
      _StringsActionsHistoryPresetsZhCn._(_root);
  @override
  late final _StringsActionsHistoryActionsZhCn actions =
      _StringsActionsHistoryActionsZhCn._(_root);
  @override
  late final _StringsActionsHistorySectionsZhCn sections =
      _StringsActionsHistorySectionsZhCn._(_root);
}

// Path: actions.agenda
class _StringsActionsAgendaZhCn extends _StringsActionsAgendaEn {
  _StringsActionsAgendaZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '待办';
  @override
  String summary({required Object due, required Object overdue}) =>
      '今天 ${due} 条 · 逾期 ${overdue} 条';
  @override
  String upcomingSummary({required Object count}) => '接下来 ${count} 条';
  @override
  String get viewAll => '查看全部';
  @override
  String get empty => '暂无待办';
}

// Path: actions.calendar
class _StringsActionsCalendarZhCn extends _StringsActionsCalendarEn {
  _StringsActionsCalendarZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '添加到日历？';
  @override
  String get pickTime => '选择开始时间';
  @override
  String get noAutoTime => '未找到可自动解析的时间';
  @override
  String get pickCustom => '选择日期时间';
}

// Path: settings.sections
class _StringsSettingsSectionsZhCn extends _StringsSettingsSectionsEn {
  _StringsSettingsSectionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get appearance => '外观';
  @override
  String get security => '安全';
  @override
  String get cloud => 'SecondLoop Cloud';
  @override
  String get aiAdvanced => '高级（自带 API Key）';
  @override
  String get storage => '同步与存储';
  @override
  String get actions => '行动';
  @override
  String get support => '帮助与支持';
  @override
  String get debug => '调试';
}

// Path: settings.actionsReview
class _StringsSettingsActionsReviewZhCn
    extends _StringsSettingsActionsReviewEn {
  _StringsSettingsActionsReviewZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsActionsReviewMorningTimeZhCn morningTime =
      _StringsSettingsActionsReviewMorningTimeZhCn._(_root);
  @override
  late final _StringsSettingsActionsReviewDayEndTimeZhCn dayEndTime =
      _StringsSettingsActionsReviewDayEndTimeZhCn._(_root);
  @override
  late final _StringsSettingsActionsReviewWeeklyTimeZhCn weeklyTime =
      _StringsSettingsActionsReviewWeeklyTimeZhCn._(_root);
  @override
  late final _StringsSettingsActionsReviewInAppFallbackZhCn inAppFallback =
      _StringsSettingsActionsReviewInAppFallbackZhCn._(_root);
}

// Path: settings.quickCaptureHotkey
class _StringsSettingsQuickCaptureHotkeyZhCn
    extends _StringsSettingsQuickCaptureHotkeyEn {
  _StringsSettingsQuickCaptureHotkeyZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '快速记录快捷键';
  @override
  String get subtitle => '用于从任何地方打开快速记录';
  @override
  String get dialogTitle => '快速记录快捷键';
  @override
  String get dialogBody => '按下新的按键组合来录制快捷键。';
  @override
  String get saved => '快速记录快捷键已更新';
  @override
  late final _StringsSettingsQuickCaptureHotkeyActionsZhCn actions =
      _StringsSettingsQuickCaptureHotkeyActionsZhCn._(_root);
  @override
  late final _StringsSettingsQuickCaptureHotkeyValidationZhCn validation =
      _StringsSettingsQuickCaptureHotkeyValidationZhCn._(_root);
  @override
  late final _StringsSettingsQuickCaptureHotkeyConflictsZhCn conflicts =
      _StringsSettingsQuickCaptureHotkeyConflictsZhCn._(_root);
}

// Path: settings.desktopBoot
class _StringsSettingsDesktopBootZhCn extends _StringsSettingsDesktopBootEn {
  _StringsSettingsDesktopBootZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsDesktopBootStartWithSystemZhCn startWithSystem =
      _StringsSettingsDesktopBootStartWithSystemZhCn._(_root);
  @override
  late final _StringsSettingsDesktopBootSilentStartupZhCn silentStartup =
      _StringsSettingsDesktopBootSilentStartupZhCn._(_root);
  @override
  late final _StringsSettingsDesktopBootKeepRunningInBackgroundZhCn
      keepRunningInBackground =
      _StringsSettingsDesktopBootKeepRunningInBackgroundZhCn._(_root);
}

// Path: settings.desktopTray
class _StringsSettingsDesktopTrayZhCn extends _StringsSettingsDesktopTrayEn {
  _StringsSettingsDesktopTrayZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsDesktopTrayMenuZhCn menu =
      _StringsSettingsDesktopTrayMenuZhCn._(_root);
  @override
  late final _StringsSettingsDesktopTrayProZhCn pro =
      _StringsSettingsDesktopTrayProZhCn._(_root);
}

// Path: settings.language
class _StringsSettingsLanguageZhCn extends _StringsSettingsLanguageEn {
  _StringsSettingsLanguageZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '语言';
  @override
  String get subtitle => '跟随系统或手动选择语言';
  @override
  String get dialogTitle => '语言';
  @override
  late final _StringsSettingsLanguageOptionsZhCn options =
      _StringsSettingsLanguageOptionsZhCn._(_root);
}

// Path: settings.theme
class _StringsSettingsThemeZhCn extends _StringsSettingsThemeEn {
  _StringsSettingsThemeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '主题';
  @override
  String get subtitle => '跟随系统，或选择明亮/深色';
  @override
  String get dialogTitle => '主题';
  @override
  late final _StringsSettingsThemeOptionsZhCn options =
      _StringsSettingsThemeOptionsZhCn._(_root);
}

// Path: settings.autoLock
class _StringsSettingsAutoLockZhCn extends _StringsSettingsAutoLockEn {
  _StringsSettingsAutoLockZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '自动锁定';
  @override
  String get subtitle => '需要解锁才能访问应用';
}

// Path: settings.systemUnlock
class _StringsSettingsSystemUnlockZhCn extends _StringsSettingsSystemUnlockEn {
  _StringsSettingsSystemUnlockZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get titleMobile => '使用生物识别';
  @override
  String get titleDesktop => '使用系统解锁';
  @override
  String get subtitleMobile => '使用生物识别解锁，而不是主密码';
  @override
  String get subtitleDesktop => '使用 Touch ID / Windows Hello 解锁，而不是主密码';
}

// Path: settings.lockNow
class _StringsSettingsLockNowZhCn extends _StringsSettingsLockNowEn {
  _StringsSettingsLockNowZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '立即锁定';
  @override
  String get subtitle => '返回解锁页面';
}

// Path: settings.llmProfiles
class _StringsSettingsLlmProfilesZhCn extends _StringsSettingsLlmProfilesEn {
  _StringsSettingsLlmProfilesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API Key（AI 对话）';
  @override
  String get subtitle => '高级：使用你自己的服务商与 Key';
}

// Path: settings.embeddingProfiles
class _StringsSettingsEmbeddingProfilesZhCn
    extends _StringsSettingsEmbeddingProfilesEn {
  _StringsSettingsEmbeddingProfilesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API Key（语义搜索）';
  @override
  String get subtitle => '高级：使用你自己的服务商与 Key';
}

// Path: settings.aiSelection
class _StringsSettingsAiSelectionZhCn extends _StringsSettingsAiSelectionEn {
  _StringsSettingsAiSelectionZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '智能化';
  @override
  String get subtitle => '统一设置 AI 问答、智能检索（Embedding）、图片读字（OCR）和语音转文字。';
  @override
  late final _StringsSettingsAiSelectionAskAiZhCn askAi =
      _StringsSettingsAiSelectionAskAiZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionEmbeddingsZhCn embeddings =
      _StringsSettingsAiSelectionEmbeddingsZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingZhCn
      mediaUnderstanding =
      _StringsSettingsAiSelectionMediaUnderstandingZhCn._(_root);
}

// Path: settings.semanticParseAutoActions
class _StringsSettingsSemanticParseAutoActionsZhCn
    extends _StringsSettingsSemanticParseAutoActionsEn {
  _StringsSettingsSemanticParseAutoActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '更智能的语义分析';
  @override
  String get subtitleEnabled => '已开启增强模式。在本地语义分析基础上，会使用 Cloud/BYOK 提升自动整理准确度。';
  @override
  String get subtitleDisabled => '已关闭增强模式。仍会使用本地语义分析。';
  @override
  String get subtitleUnset => '尚未设置，默认关闭增强模式（仍会使用本地语义分析）。';
  @override
  String get subtitleRequiresSetup =>
      '需先登录 SecondLoop Pro 或配置 API 密钥（BYOK）后，才能开启增强模式。';
  @override
  String get dialogTitle => '开启更智能的语义分析？';
  @override
  String get dialogBody =>
      '本地语义分析始终开启。开启增强模式后，SecondLoop 会在本地分析基础上，将消息文本发送给 AI 做更智能的语义理解（Semantic Parse）。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这会消耗 Cloud 额度或你自己的服务商额度。';
  @override
  late final _StringsSettingsSemanticParseAutoActionsDialogActionsZhCn
      dialogActions =
      _StringsSettingsSemanticParseAutoActionsDialogActionsZhCn._(_root);
}

// Path: settings.mediaAnnotation
class _StringsSettingsMediaAnnotationZhCn
    extends _StringsSettingsMediaAnnotationEn {
  _StringsSettingsMediaAnnotationZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '媒体理解';
  @override
  String get subtitle => '可选：OCR、图片注释与音频转写，增强检索与存储体验';
  @override
  late final _StringsSettingsMediaAnnotationRoutingGuideZhCn routingGuide =
      _StringsSettingsMediaAnnotationRoutingGuideZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrZhCn documentOcr =
      _StringsSettingsMediaAnnotationDocumentOcrZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAudioTranscribeZhCn
      audioTranscribe =
      _StringsSettingsMediaAnnotationAudioTranscribeZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationImageCaptionZhCn imageCaption =
      _StringsSettingsMediaAnnotationImageCaptionZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationProviderSettingsZhCn
      providerSettings =
      _StringsSettingsMediaAnnotationProviderSettingsZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationSetupRequiredZhCn setupRequired =
      _StringsSettingsMediaAnnotationSetupRequiredZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAnnotateEnabledZhCn
      annotateEnabled =
      _StringsSettingsMediaAnnotationAnnotateEnabledZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationSearchEnabledZhCn searchEnabled =
      _StringsSettingsMediaAnnotationSearchEnabledZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationSearchToggleConfirmZhCn
      searchToggleConfirm =
      _StringsSettingsMediaAnnotationSearchToggleConfirmZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAdvancedZhCn advanced =
      _StringsSettingsMediaAnnotationAdvancedZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationProviderModeZhCn providerMode =
      _StringsSettingsMediaAnnotationProviderModeZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationCloudModelNameZhCn cloudModelName =
      _StringsSettingsMediaAnnotationCloudModelNameZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationByokProfileZhCn byokProfile =
      _StringsSettingsMediaAnnotationByokProfileZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAllowCellularZhCn allowCellular =
      _StringsSettingsMediaAnnotationAllowCellularZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAllowCellularConfirmZhCn
      allowCellularConfirm =
      _StringsSettingsMediaAnnotationAllowCellularConfirmZhCn._(_root);
}

// Path: settings.cloudEmbeddings
class _StringsSettingsCloudEmbeddingsZhCn
    extends _StringsSettingsCloudEmbeddingsEn {
  _StringsSettingsCloudEmbeddingsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '云端增强检索（Embedding）';
  @override
  String get subtitleEnabled => '已开启。在智能检索基础上，额外使用 Cloud 生成索引，搜索和回忆通常更准确。';
  @override
  String get subtitleDisabled => '已关闭。你仍可使用智能检索，但仅使用本机索引。';
  @override
  String get subtitleUnset => '尚未设置，首次需要云端增强时会询问你是否开启。';
  @override
  String get subtitleRequiresPro => '需要 SecondLoop Pro。';
  @override
  String get dialogTitle => '开启云端增强检索？';
  @override
  String get dialogBody =>
      '“智能检索”默认使用本机索引。开启后，SecondLoop 可以将少量文本（消息预览、待办标题、跟进）发送到 SecondLoop Cloud 生成更高质量的检索索引（Embedding），从而提高搜索和回忆准确度。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这会消耗 Cloud 额度。';
  @override
  late final _StringsSettingsCloudEmbeddingsDialogActionsZhCn dialogActions =
      _StringsSettingsCloudEmbeddingsDialogActionsZhCn._(_root);
}

// Path: settings.cloudAccount
class _StringsSettingsCloudAccountZhCn extends _StringsSettingsCloudAccountEn {
  _StringsSettingsCloudAccountZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cloud 账号';
  @override
  String get subtitle => '登录 SecondLoop Cloud';
  @override
  String signedInAs({required Object email}) => '已登录：${email}';
  @override
  late final _StringsSettingsCloudAccountBenefitsZhCn benefits =
      _StringsSettingsCloudAccountBenefitsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountErrorsZhCn errors =
      _StringsSettingsCloudAccountErrorsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountFieldsZhCn fields =
      _StringsSettingsCloudAccountFieldsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountActionsZhCn actions =
      _StringsSettingsCloudAccountActionsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountEmailVerificationZhCn
      emailVerification =
      _StringsSettingsCloudAccountEmailVerificationZhCn._(_root);
}

// Path: settings.cloudUsage
class _StringsSettingsCloudUsageZhCn extends _StringsSettingsCloudUsageEn {
  _StringsSettingsCloudUsageZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '云端用量';
  @override
  String get subtitle => '当前账期用量';
  @override
  late final _StringsSettingsCloudUsageActionsZhCn actions =
      _StringsSettingsCloudUsageActionsZhCn._(_root);
  @override
  late final _StringsSettingsCloudUsageLabelsZhCn labels =
      _StringsSettingsCloudUsageLabelsZhCn._(_root);
}

// Path: settings.vaultUsage
class _StringsSettingsVaultUsageZhCn extends _StringsSettingsVaultUsageEn {
  _StringsSettingsVaultUsageZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '云端存储';
  @override
  String get subtitle => '你的同步数据占用的云端存储';
  @override
  late final _StringsSettingsVaultUsageActionsZhCn actions =
      _StringsSettingsVaultUsageActionsZhCn._(_root);
  @override
  late final _StringsSettingsVaultUsageLabelsZhCn labels =
      _StringsSettingsVaultUsageLabelsZhCn._(_root);
}

// Path: settings.diagnostics
class _StringsSettingsDiagnosticsZhCn extends _StringsSettingsDiagnosticsEn {
  _StringsSettingsDiagnosticsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '诊断信息';
  @override
  String get subtitle => '导出诊断信息以便支持排查';
  @override
  String get privacyNote => '该报告不会包含你的记录正文或 API Key。';
  @override
  String get loading => '正在加载诊断信息…';
  @override
  late final _StringsSettingsDiagnosticsMessagesZhCn messages =
      _StringsSettingsDiagnosticsMessagesZhCn._(_root);
}

// Path: settings.byokUsage
class _StringsSettingsByokUsageZhCn extends _StringsSettingsByokUsageEn {
  _StringsSettingsByokUsageZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API Key 用量';
  @override
  String get subtitle => '当前配置 • 请求数与 Token（如可获取）';
  @override
  String get loading => '加载中…';
  @override
  String get noData => '暂无数据';
  @override
  late final _StringsSettingsByokUsageErrorsZhCn errors =
      _StringsSettingsByokUsageErrorsZhCn._(_root);
  @override
  late final _StringsSettingsByokUsageSectionsZhCn sections =
      _StringsSettingsByokUsageSectionsZhCn._(_root);
  @override
  late final _StringsSettingsByokUsageLabelsZhCn labels =
      _StringsSettingsByokUsageLabelsZhCn._(_root);
  @override
  late final _StringsSettingsByokUsagePurposesZhCn purposes =
      _StringsSettingsByokUsagePurposesZhCn._(_root);
}

// Path: settings.subscription
class _StringsSettingsSubscriptionZhCn extends _StringsSettingsSubscriptionEn {
  _StringsSettingsSubscriptionZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '订阅';
  @override
  String get subtitle => '管理 SecondLoop Pro';
  @override
  late final _StringsSettingsSubscriptionBenefitsZhCn benefits =
      _StringsSettingsSubscriptionBenefitsZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionStatusZhCn status =
      _StringsSettingsSubscriptionStatusZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionActionsZhCn actions =
      _StringsSettingsSubscriptionActionsZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionLabelsZhCn labels =
      _StringsSettingsSubscriptionLabelsZhCn._(_root);
}

// Path: settings.sync
class _StringsSettingsSyncZhCn extends _StringsSettingsSyncEn {
  _StringsSettingsSyncZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '同步';
  @override
  String get subtitle => '选择同步存储位置（SecondLoop Cloud / WebDAV 网盘 / 本地文件夹）';
}

// Path: settings.resetLocalDataThisDeviceOnly
class _StringsSettingsResetLocalDataThisDeviceOnlyZhCn
    extends _StringsSettingsResetLocalDataThisDeviceOnlyEn {
  _StringsSettingsResetLocalDataThisDeviceOnlyZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => '重置本地数据？';
  @override
  String get dialogBody =>
      '这将删除本地消息，并清空「当前设备」已同步的远端数据（不影响其他设备）。不会删除你的主密码或本地 AI/同步设置。你需要重新解锁。';
  @override
  String failed({required Object error}) => '重置失败：${error}';
}

// Path: settings.resetLocalDataAllDevices
class _StringsSettingsResetLocalDataAllDevicesZhCn
    extends _StringsSettingsResetLocalDataAllDevicesEn {
  _StringsSettingsResetLocalDataAllDevicesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => '重置本地数据？';
  @override
  String get dialogBody =>
      '这将删除本地消息，并清空「所有设备」已同步的远端数据。不会删除你的主密码或本地 AI/同步设置。你需要重新解锁。';
  @override
  String failed({required Object error}) => '重置失败：${error}';
}

// Path: settings.debugResetLocalDataThisDeviceOnly
class _StringsSettingsDebugResetLocalDataThisDeviceOnlyZhCn
    extends _StringsSettingsDebugResetLocalDataThisDeviceOnlyEn {
  _StringsSettingsDebugResetLocalDataThisDeviceOnlyZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '调试：重置本地数据（仅本设备）';
  @override
  String get subtitle => '删除本地消息 + 清空本设备远端数据（其他设备保留）';
}

// Path: settings.debugResetLocalDataAllDevices
class _StringsSettingsDebugResetLocalDataAllDevicesZhCn
    extends _StringsSettingsDebugResetLocalDataAllDevicesEn {
  _StringsSettingsDebugResetLocalDataAllDevicesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '调试：重置本地数据（所有设备）';
  @override
  String get subtitle => '删除本地消息 + 清空所有设备远端数据';
}

// Path: settings.debugSemanticSearch
class _StringsSettingsDebugSemanticSearchZhCn
    extends _StringsSettingsDebugSemanticSearchEn {
  _StringsSettingsDebugSemanticSearchZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '调试：语义检索';
  @override
  String get subtitle => '搜索相似消息 + 重建向量索引';
}

// Path: chat.deleteMessageDialog
class _StringsChatDeleteMessageDialogZhCn
    extends _StringsChatDeleteMessageDialogEn {
  _StringsChatDeleteMessageDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '删除信息？';
  @override
  String get message => '这将永久删除该信息及其附件。';
}

// Path: chat.messageActions
class _StringsChatMessageActionsZhCn extends _StringsChatMessageActionsEn {
  _StringsChatMessageActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get convertToTodo => '转化为待办项';
  @override
  String get convertTodoToInfo => '转为普通信息';
  @override
  String get convertTodoToInfoConfirmTitle => '转为普通信息？';
  @override
  String get convertTodoToInfoConfirmBody => '这会移除该事项，但保留原消息内容。';
  @override
  String get openTodo => '跳转到事项';
  @override
  String get linkOtherTodo => '关联到其他事项';
}

// Path: chat.messageViewer
class _StringsChatMessageViewerZhCn extends _StringsChatMessageViewerEn {
  _StringsChatMessageViewerZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '全文';
}

// Path: chat.markdownEditor
class _StringsChatMarkdownEditorZhCn extends _StringsChatMarkdownEditorEn {
  _StringsChatMarkdownEditorZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openButton => 'Markdown';
  @override
  String get title => 'Markdown 编辑器';
  @override
  String get apply => '应用';
  @override
  String get editorLabel => '编辑区';
  @override
  String get previewLabel => '预览区';
  @override
  String get emptyPreview => '输入后会在这里实时预览。';
  @override
  String get shortcutHint => '提示：按 Cmd/Ctrl + Enter 可快速应用内容。';
  @override
  String get listContinuationHint => '在列表项中按 Enter 可自动续写列表。';
  @override
  String get quickActionsLabel => '快捷格式';
  @override
  String get themeLabel => '预览主题';
  @override
  String get themeStudio => '经典';
  @override
  String get themePaper => '纸张';
  @override
  String get themeOcean => '海洋';
  @override
  String get themeNight => '夜色';
  @override
  String get exportMenu => '导出预览';
  @override
  String get exportPng => '导出为 PNG';
  @override
  String get exportPdf => '导出为 PDF';
  @override
  String exportDone({required Object format}) => '已导出为 ${format}';
  @override
  String exportSavedPath({required Object path}) => '已保存到：${path}';
  @override
  String exportFailed({required Object error}) => '导出失败：${error}';
  @override
  String stats({required Object lines, required Object characters}) =>
      '${lines} 行 · ${characters} 字符';
  @override
  String get simpleInput => '简易输入';
  @override
  late final _StringsChatMarkdownEditorActionsZhCn actions =
      _StringsChatMarkdownEditorActionsZhCn._(_root);
}

// Path: chat.focus
class _StringsChatFocusZhCn extends _StringsChatFocusEn {
  _StringsChatFocusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => '聚焦';
  @override
  String get allMemories => '聚焦：所有记忆';
  @override
  String get thisThread => '聚焦：当前对话';
}

// Path: chat.askAiSetup
class _StringsChatAskAiSetupZhCn extends _StringsChatAskAiSetupEn {
  _StringsChatAskAiSetupZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'AI 对话需要先配置';
  @override
  String get body => '要使用「AI 对话」，请先添加你自己的 API Key（AI 配置），或订阅 SecondLoop Cloud。';
  @override
  late final _StringsChatAskAiSetupActionsZhCn actions =
      _StringsChatAskAiSetupActionsZhCn._(_root);
}

// Path: chat.cloudGateway
class _StringsChatCloudGatewayZhCn extends _StringsChatCloudGatewayEn {
  _StringsChatCloudGatewayZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get emailNotVerified => '邮箱未验证。验证邮箱后才能使用 SecondLoop Cloud 的 AI 对话。';
  @override
  late final _StringsChatCloudGatewayFallbackZhCn fallback =
      _StringsChatCloudGatewayFallbackZhCn._(_root);
  @override
  late final _StringsChatCloudGatewayErrorsZhCn errors =
      _StringsChatCloudGatewayErrorsZhCn._(_root);
}

// Path: chat.askAiConsent
class _StringsChatAskAiConsentZhCn extends _StringsChatAskAiConsentEn {
  _StringsChatAskAiConsentZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '使用 AI 前确认';
  @override
  String get body =>
      'SecondLoop 可能会将你输入的文本及少量相关片段发送到你选择的 AI 服务商，以提供 AI 功能。\n\n不会上传你的主密码或完整历史。';
  @override
  String get dontShowAgain => '不再提示';
}

// Path: chat.embeddingsConsent
class _StringsChatEmbeddingsConsentZhCn
    extends _StringsChatEmbeddingsConsentEn {
  _StringsChatEmbeddingsConsentZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '是否使用云端向量进行语义检索？';
  @override
  String get body =>
      '好处：\n- 跨语言/同义改写召回更好\n- 待办关联建议更准确\n\n隐私：\n- 仅上传生成向量所需的最小文本片段\n- 文本会上传到 SecondLoop Cloud，并会被保密处理（不写入日志/存储）\n- 不会上传你的 vault key 或 sync key\n\n用量：\n- 云端向量会消耗 Cloud 使用额度';
  @override
  String get dontShowAgain => '记住我的选择';
  @override
  late final _StringsChatEmbeddingsConsentActionsZhCn actions =
      _StringsChatEmbeddingsConsentActionsZhCn._(_root);
}

// Path: chat.topicThread
class _StringsChatTopicThreadZhCn extends _StringsChatTopicThreadEn {
  _StringsChatTopicThreadZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get filterTooltip => '主题线程筛选';
  @override
  String get actionLabel => '主题线程';
  @override
  String get create => '新建主题线程';
  @override
  String get clearFilter => '清除线程筛选';
  @override
  String get clear => '清除线程';
  @override
  String get manage => '管理线程';
  @override
  String get rename => '重命名线程';
  @override
  String get delete => '删除线程';
  @override
  late final _StringsChatTopicThreadDeleteDialogZhCn deleteDialog =
      _StringsChatTopicThreadDeleteDialogZhCn._(_root);
  @override
  String get addMessage => '加入此消息';
  @override
  String get removeMessage => '移除此消息';
  @override
  String get createDialogTitle => '新建主题线程';
  @override
  String get renameDialogTitle => '重命名主题线程';
  @override
  String get titleFieldLabel => '线程标题（可选）';
  @override
  String get untitled => '未命名主题线程';
}

// Path: chat.tagFilter
class _StringsChatTagFilterZhCn extends _StringsChatTagFilterEn {
  _StringsChatTagFilterZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => '标签筛选';
  @override
  String get clearFilter => '清空标签筛选';
  @override
  late final _StringsChatTagFilterSheetZhCn sheet =
      _StringsChatTagFilterSheetZhCn._(_root);
}

// Path: chat.tagPicker
class _StringsChatTagPickerZhCn extends _StringsChatTagPickerEn {
  _StringsChatTagPickerZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '管理标签';
  @override
  String get suggested => '建议标签';
  @override
  String get mergeSuggestions => '合并建议';
  @override
  String get mergeAction => '合并';
  @override
  String get mergeDismissAction => '忽略';
  @override
  String get mergeLaterAction => '稍后';
  @override
  String mergeSuggestionMessages({required Object count}) =>
      '将影响 ${count} 条已打标签消息';
  @override
  String get mergeReasonSystemDomain => '匹配系统领域标签';
  @override
  String get mergeReasonNameCompact => '可能是重复标签';
  @override
  String get mergeReasonNameContains => '名称高度相似';
  @override
  late final _StringsChatTagPickerMergeDialogZhCn mergeDialog =
      _StringsChatTagPickerMergeDialogZhCn._(_root);
  @override
  String mergeApplied({required Object count}) => '已合并 ${count} 条消息';
  @override
  String get mergeDismissed => '已忽略该合并建议';
  @override
  String get mergeSavedForLater => '已暂存该合并建议';
  @override
  String get all => '全部标签';
  @override
  String get inputHint => '输入标签名称';
  @override
  String get add => '添加';
  @override
  String get save => '保存';
  @override
  String get tagActionLabel => '标签';
}

// Path: chat.askScopeEmpty
class _StringsChatAskScopeEmptyZhCn extends _StringsChatAskScopeEmptyEn {
  _StringsChatAskScopeEmptyZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '当前范围未找到结果';
  @override
  late final _StringsChatAskScopeEmptyActionsZhCn actions =
      _StringsChatAskScopeEmptyActionsZhCn._(_root);
}

// Path: attachments.metadata
class _StringsAttachmentsMetadataZhCn extends _StringsAttachmentsMetadataEn {
  _StringsAttachmentsMetadataZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get format => '格式';
  @override
  String get size => '大小';
  @override
  String get capturedAt => '拍摄时间';
  @override
  String get location => '地点';
}

// Path: attachments.url
class _StringsAttachmentsUrlZhCn extends _StringsAttachmentsUrlEn {
  _StringsAttachmentsUrlZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get originalUrl => '原始链接';
  @override
  String get canonicalUrl => '规范链接';
}

// Path: attachments.content
class _StringsAttachmentsContentZhCn extends _StringsAttachmentsContentEn {
  _StringsAttachmentsContentZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get summary => '摘要';
  @override
  String get excerpt => '摘要';
  @override
  String get fullText => '全文';
  @override
  String get ocrTitle => 'OCR';
  @override
  String get needsOcrTitle => '需要 OCR';
  @override
  String get needsOcrSubtitle => '此 PDF 可能不包含可复制文本。';
  @override
  String get runOcr => '运行 OCR';
  @override
  String get rerunOcr => '重新识别';
  @override
  String get ocrRunning => 'OCR 处理中…';
  @override
  String get ocrReadySubtitle => '已可用文本，如有需要可重新识别。';
  @override
  String get keepForegroundHint => 'OCR 进行中，请尽量保持应用在前台。';
  @override
  String get openWithSystem => '用系统应用打开';
  @override
  String get previewUnavailable => '预览不可用';
  @override
  String get ocrFinished => 'OCR 已完成，正在刷新预览…';
  @override
  String get ocrFailed => '此设备上 OCR 执行失败。';
  @override
  late final _StringsAttachmentsContentSpeechTranscribeIssueZhCn
      speechTranscribeIssue =
      _StringsAttachmentsContentSpeechTranscribeIssueZhCn._(_root);
  @override
  late final _StringsAttachmentsContentVideoInsightsZhCn videoInsights =
      _StringsAttachmentsContentVideoInsightsZhCn._(_root);
}

// Path: sync.progressDialog
class _StringsSyncProgressDialogZhCn extends _StringsSyncProgressDialogEn {
  _StringsSyncProgressDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '正在同步…';
  @override
  String get preparing => '正在准备…';
  @override
  String get pulling => '正在下载更改…';
  @override
  String get pushing => '正在上传更改…';
  @override
  String get uploadingMedia => '正在上传媒体…';
  @override
  String get finalizing => '正在收尾…';
}

// Path: sync.sections
class _StringsSyncSectionsZhCn extends _StringsSyncSectionsEn {
  _StringsSyncSectionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get automation => '自动同步';
  @override
  String get backend => '同步方式';
  @override
  String get mediaPreview => '媒体下载';
  @override
  String get mediaBackup => '媒体上传';
  @override
  String get securityActions => '安全与手动同步';
}

// Path: sync.autoSync
class _StringsSyncAutoSyncZhCn extends _StringsSyncAutoSyncEn {
  _StringsSyncAutoSyncZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '自动同步';
  @override
  String get subtitle => '自动保持你的设备间数据同步。';
  @override
  String get wifiOnlyTitle => '仅在 Wi‑Fi 下自动同步';
  @override
  String get wifiOnlySubtitle => '节省流量：自动同步只在 Wi‑Fi 下进行';
}

// Path: sync.mediaPreview
class _StringsSyncMediaPreviewZhCn extends _StringsSyncMediaPreviewEn {
  _StringsSyncMediaPreviewZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get chatThumbnailsWifiOnlyTitle => '仅在 Wi‑Fi 下下载媒体文件';
  @override
  String get chatThumbnailsWifiOnlySubtitle => '当附件在本机缺失时，仅在 Wi‑Fi 下自动下载';
}

// Path: sync.mediaBackup
class _StringsSyncMediaBackupZhCn extends _StringsSyncMediaBackupEn {
  _StringsSyncMediaBackupZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '媒体上传';
  @override
  String get subtitle => '后台上传加密图片，用于跨设备回看与回溯记忆';
  @override
  String get wifiOnlyTitle => '仅在 Wi‑Fi 下上传';
  @override
  String get wifiOnlySubtitle => '节省流量：只在 Wi‑Fi 下上传';
  @override
  String get description =>
      '将加密的图片附件上传到同步存储，用于跨设备回看，并支持后续的回溯记忆功能。附件在本机缺失时可按需下载。';
  @override
  String stats(
          {required Object pending,
          required Object failed,
          required Object uploaded}) =>
      '待上传 ${pending} · 失败 ${failed} · 已上传 ${uploaded}';
  @override
  String lastUploaded({required Object at}) => '最近一次上传：${at}';
  @override
  String lastError({required Object error}) => '最近一次错误：${error}';
  @override
  String lastErrorWithTime({required Object at, required Object error}) =>
      '最近一次错误（${at}）：${error}';
  @override
  String get backfillButton => '加入历史图片';
  @override
  String get uploadNowButton => '立即上传';
  @override
  String backfillEnqueued({required Object count}) => '已将 ${count} 张图片加入上传队列';
  @override
  String backfillFailed({required Object error}) => '加入失败：${error}';
  @override
  String get notEnabled => '请先开启媒体上传。';
  @override
  String get managedVaultOnly => '媒体上传仅适用于 WebDAV 或 SecondLoop 云同步。';
  @override
  String get wifiOnlyBlocked => '已开启仅 Wi‑Fi。请连接 Wi‑Fi，或仅本次允许使用蜂窝数据。';
  @override
  String get uploaded => '上传完成';
  @override
  String get nothingToUpload => '暂无可上传内容';
  @override
  String uploadFailed({required Object error}) => '上传失败：${error}';
  @override
  late final _StringsSyncMediaBackupCellularDialogZhCn cellularDialog =
      _StringsSyncMediaBackupCellularDialogZhCn._(_root);
}

// Path: sync.localCache
class _StringsSyncLocalCacheZhCn extends _StringsSyncLocalCacheEn {
  _StringsSyncLocalCacheZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get button => '清理本地存储';
  @override
  String get subtitle => '删除本机缓存的附件文件（远端保留，需要时可重新下载）。请确保已完成同步/上传。';
  @override
  String get cleared => '已清理本地缓存';
  @override
  String failed({required Object error}) => '清理失败：${error}';
  @override
  late final _StringsSyncLocalCacheDialogZhCn dialog =
      _StringsSyncLocalCacheDialogZhCn._(_root);
}

// Path: sync.cloudManagedVault
class _StringsSyncCloudManagedVaultZhCn
    extends _StringsSyncCloudManagedVaultEn {
  _StringsSyncCloudManagedVaultZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get signInRequired => '请先登录 SecondLoop Cloud 才能使用云同步。';
  @override
  String get paymentRequired => '云同步已暂停。请续费订阅以继续同步。';
  @override
  String graceReadonlyUntil({required Object until}) =>
      '云同步处于只读状态（宽限期至 ${until}）。';
  @override
  String get storageQuotaExceeded => '云端存储已满，已暂停上传。';
  @override
  String storageQuotaExceededWithUsage(
          {required Object used, required Object limit}) =>
      '云端存储已满（${used} / ${limit}），已暂停上传。';
  @override
  late final _StringsSyncCloudManagedVaultSwitchDialogZhCn switchDialog =
      _StringsSyncCloudManagedVaultSwitchDialogZhCn._(_root);
  @override
  late final _StringsSyncCloudManagedVaultSetPassphraseDialogZhCn
      setPassphraseDialog =
      _StringsSyncCloudManagedVaultSetPassphraseDialogZhCn._(_root);
}

// Path: sync.fields
class _StringsSyncFieldsZhCn extends _StringsSyncFieldsEn {
  _StringsSyncFieldsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSyncFieldsBaseUrlZhCn baseUrl =
      _StringsSyncFieldsBaseUrlZhCn._(_root);
  @override
  late final _StringsSyncFieldsUsernameZhCn username =
      _StringsSyncFieldsUsernameZhCn._(_root);
  @override
  late final _StringsSyncFieldsPasswordZhCn password =
      _StringsSyncFieldsPasswordZhCn._(_root);
  @override
  late final _StringsSyncFieldsLocalDirZhCn localDir =
      _StringsSyncFieldsLocalDirZhCn._(_root);
  @override
  late final _StringsSyncFieldsManagedVaultBaseUrlZhCn managedVaultBaseUrl =
      _StringsSyncFieldsManagedVaultBaseUrlZhCn._(_root);
  @override
  late final _StringsSyncFieldsVaultIdZhCn vaultId =
      _StringsSyncFieldsVaultIdZhCn._(_root);
  @override
  late final _StringsSyncFieldsRemoteRootZhCn remoteRoot =
      _StringsSyncFieldsRemoteRootZhCn._(_root);
  @override
  late final _StringsSyncFieldsPassphraseZhCn passphrase =
      _StringsSyncFieldsPassphraseZhCn._(_root);
}

// Path: llmProfiles.deleteDialog
class _StringsLlmProfilesDeleteDialogZhCn
    extends _StringsLlmProfilesDeleteDialogEn {
  _StringsLlmProfilesDeleteDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '删除配置？';
  @override
  String message({required Object name}) => '确定删除「${name}」？该操作会从本设备移除。';
}

// Path: llmProfiles.fields
class _StringsLlmProfilesFieldsZhCn extends _StringsLlmProfilesFieldsEn {
  _StringsLlmProfilesFieldsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get name => '名称';
  @override
  String get provider => '提供商';
  @override
  String get baseUrlOptional => '接口地址（可选）';
  @override
  String get modelName => '模型名称';
  @override
  String get apiKey => 'API Key';
}

// Path: llmProfiles.providers
class _StringsLlmProfilesProvidersZhCn extends _StringsLlmProfilesProvidersEn {
  _StringsLlmProfilesProvidersZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openaiCompatible => 'OpenAI 兼容';
  @override
  String get geminiCompatible => 'Gemini';
  @override
  String get anthropicCompatible => 'Anthropic';
}

// Path: llmProfiles.actions
class _StringsLlmProfilesActionsZhCn extends _StringsLlmProfilesActionsEn {
  _StringsLlmProfilesActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get saveActivate => '保存并启用';
  @override
  String get cancel => '取消';
  @override
  String get delete => '删除';
}

// Path: embeddingProfiles.reindexDialog
class _StringsEmbeddingProfilesReindexDialogZhCn
    extends _StringsEmbeddingProfilesReindexDialogEn {
  _StringsEmbeddingProfilesReindexDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '重新索引向量？';
  @override
  String get message => '启用该配置可能会使用你的 API key/额度重新向量化本地内容（可能耗时并产生费用）。';
  @override
  late final _StringsEmbeddingProfilesReindexDialogActionsZhCn actions =
      _StringsEmbeddingProfilesReindexDialogActionsZhCn._(_root);
}

// Path: embeddingProfiles.deleteDialog
class _StringsEmbeddingProfilesDeleteDialogZhCn
    extends _StringsEmbeddingProfilesDeleteDialogEn {
  _StringsEmbeddingProfilesDeleteDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '删除配置？';
  @override
  String message({required Object name}) => '确定删除「${name}」？该操作会从本设备移除。';
}

// Path: embeddingProfiles.fields
class _StringsEmbeddingProfilesFieldsZhCn
    extends _StringsEmbeddingProfilesFieldsEn {
  _StringsEmbeddingProfilesFieldsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get name => '名称';
  @override
  String get provider => '提供商';
  @override
  String get baseUrlOptional => '接口地址（可选）';
  @override
  String get modelName => '模型名称';
  @override
  String get apiKey => 'API Key';
}

// Path: embeddingProfiles.providers
class _StringsEmbeddingProfilesProvidersZhCn
    extends _StringsEmbeddingProfilesProvidersEn {
  _StringsEmbeddingProfilesProvidersZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openaiCompatible => 'OpenAI 兼容';
}

// Path: embeddingProfiles.actions
class _StringsEmbeddingProfilesActionsZhCn
    extends _StringsEmbeddingProfilesActionsEn {
  _StringsEmbeddingProfilesActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get saveActivate => '保存并启用';
  @override
  String get cancel => '取消';
  @override
  String get delete => '删除';
}

// Path: actions.reviewQueue.inAppFallback
class _StringsActionsReviewQueueInAppFallbackZhCn
    extends _StringsActionsReviewQueueInAppFallbackEn {
  _StringsActionsReviewQueueInAppFallbackZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String message({required Object count}) => '有 ${count} 条事项正在等待你确认';
  @override
  String get open => '打开待确认队列';
  @override
  String get dismiss => '稍后再说';
}

// Path: actions.reviewQueue.actions
class _StringsActionsReviewQueueActionsZhCn
    extends _StringsActionsReviewQueueActionsEn {
  _StringsActionsReviewQueueActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get schedule => '安排时间';
  @override
  String get snooze => '明早提醒';
  @override
  String get start => '开始';
  @override
  String get done => '完成';
  @override
  String get dismiss => '忽略';
}

// Path: actions.todoDelete.dialog
class _StringsActionsTodoDeleteDialogZhCn
    extends _StringsActionsTodoDeleteDialogEn {
  _StringsActionsTodoDeleteDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '删除待办？';
  @override
  String get message => '这将永久删除该待办，并删除所有关联的聊天消息。';
  @override
  String get confirm => '删除';
}

// Path: actions.history.presets
class _StringsActionsHistoryPresetsZhCn
    extends _StringsActionsHistoryPresetsEn {
  _StringsActionsHistoryPresetsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get thisWeek => '本周';
  @override
  String get lastWeek => '上周';
  @override
  String get lastTwoWeeks => '上两周';
  @override
  String get custom => '自定义范围';
}

// Path: actions.history.actions
class _StringsActionsHistoryActionsZhCn
    extends _StringsActionsHistoryActionsEn {
  _StringsActionsHistoryActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get copy => '复制';
  @override
  String get copied => '已复制';
}

// Path: actions.history.sections
class _StringsActionsHistorySectionsZhCn
    extends _StringsActionsHistorySectionsEn {
  _StringsActionsHistorySectionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get created => '新增';
  @override
  String get started => '开始';
  @override
  String get done => '完成';
  @override
  String get dismissed => '不再提醒';
}

// Path: settings.actionsReview.morningTime
class _StringsSettingsActionsReviewMorningTimeZhCn
    extends _StringsSettingsActionsReviewMorningTimeEn {
  _StringsSettingsActionsReviewMorningTimeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '早上提醒时间';
  @override
  String get subtitle => '未排期事项的默认提醒时间';
}

// Path: settings.actionsReview.dayEndTime
class _StringsSettingsActionsReviewDayEndTimeZhCn
    extends _StringsSettingsActionsReviewDayEndTimeEn {
  _StringsSettingsActionsReviewDayEndTimeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '日终时间';
  @override
  String get subtitle => '到此时间仍未处理，将降低提醒频率';
}

// Path: settings.actionsReview.weeklyTime
class _StringsSettingsActionsReviewWeeklyTimeZhCn
    extends _StringsSettingsActionsReviewWeeklyTimeEn {
  _StringsSettingsActionsReviewWeeklyTimeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '每周提醒时间';
  @override
  String get subtitle => '每周提醒时间（周日）';
}

// Path: settings.actionsReview.inAppFallback
class _StringsSettingsActionsReviewInAppFallbackZhCn
    extends _StringsSettingsActionsReviewInAppFallbackEn {
  _StringsSettingsActionsReviewInAppFallbackZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '应用内提醒';
  @override
  String get subtitle => '在应用内显示待办事项通知';
}

// Path: settings.quickCaptureHotkey.actions
class _StringsSettingsQuickCaptureHotkeyActionsZhCn
    extends _StringsSettingsQuickCaptureHotkeyActionsEn {
  _StringsSettingsQuickCaptureHotkeyActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get resetDefault => '恢复默认';
}

// Path: settings.quickCaptureHotkey.validation
class _StringsSettingsQuickCaptureHotkeyValidationZhCn
    extends _StringsSettingsQuickCaptureHotkeyValidationEn {
  _StringsSettingsQuickCaptureHotkeyValidationZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get missingModifier => '至少包含一个修饰键（Ctrl/Alt/Shift 等）';
  @override
  String get modifierOnly => '快捷键必须包含一个非修饰键。';
  @override
  String systemConflict({required Object name}) => '与系统快捷键冲突：${name}';
}

// Path: settings.quickCaptureHotkey.conflicts
class _StringsSettingsQuickCaptureHotkeyConflictsZhCn
    extends _StringsSettingsQuickCaptureHotkeyConflictsEn {
  _StringsSettingsQuickCaptureHotkeyConflictsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get macosSpotlight => 'Spotlight';
  @override
  String get macosFinderSearch => 'Finder 搜索';
  @override
  String get macosInputSourceSwitch => '切换输入法';
  @override
  String get macosEmojiPicker => '表情与符号';
  @override
  String get macosScreenshot => '截屏';
  @override
  String get macosAppSwitcher => '应用切换器';
  @override
  String get macosForceQuit => '强制退出';
  @override
  String get macosLockScreen => '锁定屏幕';
  @override
  String get windowsLock => '锁定屏幕';
  @override
  String get windowsShowDesktop => '显示桌面';
  @override
  String get windowsFileExplorer => '文件资源管理器';
  @override
  String get windowsRun => '运行';
  @override
  String get windowsSearch => '搜索';
  @override
  String get windowsSettings => '设置';
  @override
  String get windowsTaskView => '任务视图';
  @override
  String get windowsLanguageSwitch => '切换输入法';
  @override
  String get windowsAppSwitcher => '应用切换器';
}

// Path: settings.desktopBoot.startWithSystem
class _StringsSettingsDesktopBootStartWithSystemZhCn
    extends _StringsSettingsDesktopBootStartWithSystemEn {
  _StringsSettingsDesktopBootStartWithSystemZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '随系统启动';
  @override
  String get subtitle => '登录系统后自动启动 SecondLoop';
}

// Path: settings.desktopBoot.silentStartup
class _StringsSettingsDesktopBootSilentStartupZhCn
    extends _StringsSettingsDesktopBootSilentStartupEn {
  _StringsSettingsDesktopBootSilentStartupZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '静默启动';
  @override
  String get subtitle => '自动启动时在后台运行，不弹出主窗口';
}

// Path: settings.desktopBoot.keepRunningInBackground
class _StringsSettingsDesktopBootKeepRunningInBackgroundZhCn
    extends _StringsSettingsDesktopBootKeepRunningInBackgroundEn {
  _StringsSettingsDesktopBootKeepRunningInBackgroundZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '关闭时常驻后台';
  @override
  String get subtitle => '关闭窗口时最小化到通知栏，而不是直接退出';
}

// Path: settings.desktopTray.menu
class _StringsSettingsDesktopTrayMenuZhCn
    extends _StringsSettingsDesktopTrayMenuEn {
  _StringsSettingsDesktopTrayMenuZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get hide => '隐藏';
  @override
  String get quit => '退出';
}

// Path: settings.desktopTray.pro
class _StringsSettingsDesktopTrayProZhCn
    extends _StringsSettingsDesktopTrayProEn {
  _StringsSettingsDesktopTrayProZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get signedIn => '已登录';
  @override
  String get aiUsage => 'AI 用量';
  @override
  String get storageUsage => '存储用量';
}

// Path: settings.language.options
class _StringsSettingsLanguageOptionsZhCn
    extends _StringsSettingsLanguageOptionsEn {
  _StringsSettingsLanguageOptionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get system => '系统';
  @override
  String systemWithValue({required Object value}) => '系统（${value}）';
  @override
  String get en => 'English';
  @override
  String get zhCn => '简体中文';
}

// Path: settings.theme.options
class _StringsSettingsThemeOptionsZhCn extends _StringsSettingsThemeOptionsEn {
  _StringsSettingsThemeOptionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get system => '系统';
  @override
  String get light => '明亮';
  @override
  String get dark => '深色';
}

// Path: settings.aiSelection.askAi
class _StringsSettingsAiSelectionAskAiZhCn
    extends _StringsSettingsAiSelectionAskAiEn {
  _StringsSettingsAiSelectionAskAiZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'AI 对话';
  @override
  String get description => '决定“AI 对话”使用哪种服务来源（Cloud 或 API 密钥）。';
  @override
  String get setupHint => '还没完成“AI 对话”设置，请先登录 Cloud 或添加 API 密钥。';
  @override
  String get preferenceUnavailableHint =>
      '你选择的“AI 对话”来源暂时不可用，请先完成 Cloud 或 API 密钥设置。';
  @override
  late final _StringsSettingsAiSelectionAskAiStatusZhCn status =
      _StringsSettingsAiSelectionAskAiStatusZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionAskAiPreferenceZhCn preference =
      _StringsSettingsAiSelectionAskAiPreferenceZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionAskAiActionsZhCn actions =
      _StringsSettingsAiSelectionAskAiActionsZhCn._(_root);
}

// Path: settings.aiSelection.embeddings
class _StringsSettingsAiSelectionEmbeddingsZhCn
    extends _StringsSettingsAiSelectionEmbeddingsEn {
  _StringsSettingsAiSelectionEmbeddingsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '智能检索（Embedding）';
  @override
  String get description => '给消息和待办生成检索索引，这是基础智能检索能力；开启下方“云端增强检索”后，结果通常更准确。';
  @override
  String get preferenceUnavailableHint => '你选择的智能检索来源暂时不可用，已自动切换到可用方案。';
  @override
  late final _StringsSettingsAiSelectionEmbeddingsStatusZhCn status =
      _StringsSettingsAiSelectionEmbeddingsStatusZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceZhCn preference =
      _StringsSettingsAiSelectionEmbeddingsPreferenceZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionEmbeddingsActionsZhCn actions =
      _StringsSettingsAiSelectionEmbeddingsActionsZhCn._(_root);
}

// Path: settings.aiSelection.mediaUnderstanding
class _StringsSettingsAiSelectionMediaUnderstandingZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingEn {
  _StringsSettingsAiSelectionMediaUnderstandingZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '图片与音频理解';
  @override
  String get description => '决定图片读字（OCR）、图片说明和语音转文字由谁处理。';
  @override
  String get preferenceUnavailableHint => '你选择的图片/音频处理来源暂时不可用，已自动切换到可用方案。';
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingStatusZhCn status =
      _StringsSettingsAiSelectionMediaUnderstandingStatusZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceZhCn
      preference =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingActionsZhCn actions =
      _StringsSettingsAiSelectionMediaUnderstandingActionsZhCn._(_root);
}

// Path: settings.semanticParseAutoActions.dialogActions
class _StringsSettingsSemanticParseAutoActionsDialogActionsZhCn
    extends _StringsSettingsSemanticParseAutoActionsDialogActionsEn {
  _StringsSettingsSemanticParseAutoActionsDialogActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get enable => '开启';
}

// Path: settings.mediaAnnotation.routingGuide
class _StringsSettingsMediaAnnotationRoutingGuideZhCn
    extends _StringsSettingsMediaAnnotationRoutingGuideEn {
  _StringsSettingsMediaAnnotationRoutingGuideZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '先选择 AI 来源';
  @override
  String get pro => 'Pro 且已登录：默认使用 SecondLoop Cloud。';
  @override
  String get byok => '免费/BYOK：请先在「AI 对话」里添加 OpenAI-compatible 配置档，并设为当前使用。';
}

// Path: settings.mediaAnnotation.documentOcr
class _StringsSettingsMediaAnnotationDocumentOcrZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrEn {
  _StringsSettingsMediaAnnotationDocumentOcrZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '文档 OCR';
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrEnabledZhCn enabled =
      _StringsSettingsMediaAnnotationDocumentOcrEnabledZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsZhCn
      languageHints =
      _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesZhCn
      pdfAutoMaxPages =
      _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrPdfDpiZhCn pdfDpi =
      _StringsSettingsMediaAnnotationDocumentOcrPdfDpiZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsZhCn
      linuxModels =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsZhCn._(_root);
}

// Path: settings.mediaAnnotation.audioTranscribe
class _StringsSettingsMediaAnnotationAudioTranscribeZhCn
    extends _StringsSettingsMediaAnnotationAudioTranscribeEn {
  _StringsSettingsMediaAnnotationAudioTranscribeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '音频转写';
  @override
  late final _StringsSettingsMediaAnnotationAudioTranscribeEnabledZhCn enabled =
      _StringsSettingsMediaAnnotationAudioTranscribeEnabledZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAudioTranscribeEngineZhCn engine =
      _StringsSettingsMediaAnnotationAudioTranscribeEngineZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiZhCn
      configureApi =
      _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiZhCn._(_root);
}

// Path: settings.mediaAnnotation.imageCaption
class _StringsSettingsMediaAnnotationImageCaptionZhCn
    extends _StringsSettingsMediaAnnotationImageCaptionEn {
  _StringsSettingsMediaAnnotationImageCaptionZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '图片注释';
}

// Path: settings.mediaAnnotation.providerSettings
class _StringsSettingsMediaAnnotationProviderSettingsZhCn
    extends _StringsSettingsMediaAnnotationProviderSettingsEn {
  _StringsSettingsMediaAnnotationProviderSettingsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '图片注释服务来源';
}

// Path: settings.mediaAnnotation.setupRequired
class _StringsSettingsMediaAnnotationSetupRequiredZhCn
    extends _StringsSettingsMediaAnnotationSetupRequiredEn {
  _StringsSettingsMediaAnnotationSetupRequiredZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '图片注释需要先配置';
  @override
  String get body => '要注释图片，SecondLoop 需要一个多模态模型。';
  @override
  late final _StringsSettingsMediaAnnotationSetupRequiredReasonsZhCn reasons =
      _StringsSettingsMediaAnnotationSetupRequiredReasonsZhCn._(_root);
}

// Path: settings.mediaAnnotation.annotateEnabled
class _StringsSettingsMediaAnnotationAnnotateEnabledZhCn
    extends _StringsSettingsMediaAnnotationAnnotateEnabledEn {
  _StringsSettingsMediaAnnotationAnnotateEnabledZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '注释图片';
  @override
  String get subtitle => '添加图片后，SecondLoop 可能会将图片发送给 AI 生成加密注释。';
}

// Path: settings.mediaAnnotation.searchEnabled
class _StringsSettingsMediaAnnotationSearchEnabledZhCn
    extends _StringsSettingsMediaAnnotationSearchEnabledEn {
  _StringsSettingsMediaAnnotationSearchEnabledZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '注释用于搜索';
  @override
  String get subtitle => '将图片注释加入搜索索引。';
}

// Path: settings.mediaAnnotation.searchToggleConfirm
class _StringsSettingsMediaAnnotationSearchToggleConfirmZhCn
    extends _StringsSettingsMediaAnnotationSearchToggleConfirmEn {
  _StringsSettingsMediaAnnotationSearchToggleConfirmZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '更新搜索索引？';
  @override
  String get bodyEnable => '开启后会重新生成搜索数据，让图片注释可被检索。';
  @override
  String get bodyDisable => '关闭后会重新生成搜索数据，从检索中移除图片注释。';
}

// Path: settings.mediaAnnotation.advanced
class _StringsSettingsMediaAnnotationAdvancedZhCn
    extends _StringsSettingsMediaAnnotationAdvancedEn {
  _StringsSettingsMediaAnnotationAdvancedZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '高级设置';
}

// Path: settings.mediaAnnotation.providerMode
class _StringsSettingsMediaAnnotationProviderModeZhCn
    extends _StringsSettingsMediaAnnotationProviderModeEn {
  _StringsSettingsMediaAnnotationProviderModeZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '多模态模型';
  @override
  String get subtitle => '为图片注释选择独立于“AI 对话”的服务商/模型。';
  @override
  late final _StringsSettingsMediaAnnotationProviderModeLabelsZhCn labels =
      _StringsSettingsMediaAnnotationProviderModeLabelsZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationProviderModeDescriptionsZhCn
      descriptions =
      _StringsSettingsMediaAnnotationProviderModeDescriptionsZhCn._(_root);
}

// Path: settings.mediaAnnotation.cloudModelName
class _StringsSettingsMediaAnnotationCloudModelNameZhCn
    extends _StringsSettingsMediaAnnotationCloudModelNameEn {
  _StringsSettingsMediaAnnotationCloudModelNameZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cloud 模型名';
  @override
  String get subtitle => '可选：覆盖云端多模态模型名。';
  @override
  String get hint => '例如 gpt-4o-mini';
  @override
  String get followAskAi => '跟随 AI 对话';
}

// Path: settings.mediaAnnotation.byokProfile
class _StringsSettingsMediaAnnotationByokProfileZhCn
    extends _StringsSettingsMediaAnnotationByokProfileEn {
  _StringsSettingsMediaAnnotationByokProfileZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API Key 配置档';
  @override
  String get subtitle => '选择图片注释使用哪个配置档。';
  @override
  String get unset => '未设置';
  @override
  String get missingBackend => '当前构建不可用。';
  @override
  String get noOpenAiCompatibleProfiles =>
      '没有可用的 OpenAI-compatible 配置档，请先在“API Key（AI 对话）”里添加。';
}

// Path: settings.mediaAnnotation.allowCellular
class _StringsSettingsMediaAnnotationAllowCellularZhCn
    extends _StringsSettingsMediaAnnotationAllowCellularEn {
  _StringsSettingsMediaAnnotationAllowCellularZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '允许蜂窝网络';
  @override
  String get subtitle => '允许用蜂窝网络进行图片注释（默认仅 Wi‑Fi）。';
}

// Path: settings.mediaAnnotation.allowCellularConfirm
class _StringsSettingsMediaAnnotationAllowCellularConfirmZhCn
    extends _StringsSettingsMediaAnnotationAllowCellularConfirmEn {
  _StringsSettingsMediaAnnotationAllowCellularConfirmZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '允许使用蜂窝网络注释图片？';
  @override
  String get body => '图片注释可能会向你选择的 AI 服务商上传图片，并消耗一定流量。';
}

// Path: settings.cloudEmbeddings.dialogActions
class _StringsSettingsCloudEmbeddingsDialogActionsZhCn
    extends _StringsSettingsCloudEmbeddingsDialogActionsEn {
  _StringsSettingsCloudEmbeddingsDialogActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get enable => '开启';
}

// Path: settings.cloudAccount.benefits
class _StringsSettingsCloudAccountBenefitsZhCn
    extends _StringsSettingsCloudAccountBenefitsEn {
  _StringsSettingsCloudAccountBenefitsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '创建 Cloud 账号以购买订阅';
  @override
  late final _StringsSettingsCloudAccountBenefitsItemsZhCn items =
      _StringsSettingsCloudAccountBenefitsItemsZhCn._(_root);
}

// Path: settings.cloudAccount.errors
class _StringsSettingsCloudAccountErrorsZhCn
    extends _StringsSettingsCloudAccountErrorsEn {
  _StringsSettingsCloudAccountErrorsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get missingWebApiKey =>
      '当前版本暂不支持 Cloud 登录。如果你是从源码运行，请先执行 `pixi run init-env`（或复制 `.env.example` → `.env.local`），填入 `SECONDLOOP_FIREBASE_WEB_API_KEY`，然后重启 App。';
}

// Path: settings.cloudAccount.fields
class _StringsSettingsCloudAccountFieldsZhCn
    extends _StringsSettingsCloudAccountFieldsEn {
  _StringsSettingsCloudAccountFieldsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get email => '邮箱';
  @override
  String get password => '密码';
}

// Path: settings.cloudAccount.actions
class _StringsSettingsCloudAccountActionsZhCn
    extends _StringsSettingsCloudAccountActionsEn {
  _StringsSettingsCloudAccountActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get signIn => '登录';
  @override
  String get signUp => '创建账号';
  @override
  String get signOut => '退出登录';
}

// Path: settings.cloudAccount.emailVerification
class _StringsSettingsCloudAccountEmailVerificationZhCn
    extends _StringsSettingsCloudAccountEmailVerificationEn {
  _StringsSettingsCloudAccountEmailVerificationZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '邮箱验证';
  @override
  late final _StringsSettingsCloudAccountEmailVerificationStatusZhCn status =
      _StringsSettingsCloudAccountEmailVerificationStatusZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountEmailVerificationLabelsZhCn labels =
      _StringsSettingsCloudAccountEmailVerificationLabelsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountEmailVerificationActionsZhCn actions =
      _StringsSettingsCloudAccountEmailVerificationActionsZhCn._(_root);
  @override
  late final _StringsSettingsCloudAccountEmailVerificationMessagesZhCn
      messages =
      _StringsSettingsCloudAccountEmailVerificationMessagesZhCn._(_root);
}

// Path: settings.cloudUsage.actions
class _StringsSettingsCloudUsageActionsZhCn
    extends _StringsSettingsCloudUsageActionsEn {
  _StringsSettingsCloudUsageActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get refresh => '刷新';
}

// Path: settings.cloudUsage.labels
class _StringsSettingsCloudUsageLabelsZhCn
    extends _StringsSettingsCloudUsageLabelsEn {
  _StringsSettingsCloudUsageLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get gatewayNotConfigured => '当前版本暂不支持查看云端用量。';
  @override
  String get signInRequired => '登录后才能查看用量。';
  @override
  String get usage => '用量：';
  @override
  String get askAiUsage => 'AI 对话：';
  @override
  String get embeddingsUsage => '智能搜索：';
  @override
  String get inputTokensUsed30d => '输入 Tokens（30 天）：';
  @override
  String get outputTokensUsed30d => '输出 Tokens（30 天）：';
  @override
  String get tokensUsed30d => 'Tokens（30 天）：';
  @override
  String get requestsUsed30d => '请求数（30 天）：';
  @override
  String get resetAt => '重置时间：';
  @override
  String get paymentRequired => '需订阅后才能查看云端用量。';
  @override
  String loadFailed({required Object error}) => '加载失败：${error}';
}

// Path: settings.vaultUsage.actions
class _StringsSettingsVaultUsageActionsZhCn
    extends _StringsSettingsVaultUsageActionsEn {
  _StringsSettingsVaultUsageActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get refresh => '刷新';
}

// Path: settings.vaultUsage.labels
class _StringsSettingsVaultUsageLabelsZhCn
    extends _StringsSettingsVaultUsageLabelsEn {
  _StringsSettingsVaultUsageLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get notConfigured => '当前版本暂不支持查看云端存储用量。';
  @override
  String get signInRequired => '登录后才能查看云端存储用量。';
  @override
  String get used => '已用：';
  @override
  String get limit => '上限：';
  @override
  String get attachments => '照片与文件：';
  @override
  String get ops => '同步记录：';
  @override
  String loadFailed({required Object error}) => '加载失败：${error}';
}

// Path: settings.diagnostics.messages
class _StringsSettingsDiagnosticsMessagesZhCn
    extends _StringsSettingsDiagnosticsMessagesEn {
  _StringsSettingsDiagnosticsMessagesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get copied => '诊断信息已复制';
  @override
  String copyFailed({required Object error}) => '复制诊断信息失败：${error}';
  @override
  String shareFailed({required Object error}) => '分享诊断信息失败：${error}';
}

// Path: settings.byokUsage.errors
class _StringsSettingsByokUsageErrorsZhCn
    extends _StringsSettingsByokUsageErrorsEn {
  _StringsSettingsByokUsageErrorsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String unavailable({required Object error}) => '用量不可用：${error}';
}

// Path: settings.byokUsage.sections
class _StringsSettingsByokUsageSectionsZhCn
    extends _StringsSettingsByokUsageSectionsEn {
  _StringsSettingsByokUsageSectionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String today({required Object day}) => '今日（${day}）';
  @override
  String last30d({required Object start, required Object end}) =>
      '近 30 天（${start} → ${end}）';
}

// Path: settings.byokUsage.labels
class _StringsSettingsByokUsageLabelsZhCn
    extends _StringsSettingsByokUsageLabelsEn {
  _StringsSettingsByokUsageLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String requests({required Object purpose}) => '${purpose} 请求数';
  @override
  String tokens({required Object purpose}) => '${purpose} tokens（输入/输出/总计）';
}

// Path: settings.byokUsage.purposes
class _StringsSettingsByokUsagePurposesZhCn
    extends _StringsSettingsByokUsagePurposesEn {
  _StringsSettingsByokUsagePurposesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get semanticParse => '语义解析';
  @override
  String get mediaAnnotation => '图片注释';
}

// Path: settings.subscription.benefits
class _StringsSettingsSubscriptionBenefitsZhCn
    extends _StringsSettingsSubscriptionBenefitsEn {
  _StringsSettingsSubscriptionBenefitsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'SecondLoop Pro 可解锁';
  @override
  late final _StringsSettingsSubscriptionBenefitsItemsZhCn items =
      _StringsSettingsSubscriptionBenefitsItemsZhCn._(_root);
}

// Path: settings.subscription.status
class _StringsSettingsSubscriptionStatusZhCn
    extends _StringsSettingsSubscriptionStatusEn {
  _StringsSettingsSubscriptionStatusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get unknown => '未知';
  @override
  String get entitled => '已生效';
  @override
  String get notEntitled => '未生效';
}

// Path: settings.subscription.actions
class _StringsSettingsSubscriptionActionsZhCn
    extends _StringsSettingsSubscriptionActionsEn {
  _StringsSettingsSubscriptionActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get purchase => '订阅';
}

// Path: settings.subscription.labels
class _StringsSettingsSubscriptionLabelsZhCn
    extends _StringsSettingsSubscriptionLabelsEn {
  _StringsSettingsSubscriptionLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get status => '状态：';
  @override
  String get purchaseUnavailable => '订阅购买暂未开放。';
  @override
  String loadFailed({required Object error}) => '加载失败：${error}';
}

// Path: chat.markdownEditor.actions
class _StringsChatMarkdownEditorActionsZhCn
    extends _StringsChatMarkdownEditorActionsEn {
  _StringsChatMarkdownEditorActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get heading => '标题';
  @override
  String headingLevel({required Object level}) => '${level} 级标题';
  @override
  String get bold => '加粗';
  @override
  String get italic => '斜体';
  @override
  String get strike => '删除线';
  @override
  String get code => '行内代码';
  @override
  String get link => '插入链接';
  @override
  String get blockquote => '引用';
  @override
  String get bulletList => '无序列表';
  @override
  String get orderedList => '有序列表';
  @override
  String get taskList => '任务列表';
  @override
  String get codeBlock => '代码块';
}

// Path: chat.askAiSetup.actions
class _StringsChatAskAiSetupActionsZhCn
    extends _StringsChatAskAiSetupActionsEn {
  _StringsChatAskAiSetupActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get subscribe => '订阅';
  @override
  String get configureByok => '添加 API Key';
}

// Path: chat.cloudGateway.fallback
class _StringsChatCloudGatewayFallbackZhCn
    extends _StringsChatCloudGatewayFallbackEn {
  _StringsChatCloudGatewayFallbackZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get auth => 'Cloud 登录已失效。本次将使用你的 API Key。';
  @override
  String get entitlement => '需要订阅 SecondLoop Cloud。本次将使用你的 API Key。';
  @override
  String get rateLimited => 'Cloud 正忙。本次将使用你的 API Key。';
  @override
  String get generic => 'Cloud 请求失败。本次将使用你的 API Key。';
}

// Path: chat.cloudGateway.errors
class _StringsChatCloudGatewayErrorsZhCn
    extends _StringsChatCloudGatewayErrorsEn {
  _StringsChatCloudGatewayErrorsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get auth => 'Cloud 登录已失效，请在 Cloud 账号页重新登录。';
  @override
  String get entitlement => '需要订阅 SecondLoop Cloud。请添加 API Key 或稍后再试。';
  @override
  String get rateLimited => 'Cloud 触发限速，请稍后再试。';
  @override
  String get generic => 'Cloud 请求失败。';
}

// Path: chat.embeddingsConsent.actions
class _StringsChatEmbeddingsConsentActionsZhCn
    extends _StringsChatEmbeddingsConsentActionsEn {
  _StringsChatEmbeddingsConsentActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get useLocal => '使用本地';
  @override
  String get enableCloud => '开启云端向量';
}

// Path: chat.topicThread.deleteDialog
class _StringsChatTopicThreadDeleteDialogZhCn
    extends _StringsChatTopicThreadDeleteDialogEn {
  _StringsChatTopicThreadDeleteDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '删除主题线程？';
  @override
  String get message => '删除后将移除该线程及其消息归属，且无法撤销。';
  @override
  String get confirm => '删除';
}

// Path: chat.tagFilter.sheet
class _StringsChatTagFilterSheetZhCn extends _StringsChatTagFilterSheetEn {
  _StringsChatTagFilterSheetZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '按标签筛选';
  @override
  String get apply => '应用';
  @override
  String get clear => '清空';
  @override
  String get includeHint => '点击：包含';
  @override
  String get excludeHint => '再次点击：排除';
  @override
  String get empty => '暂无标签';
}

// Path: chat.tagPicker.mergeDialog
class _StringsChatTagPickerMergeDialogZhCn
    extends _StringsChatTagPickerMergeDialogEn {
  _StringsChatTagPickerMergeDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '确认合并标签？';
  @override
  String message({required Object source, required Object target}) =>
      '将“${source}”合并到“${target}”？这会更新已有消息上的标签。';
  @override
  String get confirm => '合并';
}

// Path: chat.askScopeEmpty.actions
class _StringsChatAskScopeEmptyActionsZhCn
    extends _StringsChatAskScopeEmptyActionsEn {
  _StringsChatAskScopeEmptyActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get expandTimeWindow => '扩大时间窗口';
  @override
  String get removeIncludeTags => '移除包含标签';
  @override
  String get switchScopeToAll => '切换范围到全部';
}

// Path: attachments.content.speechTranscribeIssue
class _StringsAttachmentsContentSpeechTranscribeIssueZhCn
    extends _StringsAttachmentsContentSpeechTranscribeIssueEn {
  _StringsAttachmentsContentSpeechTranscribeIssueZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '语音转录暂不可用';
  @override
  String get openSettings => '打开系统设置';
  @override
  String get openSettingsFailed => '无法自动打开系统设置，请手动检查系统的语音识别权限与听写开关。';
  @override
  String get permissionDenied =>
      '语音识别权限被拒绝。请先点击“重试”再次触发系统授权弹窗；若仍被拦截，请前往系统设置开启权限。';
  @override
  String get permissionRestricted => '语音识别被系统策略限制。请检查屏幕使用时间或设备管理策略。';
  @override
  String get serviceDisabled => '系统“听写与 Siri”已关闭。请先启用后再重试。';
  @override
  String get runtimeUnavailable => '当前设备暂时无法使用语音识别运行时。请稍后重试。';
  @override
  String get permissionRequest => '本地语音转录需要语音识别权限。请点击“重试”，并在系统弹窗中允许授权。';
  @override
  String get offlineUnavailable => '当前设备或语言暂不支持离线语音识别。请先安装系统语音包，或切换到云端转录。';
}

// Path: attachments.content.videoInsights
class _StringsAttachmentsContentVideoInsightsZhCn
    extends _StringsAttachmentsContentVideoInsightsEn {
  _StringsAttachmentsContentVideoInsightsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsAttachmentsContentVideoInsightsContentKindZhCn
      contentKind =
      _StringsAttachmentsContentVideoInsightsContentKindZhCn._(_root);
  @override
  late final _StringsAttachmentsContentVideoInsightsDetailZhCn detail =
      _StringsAttachmentsContentVideoInsightsDetailZhCn._(_root);
  @override
  late final _StringsAttachmentsContentVideoInsightsFieldsZhCn fields =
      _StringsAttachmentsContentVideoInsightsFieldsZhCn._(_root);
}

// Path: sync.mediaBackup.cellularDialog
class _StringsSyncMediaBackupCellularDialogZhCn
    extends _StringsSyncMediaBackupCellularDialogEn {
  _StringsSyncMediaBackupCellularDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '使用蜂窝数据？';
  @override
  String get message => '已开启仅 Wi‑Fi。使用蜂窝数据上传可能消耗较多流量。';
  @override
  String get confirm => '仍然使用';
}

// Path: sync.localCache.dialog
class _StringsSyncLocalCacheDialogZhCn extends _StringsSyncLocalCacheDialogEn {
  _StringsSyncLocalCacheDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '清理本地存储？';
  @override
  String get message => '这将删除本机缓存的照片与文件，以节省本地空间。远端同步存储会保留副本；之后查看时会按需重新下载。';
  @override
  String get confirm => '清理';
}

// Path: sync.cloudManagedVault.switchDialog
class _StringsSyncCloudManagedVaultSwitchDialogZhCn
    extends _StringsSyncCloudManagedVaultSwitchDialogEn {
  _StringsSyncCloudManagedVaultSwitchDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '切换到 SecondLoop Cloud 同步？';
  @override
  String get message => '你的订阅已生效。是否将同步方式切换到 SecondLoop Cloud？你可以随时切换回来。';
  @override
  String get cancel => '暂不';
  @override
  String get confirm => '切换';
}

// Path: sync.cloudManagedVault.setPassphraseDialog
class _StringsSyncCloudManagedVaultSetPassphraseDialogZhCn
    extends _StringsSyncCloudManagedVaultSetPassphraseDialogEn {
  _StringsSyncCloudManagedVaultSetPassphraseDialogZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '设置同步口令';
  @override
  String get confirm => '保存口令';
}

// Path: sync.fields.baseUrl
class _StringsSyncFieldsBaseUrlZhCn extends _StringsSyncFieldsBaseUrlEn {
  _StringsSyncFieldsBaseUrlZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => '服务器地址';
  @override
  String get hint => 'https://example.com/dav';
}

// Path: sync.fields.username
class _StringsSyncFieldsUsernameZhCn extends _StringsSyncFieldsUsernameEn {
  _StringsSyncFieldsUsernameZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => '用户名（可选）';
}

// Path: sync.fields.password
class _StringsSyncFieldsPasswordZhCn extends _StringsSyncFieldsPasswordEn {
  _StringsSyncFieldsPasswordZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => '密码（可选）';
}

// Path: sync.fields.localDir
class _StringsSyncFieldsLocalDirZhCn extends _StringsSyncFieldsLocalDirEn {
  _StringsSyncFieldsLocalDirZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => '文件夹路径';
  @override
  String get hint => '/Users/me/SecondLoopVault';
  @override
  String get helper => '更适合桌面端；移动端可能不支持该路径。';
}

// Path: sync.fields.managedVaultBaseUrl
class _StringsSyncFieldsManagedVaultBaseUrlZhCn
    extends _StringsSyncFieldsManagedVaultBaseUrlEn {
  _StringsSyncFieldsManagedVaultBaseUrlZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Cloud 服务器地址（高级）';
  @override
  String get hint => 'https://vault.example.com';
}

// Path: sync.fields.vaultId
class _StringsSyncFieldsVaultIdZhCn extends _StringsSyncFieldsVaultIdEn {
  _StringsSyncFieldsVaultIdZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Cloud 账号 ID';
  @override
  String get hint => '自动填写';
}

// Path: sync.fields.remoteRoot
class _StringsSyncFieldsRemoteRootZhCn extends _StringsSyncFieldsRemoteRootEn {
  _StringsSyncFieldsRemoteRootZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => '文件夹名称';
  @override
  String get hint => 'SecondLoop';
}

// Path: sync.fields.passphrase
class _StringsSyncFieldsPassphraseZhCn extends _StringsSyncFieldsPassphraseEn {
  _StringsSyncFieldsPassphraseZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get label => '同步口令';
  @override
  String get helper => '所有设备请使用同一口令。口令不会被上传。';
}

// Path: embeddingProfiles.reindexDialog.actions
class _StringsEmbeddingProfilesReindexDialogActionsZhCn
    extends _StringsEmbeddingProfilesReindexDialogActionsEn {
  _StringsEmbeddingProfilesReindexDialogActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get continueLabel => '继续';
}

// Path: settings.aiSelection.askAi.status
class _StringsSettingsAiSelectionAskAiStatusZhCn
    extends _StringsSettingsAiSelectionAskAiStatusEn {
  _StringsSettingsAiSelectionAskAiStatusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '正在检查当前使用来源...';
  @override
  String get cloud => '当前使用：SecondLoop Cloud';
  @override
  String get byok => '当前使用：API 密钥（BYOK）';
  @override
  String get notConfigured => '当前使用：未完成设置';
}

// Path: settings.aiSelection.askAi.preference
class _StringsSettingsAiSelectionAskAiPreferenceZhCn
    extends _StringsSettingsAiSelectionAskAiPreferenceEn {
  _StringsSettingsAiSelectionAskAiPreferenceZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsAiSelectionAskAiPreferenceAutoZhCn auto =
      _StringsSettingsAiSelectionAskAiPreferenceAutoZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionAskAiPreferenceCloudZhCn cloud =
      _StringsSettingsAiSelectionAskAiPreferenceCloudZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionAskAiPreferenceByokZhCn byok =
      _StringsSettingsAiSelectionAskAiPreferenceByokZhCn._(_root);
}

// Path: settings.aiSelection.askAi.actions
class _StringsSettingsAiSelectionAskAiActionsZhCn
    extends _StringsSettingsAiSelectionAskAiActionsEn {
  _StringsSettingsAiSelectionAskAiActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openCloud => '打开 Cloud 账户';
  @override
  String get openByok => '打开 API 密钥';
}

// Path: settings.aiSelection.embeddings.status
class _StringsSettingsAiSelectionEmbeddingsStatusZhCn
    extends _StringsSettingsAiSelectionEmbeddingsStatusEn {
  _StringsSettingsAiSelectionEmbeddingsStatusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '正在检查当前使用来源...';
  @override
  String get cloud => '当前使用：SecondLoop Cloud';
  @override
  String get byok => '当前使用：API 密钥（Embedding/BYOK）';
  @override
  String get local => '当前使用：本机智能检索';
}

// Path: settings.aiSelection.embeddings.preference
class _StringsSettingsAiSelectionEmbeddingsPreferenceZhCn
    extends _StringsSettingsAiSelectionEmbeddingsPreferenceEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceAutoZhCn auto =
      _StringsSettingsAiSelectionEmbeddingsPreferenceAutoZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceCloudZhCn cloud =
      _StringsSettingsAiSelectionEmbeddingsPreferenceCloudZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceByokZhCn byok =
      _StringsSettingsAiSelectionEmbeddingsPreferenceByokZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionEmbeddingsPreferenceLocalZhCn local =
      _StringsSettingsAiSelectionEmbeddingsPreferenceLocalZhCn._(_root);
}

// Path: settings.aiSelection.embeddings.actions
class _StringsSettingsAiSelectionEmbeddingsActionsZhCn
    extends _StringsSettingsAiSelectionEmbeddingsActionsEn {
  _StringsSettingsAiSelectionEmbeddingsActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openEmbeddingProfiles => '打开向量 API 密钥';
  @override
  String get openCloudAccount => '打开 Cloud 账户';
}

// Path: settings.aiSelection.mediaUnderstanding.status
class _StringsSettingsAiSelectionMediaUnderstandingStatusZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingStatusEn {
  _StringsSettingsAiSelectionMediaUnderstandingStatusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '正在检查当前使用来源...';
  @override
  String get cloud => '当前使用：SecondLoop Cloud';
  @override
  String get byok => '当前使用：API 密钥（BYOK）';
  @override
  String get local => '当前使用：本机能力（系统自带）';
}

// Path: settings.aiSelection.mediaUnderstanding.preference
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingPreferenceEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoZhCn
      auto =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudZhCn
      cloud =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokZhCn
      byok =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokZhCn._(_root);
  @override
  late final _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalZhCn
      local =
      _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalZhCn._(_root);
}

// Path: settings.aiSelection.mediaUnderstanding.actions
class _StringsSettingsAiSelectionMediaUnderstandingActionsZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingActionsEn {
  _StringsSettingsAiSelectionMediaUnderstandingActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openSettings => '打开媒体理解设置';
  @override
  String get openCloudAccount => '打开 Cloud 账户';
  @override
  String get openByok => '打开 API 密钥';
}

// Path: settings.mediaAnnotation.documentOcr.enabled
class _StringsSettingsMediaAnnotationDocumentOcrEnabledZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrEnabledEn {
  _StringsSettingsMediaAnnotationDocumentOcrEnabledZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '启用 OCR';
  @override
  String get subtitle => '当文档文本提取不足时，对扫描 PDF 和视频关键帧执行 OCR。';
}

// Path: settings.mediaAnnotation.documentOcr.languageHints
class _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '语言提示';
  @override
  String get subtitle => '选择 OCR 识别优先语言。';
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsZhCn
      labels =
      _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsZhCn._(
          _root);
}

// Path: settings.mediaAnnotation.documentOcr.pdfAutoMaxPages
class _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesEn {
  _StringsSettingsMediaAnnotationDocumentOcrPdfAutoMaxPagesZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '自动 OCR 页数上限';
  @override
  String get subtitle => '超过该页数的 PDF 会保持 needs_ocr，需在查看页手动执行。';
  @override
  String get manualOnly => '仅手动';
  @override
  String pages({required Object count}) => '${count} 页';
}

// Path: settings.mediaAnnotation.documentOcr.pdfDpi
class _StringsSettingsMediaAnnotationDocumentOcrPdfDpiZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrPdfDpiEn {
  _StringsSettingsMediaAnnotationDocumentOcrPdfDpiZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'OCR DPI';
  @override
  String get subtitle => '更高 DPI 可能提升识别率，但处理更慢。';
  @override
  String value({required Object dpi}) => '${dpi} dpi';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '桌面 OCR 模型';
  @override
  String get subtitle => '为桌面端（Linux/macOS/Windows）下载本地 OCR 模型文件。';
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusZhCn
      status =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsZhCn
      actions =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteZhCn
      confirmDelete =
      _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteZhCn._(
          _root);
}

// Path: settings.mediaAnnotation.audioTranscribe.enabled
class _StringsSettingsMediaAnnotationAudioTranscribeEnabledZhCn
    extends _StringsSettingsMediaAnnotationAudioTranscribeEnabledEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEnabledZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '转写音频附件';
  @override
  String get subtitle => '添加音频后，SecondLoop 可自动转写并保存加密文本，用于播放与搜索。';
}

// Path: settings.mediaAnnotation.audioTranscribe.engine
class _StringsSettingsMediaAnnotationAudioTranscribeEngineZhCn
    extends _StringsSettingsMediaAnnotationAudioTranscribeEngineEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEngineZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '转写引擎';
  @override
  String get subtitle => '选择音频转写使用的引擎。';
  @override
  String get notAvailable => '不可用';
  @override
  late final _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsZhCn
      labels =
      _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsZhCn._(_root);
  @override
  late final _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsZhCn
      descriptions =
      _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsZhCn._(
          _root);
}

// Path: settings.mediaAnnotation.audioTranscribe.configureApi
class _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiZhCn
    extends _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiEn {
  _StringsSettingsMediaAnnotationAudioTranscribeConfigureApiZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '配置转写 API';
  @override
  String get subtitle =>
      'Pro 用户可用 SecondLoop Cloud；免费用户可用「AI 对话」中的 OpenAI-compatible API Key 配置档。';
  @override
  String get body =>
      '音频转写可使用 SecondLoop Cloud（需要 Pro + 登录）或“AI 对话”里的 OpenAI-compatible API Key 配置档。';
  @override
  String get openCloud => '打开 Cloud 账号';
  @override
  String get openApiKeys => '打开 API Key';
}

// Path: settings.mediaAnnotation.setupRequired.reasons
class _StringsSettingsMediaAnnotationSetupRequiredReasonsZhCn
    extends _StringsSettingsMediaAnnotationSetupRequiredReasonsEn {
  _StringsSettingsMediaAnnotationSetupRequiredReasonsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get cloudUnavailable => '当前构建未启用 SecondLoop Cloud。';
  @override
  String get cloudRequiresPro => 'SecondLoop Cloud 需要 Pro。';
  @override
  String get cloudSignIn => '请先登录 SecondLoop Cloud。';
  @override
  String get byokOpenAiCompatible => '请先添加 OpenAI-compatible 的 API Key 配置档。';
  @override
  String get followAskAi =>
      '“AI 对话”需要使用 OpenAI-compatible 配置档，或在高级设置里选择其它多模态模型。';
}

// Path: settings.mediaAnnotation.providerMode.labels
class _StringsSettingsMediaAnnotationProviderModeLabelsZhCn
    extends _StringsSettingsMediaAnnotationProviderModeLabelsEn {
  _StringsSettingsMediaAnnotationProviderModeLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get followAskAi => '跟随 AI 对话';
  @override
  String get cloudGateway => 'SecondLoop Cloud';
  @override
  String get byokProfile => 'API Key（配置档）';
}

// Path: settings.mediaAnnotation.providerMode.descriptions
class _StringsSettingsMediaAnnotationProviderModeDescriptionsZhCn
    extends _StringsSettingsMediaAnnotationProviderModeDescriptionsEn {
  _StringsSettingsMediaAnnotationProviderModeDescriptionsZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get followAskAi => '使用与“AI 对话”相同的设置（推荐）。';
  @override
  String get cloudGateway => '优先使用 SecondLoop Cloud（需要 Pro，且需可用）。';
  @override
  String get byokProfile => '使用指定的 API Key 配置档（仅支持 OpenAI-compatible）。';
}

// Path: settings.cloudAccount.benefits.items
class _StringsSettingsCloudAccountBenefitsItemsZhCn
    extends _StringsSettingsCloudAccountBenefitsItemsEn {
  _StringsSettingsCloudAccountBenefitsItemsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsCloudAccountBenefitsItemsPurchaseZhCn purchase =
      _StringsSettingsCloudAccountBenefitsItemsPurchaseZhCn._(_root);
}

// Path: settings.cloudAccount.emailVerification.status
class _StringsSettingsCloudAccountEmailVerificationStatusZhCn
    extends _StringsSettingsCloudAccountEmailVerificationStatusEn {
  _StringsSettingsCloudAccountEmailVerificationStatusZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get unknown => '未知';
  @override
  String get verified => '已验证';
  @override
  String get notVerified => '未验证';
}

// Path: settings.cloudAccount.emailVerification.labels
class _StringsSettingsCloudAccountEmailVerificationLabelsZhCn
    extends _StringsSettingsCloudAccountEmailVerificationLabelsEn {
  _StringsSettingsCloudAccountEmailVerificationLabelsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get status => '状态：';
  @override
  String get help => '验证邮箱后才能使用 SecondLoop Cloud 的 AI 对话。';
  @override
  String get verifiedHelp => '邮箱已验证，可继续订阅。';
  @override
  String loadFailed({required Object error}) => '加载失败：${error}';
}

// Path: settings.cloudAccount.emailVerification.actions
class _StringsSettingsCloudAccountEmailVerificationActionsZhCn
    extends _StringsSettingsCloudAccountEmailVerificationActionsEn {
  _StringsSettingsCloudAccountEmailVerificationActionsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get resend => '重新发送验证邮件';
  @override
  String resendCooldown({required Object seconds}) => '${seconds} 秒后可重新发送';
}

// Path: settings.cloudAccount.emailVerification.messages
class _StringsSettingsCloudAccountEmailVerificationMessagesZhCn
    extends _StringsSettingsCloudAccountEmailVerificationMessagesEn {
  _StringsSettingsCloudAccountEmailVerificationMessagesZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get verificationEmailSent => '验证邮件已发送';
  @override
  String get verificationAlreadyDone => '邮箱已完成验证。';
  @override
  String get signUpVerificationPrompt => '账号已创建，请先完成邮箱验证再进行订阅。';
  @override
  String verificationEmailSendFailed({required Object error}) =>
      '发送验证邮件失败：${error}';
}

// Path: settings.subscription.benefits.items
class _StringsSettingsSubscriptionBenefitsItemsZhCn
    extends _StringsSettingsSubscriptionBenefitsItemsEn {
  _StringsSettingsSubscriptionBenefitsItemsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  late final _StringsSettingsSubscriptionBenefitsItemsNoSetupZhCn noSetup =
      _StringsSettingsSubscriptionBenefitsItemsNoSetupZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionBenefitsItemsCloudSyncZhCn cloudSync =
      _StringsSettingsSubscriptionBenefitsItemsCloudSyncZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionBenefitsItemsMobileSearchZhCn
      mobileSearch =
      _StringsSettingsSubscriptionBenefitsItemsMobileSearchZhCn._(_root);
}

// Path: attachments.content.videoInsights.contentKind
class _StringsAttachmentsContentVideoInsightsContentKindZhCn
    extends _StringsAttachmentsContentVideoInsightsContentKindEn {
  _StringsAttachmentsContentVideoInsightsContentKindZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get knowledge => '知识类视频';
  @override
  String get nonKnowledge => '非知识类视频';
  @override
  String get unknown => '未知';
}

// Path: attachments.content.videoInsights.detail
class _StringsAttachmentsContentVideoInsightsDetailZhCn
    extends _StringsAttachmentsContentVideoInsightsDetailEn {
  _StringsAttachmentsContentVideoInsightsDetailZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get knowledgeMarkdown => '知识文稿';
  @override
  String get videoDescription => '视频描述';
  @override
  String get extractedContent => '提取内容';
}

// Path: attachments.content.videoInsights.fields
class _StringsAttachmentsContentVideoInsightsFieldsZhCn
    extends _StringsAttachmentsContentVideoInsightsFieldsEn {
  _StringsAttachmentsContentVideoInsightsFieldsZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get contentType => '内容类型';
  @override
  String get segments => '分段处理';
  @override
  String get summary => '视频概要';
}

// Path: settings.aiSelection.askAi.preference.auto
class _StringsSettingsAiSelectionAskAiPreferenceAutoZhCn
    extends _StringsSettingsAiSelectionAskAiPreferenceAutoEn {
  _StringsSettingsAiSelectionAskAiPreferenceAutoZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '自动';
  @override
  String get description => '自动选择可用服务：优先 Cloud，不可用时改用 API 密钥（BYOK）。';
}

// Path: settings.aiSelection.askAi.preference.cloud
class _StringsSettingsAiSelectionAskAiPreferenceCloudZhCn
    extends _StringsSettingsAiSelectionAskAiPreferenceCloudEn {
  _StringsSettingsAiSelectionAskAiPreferenceCloudZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'SecondLoop Cloud';
  @override
  String get description => '固定使用 Cloud。Cloud 不可用时，“AI 对话”会暂时不可用。';
}

// Path: settings.aiSelection.askAi.preference.byok
class _StringsSettingsAiSelectionAskAiPreferenceByokZhCn
    extends _StringsSettingsAiSelectionAskAiPreferenceByokEn {
  _StringsSettingsAiSelectionAskAiPreferenceByokZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API 密钥（BYOK）';
  @override
  String get description => '固定使用你自己的 API 密钥（BYOK）。没有可用配置时，“AI 对话”会暂时不可用。';
}

// Path: settings.aiSelection.embeddings.preference.auto
class _StringsSettingsAiSelectionEmbeddingsPreferenceAutoZhCn
    extends _StringsSettingsAiSelectionEmbeddingsPreferenceAutoEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceAutoZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '自动';
  @override
  String get description => '自动选择：优先 Cloud，其次 API 密钥（BYOK），最后本机能力。';
}

// Path: settings.aiSelection.embeddings.preference.cloud
class _StringsSettingsAiSelectionEmbeddingsPreferenceCloudZhCn
    extends _StringsSettingsAiSelectionEmbeddingsPreferenceCloudEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceCloudZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'SecondLoop Cloud';
  @override
  String get description => '优先使用 Cloud。Cloud 不可用时自动切换到 API 密钥或本机能力。';
}

// Path: settings.aiSelection.embeddings.preference.byok
class _StringsSettingsAiSelectionEmbeddingsPreferenceByokZhCn
    extends _StringsSettingsAiSelectionEmbeddingsPreferenceByokEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceByokZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API 密钥（BYOK）';
  @override
  String get description => '优先使用 API 密钥（BYOK）。失败时自动切换到本机能力。';
}

// Path: settings.aiSelection.embeddings.preference.local
class _StringsSettingsAiSelectionEmbeddingsPreferenceLocalZhCn
    extends _StringsSettingsAiSelectionEmbeddingsPreferenceLocalEn {
  _StringsSettingsAiSelectionEmbeddingsPreferenceLocalZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '本地能力';
  @override
  String get description => '尽量只在本机生成检索索引（Embedding）。';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.auto
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceAutoZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '自动';
  @override
  String get description => '自动选择：优先 Cloud，其次 API 密钥（BYOK），最后本机能力。';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.cloud
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceCloudZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'SecondLoop Cloud';
  @override
  String get description => '优先使用 Cloud。Cloud 不可用时自动切换到 API 密钥或本机能力。';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.byok
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceByokZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'API 密钥（BYOK）';
  @override
  String get description => '优先使用 API 密钥（BYOK）。失败时自动切换到本机能力。';
}

// Path: settings.aiSelection.mediaUnderstanding.preference.local
class _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalZhCn
    extends _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalEn {
  _StringsSettingsAiSelectionMediaUnderstandingPreferenceLocalZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '本地能力';
  @override
  String get description => '优先使用本机能力（系统自带）。';
}

// Path: settings.mediaAnnotation.documentOcr.languageHints.labels
class _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLanguageHintsLabelsZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get devicePlusEn => '设备语言 + 英文';
  @override
  String get en => '英文';
  @override
  String get zhEn => '中文 + 英文';
  @override
  String get jaEn => '日文 + 英文';
  @override
  String get koEn => '韩文 + 英文';
  @override
  String get frEn => '法文 + 英文';
  @override
  String get deEn => '德文 + 英文';
  @override
  String get esEn => '西班牙文 + 英文';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels.status
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsStatusZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get notInstalled => '未安装';
  @override
  String get runtimeMissing => '模型已下载，但 OCR 运行环境未就绪';
  @override
  String get downloading => '下载中...';
  @override
  String installed({required Object count, required Object size}) =>
      '已安装：${count} 个文件（${size}）';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels.actions
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsActionsZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get download => '下载模型';
  @override
  String get redownload => '重新下载';
  @override
  String get delete => '删除模型';
}

// Path: settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete
class _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteZhCn
    extends _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteEn {
  _StringsSettingsMediaAnnotationDocumentOcrLinuxModelsConfirmDeleteZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '删除已下载 OCR 模型？';
  @override
  String get body => '删除后，桌面端本地 OCR 可能不可用，直到再次下载。';
  @override
  String get confirm => '删除';
}

// Path: settings.mediaAnnotation.audioTranscribe.engine.labels
class _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsZhCn
    extends _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEngineLabelsZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get whisper => 'Whisper';
  @override
  String get multimodalLlm => '多模态 LLM';
  @override
  String get auto => '自动';
}

// Path: settings.mediaAnnotation.audioTranscribe.engine.descriptions
class _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsZhCn
    extends _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsEn {
  _StringsSettingsMediaAnnotationAudioTranscribeEngineDescriptionsZhCn._(
      _StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get whisper => '语音转写稳定默认方案（推荐）。';
  @override
  String get multimodalLlm => '可用时使用多模态聊天模型。';
  @override
  String get auto => '由 SecondLoop 自动选择最可用的引擎。';
}

// Path: settings.cloudAccount.benefits.items.purchase
class _StringsSettingsCloudAccountBenefitsItemsPurchaseZhCn
    extends _StringsSettingsCloudAccountBenefitsItemsPurchaseEn {
  _StringsSettingsCloudAccountBenefitsItemsPurchaseZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '购买 SecondLoop Pro 订阅';
  @override
  String get body => '需要 Cloud 账号才能开通订阅。';
}

// Path: settings.subscription.benefits.items.noSetup
class _StringsSettingsSubscriptionBenefitsItemsNoSetupZhCn
    extends _StringsSettingsSubscriptionBenefitsItemsNoSetupEn {
  _StringsSettingsSubscriptionBenefitsItemsNoSetupZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '免配置直接用 AI';
  @override
  String get body => '不用做任何配置，订阅后就能直接使用 AI 对话。';
}

// Path: settings.subscription.benefits.items.cloudSync
class _StringsSettingsSubscriptionBenefitsItemsCloudSyncZhCn
    extends _StringsSettingsSubscriptionBenefitsItemsCloudSyncEn {
  _StringsSettingsSubscriptionBenefitsItemsCloudSyncZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '云存储 + 多设备同步';
  @override
  String get body => '手机/电脑自动同步，换设备也不丢。';
}

// Path: settings.subscription.benefits.items.mobileSearch
class _StringsSettingsSubscriptionBenefitsItemsMobileSearchZhCn
    extends _StringsSettingsSubscriptionBenefitsItemsMobileSearchEn {
  _StringsSettingsSubscriptionBenefitsItemsMobileSearchZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '手机也能按意思搜索';
  @override
  String get body => '就算记不住原话，用相近的说法也能搜到。';
}

/// Flat map(s) containing all translations.
/// Only for edge cases! For simple maps, use the map function of this library.

extension on Translations {
  dynamic _flatMapFunction(String path) {
    switch (path) {
      case 'app.title':
        return 'SecondLoop';
      case 'app.tabs.main':
        return 'Main';
      case 'app.tabs.settings':
        return 'Settings';
      case 'common.actions.cancel':
        return 'Cancel';
      case 'common.actions.notNow':
        return 'Not now';
      case 'common.actions.allow':
        return 'Allow';
      case 'common.actions.save':
        return 'Save';
      case 'common.actions.copy':
        return 'Copy';
      case 'common.actions.reset':
        return 'Reset';
      case 'common.actions.continueLabel':
        return 'Continue';
      case 'common.actions.send':
        return 'Send';
      case 'common.actions.askAi':
        return 'Ask AI';
      case 'common.actions.configureAi':
        return 'Configure AI';
      case 'common.actions.stop':
        return 'Stop';
      case 'common.actions.stopping':
        return 'Stopping…';
      case 'common.actions.edit':
        return 'Edit';
      case 'common.actions.delete':
        return 'Delete';
      case 'common.actions.undo':
        return 'Undo';
      case 'common.actions.open':
        return 'Open';
      case 'common.actions.retry':
        return 'Retry';
      case 'common.actions.ignore':
        return 'Ignore';
      case 'common.actions.refresh':
        return 'Refresh';
      case 'common.actions.share':
        return 'Share';
      case 'common.actions.search':
        return 'Search';
      case 'common.actions.useModel':
        return 'Use model';
      case 'common.actions.processPending':
        return 'Process pending';
      case 'common.actions.rebuildEmbeddings':
        return 'Rebuild embeddings';
      case 'common.actions.push':
        return 'Upload';
      case 'common.actions.pull':
        return 'Download';
      case 'common.actions.lockNow':
        return 'Lock now';
      case 'common.fields.masterPassword':
        return 'Master password';
      case 'common.fields.confirm':
        return 'Confirm';
      case 'common.fields.message':
        return 'Message';
      case 'common.fields.quickCapture':
        return 'Quick capture';
      case 'common.fields.query':
        return 'Query';
      case 'common.labels.elapsedSeconds':
        return ({required Object seconds}) => 'Elapsed: ${seconds}s';
      case 'common.labels.topK':
        return 'Top‑K:';
      case 'errors.initFailed':
        return ({required Object error}) => 'Init failed: ${error}';
      case 'errors.loadFailed':
        return ({required Object error}) => 'Load failed: ${error}';
      case 'errors.saveFailed':
        return ({required Object error}) => 'Save failed: ${error}';
      case 'errors.lockGateError':
        return ({required Object error}) => 'LockGate error: ${error}';
      case 'errors.missingMainStream':
        return 'Missing Main Stream';
      case 'actions.capture.title':
        return 'Turn this into a reminder?';
      case 'actions.capture.pickTime':
        return 'Pick a time';
      case 'actions.capture.reviewLater':
        return 'Remind me to confirm later';
      case 'actions.capture.justSave':
        return 'Just save as note';
      case 'actions.reviewQueue.title':
        return 'Needs confirmation';
      case 'actions.reviewQueue.banner':
        return ({required Object count}) => '${count} items need confirmation';
      case 'actions.reviewQueue.empty':
        return 'No items to confirm';
      case 'actions.reviewQueue.snoozedUntil':
        return ({required Object when}) => 'Snoozed until ${when}';
      case 'actions.reviewQueue.inAppFallback.message':
        return ({required Object count}) =>
            '${count} items are waiting in your review queue';
      case 'actions.reviewQueue.inAppFallback.open':
        return 'Open review queue';
      case 'actions.reviewQueue.inAppFallback.dismiss':
        return 'Dismiss';
      case 'actions.reviewQueue.actions.schedule':
        return 'Schedule';
      case 'actions.reviewQueue.actions.snooze':
        return 'Tomorrow morning';
      case 'actions.reviewQueue.actions.start':
        return 'Start';
      case 'actions.reviewQueue.actions.done':
        return 'Done';
      case 'actions.reviewQueue.actions.dismiss':
        return 'Dismiss';
      case 'actions.todoStatus.inbox':
        return 'Needs confirmation';
      case 'actions.todoStatus.open':
        return 'Not started';
      case 'actions.todoStatus.inProgress':
        return 'In progress';
      case 'actions.todoStatus.done':
        return 'Done';
      case 'actions.todoStatus.dismissed':
        return 'Deleted';
      case 'actions.todoLink.title':
        return 'Update a task?';
      case 'actions.todoLink.subtitle':
        return ({required Object status}) => 'Mark as: ${status}';
      case 'actions.todoLink.updated':
        return ({required Object title, required Object status}) =>
            'Updated "${title}" → ${status}';
      case 'actions.todoNoteLink.action':
        return 'Link to task';
      case 'actions.todoNoteLink.actionShort':
        return 'Link';
      case 'actions.todoNoteLink.title':
        return 'Link to which task?';
      case 'actions.todoNoteLink.subtitle':
        return 'Add this message as a follow-up note';
      case 'actions.todoNoteLink.noMatches':
        return 'No matching tasks';
      case 'actions.todoNoteLink.suggest':
        return 'Link this message to a task?';
      case 'actions.todoNoteLink.linked':
        return ({required Object title}) => 'Linked to "${title}"';
      case 'actions.todoAuto.created':
        return ({required Object title}) => 'Created "${title}"';
      case 'actions.todoDetail.title':
        return 'Task';
      case 'actions.todoDetail.emptyTimeline':
        return 'No updates yet';
      case 'actions.todoDetail.noteHint':
        return 'Add a note…';
      case 'actions.todoDetail.addNote':
        return 'Add';
      case 'actions.todoDetail.attach':
        return 'Attach';
      case 'actions.todoDetail.pickAttachment':
        return 'Choose an attachment';
      case 'actions.todoDetail.noAttachments':
        return 'No attachments yet';
      case 'actions.todoDetail.attachmentNoteDefault':
        return 'Added attachment';
      case 'actions.todoDelete.dialog.title':
        return 'Delete task?';
      case 'actions.todoDelete.dialog.message':
        return 'This will permanently delete this task and all linked chat messages.';
      case 'actions.todoDelete.dialog.confirm':
        return 'Delete';
      case 'actions.todoRecurrenceEditScope.title':
        return 'Apply changes to recurring task';
      case 'actions.todoRecurrenceEditScope.message':
        return 'How should this change be applied?';
      case 'actions.todoRecurrenceEditScope.thisOnly':
        return 'This occurrence only';
      case 'actions.todoRecurrenceEditScope.thisAndFuture':
        return 'This and future';
      case 'actions.todoRecurrenceEditScope.wholeSeries':
        return 'Whole series';
      case 'actions.todoRecurrenceRule.title':
        return 'Edit recurrence';
      case 'actions.todoRecurrenceRule.edit':
        return 'Recurrence';
      case 'actions.todoRecurrenceRule.frequencyLabel':
        return 'Frequency';
      case 'actions.todoRecurrenceRule.intervalLabel':
        return 'Interval';
      case 'actions.todoRecurrenceRule.daily':
        return 'Daily';
      case 'actions.todoRecurrenceRule.weekly':
        return 'Weekly';
      case 'actions.todoRecurrenceRule.monthly':
        return 'Monthly';
      case 'actions.todoRecurrenceRule.yearly':
        return 'Yearly';
      case 'actions.history.title':
        return 'History';
      case 'actions.history.empty':
        return 'No activity in this range';
      case 'actions.history.presets.thisWeek':
        return 'This week';
      case 'actions.history.presets.lastWeek':
        return 'Last week';
      case 'actions.history.presets.lastTwoWeeks':
        return 'Last 2 weeks';
      case 'actions.history.presets.custom':
        return 'Custom range';
      case 'actions.history.actions.copy':
        return 'Copy';
      case 'actions.history.actions.copied':
        return 'Copied';
      case 'actions.history.sections.created':
        return 'Created';
      case 'actions.history.sections.started':
        return 'Started';
      case 'actions.history.sections.done':
        return 'Done';
      case 'actions.history.sections.dismissed':
        return 'Dismissed';
      case 'actions.agenda.title':
        return 'Tasks';
      case 'actions.agenda.summary':
        return ({required Object due, required Object overdue}) =>
            'Today ${due} • Overdue ${overdue}';
      case 'actions.agenda.upcomingSummary':
        return ({required Object count}) => 'Upcoming ${count}';
      case 'actions.agenda.viewAll':
        return 'View all';
      case 'actions.agenda.empty':
        return 'No scheduled tasks';
      case 'actions.calendar.title':
        return 'Add to calendar?';
      case 'actions.calendar.pickTime':
        return 'Pick a start time';
      case 'actions.calendar.noAutoTime':
        return 'No suggested time found';
      case 'actions.calendar.pickCustom':
        return 'Pick date & time';
      case 'settings.title':
        return 'Settings';
      case 'settings.sections.appearance':
        return 'Appearance';
      case 'settings.sections.security':
        return 'Security';
      case 'settings.sections.cloud':
        return 'SecondLoop Cloud';
      case 'settings.sections.aiAdvanced':
        return 'Advanced (API keys)';
      case 'settings.sections.storage':
        return 'Sync & storage';
      case 'settings.sections.actions':
        return 'Actions';
      case 'settings.sections.support':
        return 'Help & support';
      case 'settings.sections.debug':
        return 'Debug';
      case 'settings.actionsReview.morningTime.title':
        return 'Morning review time';
      case 'settings.actionsReview.morningTime.subtitle':
        return 'Default reminder time for unplanned tasks';
      case 'settings.actionsReview.dayEndTime.title':
        return 'Day end time';
      case 'settings.actionsReview.dayEndTime.subtitle':
        return 'If not handled by this time, reminders back off';
      case 'settings.actionsReview.weeklyTime.title':
        return 'Weekly review time';
      case 'settings.actionsReview.weeklyTime.subtitle':
        return 'Weekly reminder time (Sunday)';
      case 'settings.actionsReview.inAppFallback.title':
        return 'In-app reminders';
      case 'settings.actionsReview.inAppFallback.subtitle':
        return 'Show todo notifications in app';
      case 'settings.quickCaptureHotkey.title':
        return 'Quick capture shortcut';
      case 'settings.quickCaptureHotkey.subtitle':
        return 'Global shortcut to open Quick capture';
      case 'settings.quickCaptureHotkey.dialogTitle':
        return 'Quick capture shortcut';
      case 'settings.quickCaptureHotkey.dialogBody':
        return 'Press a key combination to record a new shortcut.';
      case 'settings.quickCaptureHotkey.saved':
        return 'Quick capture shortcut updated';
      case 'settings.quickCaptureHotkey.actions.resetDefault':
        return 'Reset to default';
      case 'settings.quickCaptureHotkey.validation.missingModifier':
        return 'Use at least one modifier key (Ctrl/Alt/Shift/etc.)';
      case 'settings.quickCaptureHotkey.validation.modifierOnly':
        return 'Shortcut must include a non-modifier key.';
      case 'settings.quickCaptureHotkey.validation.systemConflict':
        return ({required Object name}) =>
            'Conflicts with system shortcut: ${name}';
      case 'settings.quickCaptureHotkey.conflicts.macosSpotlight':
        return 'Spotlight';
      case 'settings.quickCaptureHotkey.conflicts.macosFinderSearch':
        return 'Finder search';
      case 'settings.quickCaptureHotkey.conflicts.macosInputSourceSwitch':
        return 'Switch input source';
      case 'settings.quickCaptureHotkey.conflicts.macosEmojiPicker':
        return 'Emoji & Symbols';
      case 'settings.quickCaptureHotkey.conflicts.macosScreenshot':
        return 'Screenshot';
      case 'settings.quickCaptureHotkey.conflicts.macosAppSwitcher':
        return 'App switcher';
      case 'settings.quickCaptureHotkey.conflicts.macosForceQuit':
        return 'Force Quit';
      case 'settings.quickCaptureHotkey.conflicts.macosLockScreen':
        return 'Lock screen';
      case 'settings.quickCaptureHotkey.conflicts.windowsLock':
        return 'Lock screen';
      case 'settings.quickCaptureHotkey.conflicts.windowsShowDesktop':
        return 'Show desktop';
      case 'settings.quickCaptureHotkey.conflicts.windowsFileExplorer':
        return 'File Explorer';
      case 'settings.quickCaptureHotkey.conflicts.windowsRun':
        return 'Run';
      case 'settings.quickCaptureHotkey.conflicts.windowsSearch':
        return 'Search';
      case 'settings.quickCaptureHotkey.conflicts.windowsSettings':
        return 'Settings';
      case 'settings.quickCaptureHotkey.conflicts.windowsTaskView':
        return 'Task view';
      case 'settings.quickCaptureHotkey.conflicts.windowsLanguageSwitch':
        return 'Switch input language';
      case 'settings.quickCaptureHotkey.conflicts.windowsAppSwitcher':
        return 'App switcher';
      case 'settings.desktopBoot.startWithSystem.title':
        return 'Start with system';
      case 'settings.desktopBoot.startWithSystem.subtitle':
        return 'Launch SecondLoop automatically after sign-in';
      case 'settings.desktopBoot.silentStartup.title':
        return 'Silent startup';
      case 'settings.desktopBoot.silentStartup.subtitle':
        return 'When auto-starting, run in background without showing a window';
      case 'settings.desktopBoot.keepRunningInBackground.title':
        return 'Keep running in background';
      case 'settings.desktopBoot.keepRunningInBackground.subtitle':
        return 'When closing the window, minimize to tray instead of quitting';
      case 'settings.desktopTray.menu.hide':
        return 'Hide';
      case 'settings.desktopTray.menu.quit':
        return 'Quit';
      case 'settings.desktopTray.pro.signedIn':
        return 'Signed in';
      case 'settings.desktopTray.pro.aiUsage':
        return 'AI usage';
      case 'settings.desktopTray.pro.storageUsage':
        return 'Storage usage';
      case 'settings.language.title':
        return 'Language';
      case 'settings.language.subtitle':
        return 'Follow system or choose a language';
      case 'settings.language.dialogTitle':
        return 'Language';
      case 'settings.language.options.system':
        return 'System';
      case 'settings.language.options.systemWithValue':
        return ({required Object value}) => 'System (${value})';
      case 'settings.language.options.en':
        return 'English';
      case 'settings.language.options.zhCn':
        return 'Simplified Chinese';
      case 'settings.theme.title':
        return 'Theme';
      case 'settings.theme.subtitle':
        return 'Follow system, or choose light/dark';
      case 'settings.theme.dialogTitle':
        return 'Theme';
      case 'settings.theme.options.system':
        return 'System';
      case 'settings.theme.options.light':
        return 'Light';
      case 'settings.theme.options.dark':
        return 'Dark';
      case 'settings.autoLock.title':
        return 'Auto lock';
      case 'settings.autoLock.subtitle':
        return 'Require unlock to access the app';
      case 'settings.systemUnlock.titleMobile':
        return 'Use biometrics';
      case 'settings.systemUnlock.titleDesktop':
        return 'Use system unlock';
      case 'settings.systemUnlock.subtitleMobile':
        return 'Unlock with biometrics instead of master password';
      case 'settings.systemUnlock.subtitleDesktop':
        return 'Unlock with Touch ID / Windows Hello instead of master password';
      case 'settings.lockNow.title':
        return 'Lock now';
      case 'settings.lockNow.subtitle':
        return 'Return to the unlock screen';
      case 'settings.llmProfiles.title':
        return 'API keys (Ask AI)';
      case 'settings.llmProfiles.subtitle':
        return 'Advanced: use your own provider and key';
      case 'settings.embeddingProfiles.title':
        return 'API keys (Semantic search)';
      case 'settings.embeddingProfiles.subtitle':
        return 'Advanced: use your own provider and key';
      case 'settings.aiSelection.title':
        return 'Intelligence';
      case 'settings.aiSelection.subtitle':
        return 'Unified settings for Ask AI, embeddings, OCR, speech recognition, and image understanding.';
      case 'settings.aiSelection.askAi.title':
        return 'Ask AI';
      case 'settings.aiSelection.askAi.description':
        return 'Chat assistant provider for your messages and memory.';
      case 'settings.aiSelection.askAi.setupHint':
        return 'Ask AI is not configured yet. Open Cloud account or add an API key profile to continue.';
      case 'settings.aiSelection.askAi.preferenceUnavailableHint':
        return 'The selected Ask AI source is unavailable. Open Cloud account or API keys to finish setup.';
      case 'settings.aiSelection.askAi.status.loading':
        return 'Checking current route...';
      case 'settings.aiSelection.askAi.status.cloud':
        return 'Current route: SecondLoop Cloud';
      case 'settings.aiSelection.askAi.status.byok':
        return 'Current route: API key profile (BYOK)';
      case 'settings.aiSelection.askAi.status.notConfigured':
        return 'Current route: setup required';
      case 'settings.aiSelection.askAi.preference.auto.title':
        return 'Auto';
      case 'settings.aiSelection.askAi.preference.auto.description':
        return 'Prefer Cloud when available, otherwise use BYOK.';
      case 'settings.aiSelection.askAi.preference.cloud.title':
        return 'SecondLoop Cloud';
      case 'settings.aiSelection.askAi.preference.cloud.description':
        return 'Use Cloud only. Ask AI stays unavailable until Cloud is ready.';
      case 'settings.aiSelection.askAi.preference.byok.title':
        return 'API key (BYOK)';
      case 'settings.aiSelection.askAi.preference.byok.description':
        return 'Use BYOK only. Ask AI stays unavailable until an active profile exists.';
      case 'settings.aiSelection.askAi.actions.openCloud':
        return 'Open Cloud account';
      case 'settings.aiSelection.askAi.actions.openByok':
        return 'Open API keys';
      case 'settings.aiSelection.embeddings.title':
        return 'Semantic search & embeddings';
      case 'settings.aiSelection.embeddings.description':
        return 'Used for recall, todo linking, and Ask AI retrieval quality.';
      case 'settings.aiSelection.embeddings.preferenceUnavailableHint':
        return 'Selected embeddings source is unavailable. Running on fallback route.';
      case 'settings.aiSelection.embeddings.status.loading':
        return 'Checking current route...';
      case 'settings.aiSelection.embeddings.status.cloud':
        return 'Current route: SecondLoop Cloud';
      case 'settings.aiSelection.embeddings.status.byok':
        return 'Current route: Embedding API key (BYOK)';
      case 'settings.aiSelection.embeddings.status.local':
        return 'Current route: Local embeddings runtime';
      case 'settings.aiSelection.embeddings.preference.auto.title':
        return 'Auto';
      case 'settings.aiSelection.embeddings.preference.auto.description':
        return 'Prefer Cloud, then BYOK, then local runtime.';
      case 'settings.aiSelection.embeddings.preference.cloud.title':
        return 'SecondLoop Cloud';
      case 'settings.aiSelection.embeddings.preference.cloud.description':
        return 'Prefer Cloud. If unavailable, fallback to BYOK or local runtime.';
      case 'settings.aiSelection.embeddings.preference.byok.title':
        return 'API key (BYOK)';
      case 'settings.aiSelection.embeddings.preference.byok.description':
        return 'Prefer BYOK. Automatically fallback to local runtime on failure.';
      case 'settings.aiSelection.embeddings.preference.local.title':
        return 'Local runtime';
      case 'settings.aiSelection.embeddings.preference.local.description':
        return 'Run embeddings only on local runtime when available.';
      case 'settings.aiSelection.embeddings.actions.openEmbeddingProfiles':
        return 'Open embedding API keys';
      case 'settings.aiSelection.embeddings.actions.openCloudAccount':
        return 'Open Cloud account';
      case 'settings.aiSelection.mediaUnderstanding.title':
        return 'Media understanding';
      case 'settings.aiSelection.mediaUnderstanding.description':
        return 'OCR, captions, and audio transcription source selection.';
      case 'settings.aiSelection.mediaUnderstanding.preferenceUnavailableHint':
        return 'Selected media source is unavailable. Running on fallback route.';
      case 'settings.aiSelection.mediaUnderstanding.status.loading':
        return 'Checking current route...';
      case 'settings.aiSelection.mediaUnderstanding.status.cloud':
        return 'Current route: SecondLoop Cloud';
      case 'settings.aiSelection.mediaUnderstanding.status.byok':
        return 'Current route: API key profile (BYOK)';
      case 'settings.aiSelection.mediaUnderstanding.status.local':
        return 'Current route: Local runtime/native capabilities';
      case 'settings.aiSelection.mediaUnderstanding.preference.auto.title':
        return 'Auto';
      case 'settings.aiSelection.mediaUnderstanding.preference.auto.description':
        return 'Prefer Cloud, then BYOK, then local capabilities.';
      case 'settings.aiSelection.mediaUnderstanding.preference.cloud.title':
        return 'SecondLoop Cloud';
      case 'settings.aiSelection.mediaUnderstanding.preference.cloud.description':
        return 'Prefer Cloud. If unavailable, fallback to BYOK or local capabilities.';
      case 'settings.aiSelection.mediaUnderstanding.preference.byok.title':
        return 'API key (BYOK)';
      case 'settings.aiSelection.mediaUnderstanding.preference.byok.description':
        return 'Prefer BYOK. Automatically fallback to local capabilities on failure.';
      case 'settings.aiSelection.mediaUnderstanding.preference.local.title':
        return 'Local capabilities';
      case 'settings.aiSelection.mediaUnderstanding.preference.local.description':
        return 'Prefer local runtime/native media understanding only.';
      case 'settings.aiSelection.mediaUnderstanding.actions.openSettings':
        return 'Open media understanding settings';
      case 'settings.aiSelection.mediaUnderstanding.actions.openCloudAccount':
        return 'Open Cloud account';
      case 'settings.aiSelection.mediaUnderstanding.actions.openByok':
        return 'Open API keys';
      case 'settings.semanticParseAutoActions.title':
        return 'Smarter semantic analysis';
      case 'settings.semanticParseAutoActions.subtitleEnabled':
        return 'Enhanced mode is on. Local semantic analysis stays on, and Cloud/BYOK improves automation quality.';
      case 'settings.semanticParseAutoActions.subtitleDisabled':
        return 'Enhanced mode is off. Local semantic analysis remains active.';
      case 'settings.semanticParseAutoActions.subtitleUnset':
        return 'Not set. Enhanced mode is off by default (local semantic analysis remains active).';
      case 'settings.semanticParseAutoActions.subtitleRequiresSetup':
        return 'Sign in with SecondLoop Pro or configure an API key (BYOK) to enable enhanced mode.';
      case 'settings.semanticParseAutoActions.dialogTitle':
        return 'Enable smarter semantic analysis?';
      case 'settings.semanticParseAutoActions.dialogBody':
        return 'Local semantic analysis is always on. When enhanced mode is enabled, SecondLoop may send message text to AI for smarter semantic parsing on top of local analysis.\n\nThe text is processed confidentially (not logged or stored). Your vault key and sync key are never uploaded.\n\nThis may use Cloud quota or your own provider quota.';
      case 'settings.semanticParseAutoActions.dialogActions.enable':
        return 'Enable';
      case 'settings.mediaAnnotation.title':
        return 'Media understanding';
      case 'settings.mediaAnnotation.subtitle':
        return 'Optional: OCR, image captions, and audio transcripts for better search/storage';
      case 'settings.mediaAnnotation.routingGuide.title':
        return 'Choose your AI source';
      case 'settings.mediaAnnotation.routingGuide.pro':
        return 'Pro + signed in: uses SecondLoop Cloud by default.';
      case 'settings.mediaAnnotation.routingGuide.byok':
        return 'Free/BYOK: add an OpenAI-compatible profile in Ask AI settings, then set it active.';
      case 'settings.mediaAnnotation.documentOcr.title':
        return 'Document OCR';
      case 'settings.mediaAnnotation.documentOcr.enabled.title':
        return 'Enable OCR';
      case 'settings.mediaAnnotation.documentOcr.enabled.subtitle':
        return 'Run OCR for scanned PDFs and video keyframes when text extraction is insufficient.';
      case 'settings.mediaAnnotation.documentOcr.languageHints.title':
        return 'Language hints';
      case 'settings.mediaAnnotation.documentOcr.languageHints.subtitle':
        return 'Choose preferred languages for OCR recognition.';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.devicePlusEn':
        return 'Device language + English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.en':
        return 'English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.zhEn':
        return 'Chinese + English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.jaEn':
        return 'Japanese + English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.koEn':
        return 'Korean + English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.frEn':
        return 'French + English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.deEn':
        return 'German + English';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.esEn':
        return 'Spanish + English';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.title':
        return 'Auto OCR page limit';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.subtitle':
        return 'PDFs above this limit stay in needs-OCR state until you run OCR manually in viewer.';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.manualOnly':
        return 'Manual only';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.pages':
        return ({required Object count}) => '${count} pages';
      case 'settings.mediaAnnotation.documentOcr.pdfDpi.title':
        return 'OCR DPI';
      case 'settings.mediaAnnotation.documentOcr.pdfDpi.subtitle':
        return 'Higher DPI may improve accuracy but costs more processing time.';
      case 'settings.mediaAnnotation.documentOcr.pdfDpi.value':
        return ({required Object dpi}) => '${dpi} dpi';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.title':
        return 'Desktop OCR models';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.subtitle':
        return 'Download local OCR model files for desktop (Linux/macOS/Windows).';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.notInstalled':
        return 'Not installed';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.runtimeMissing':
        return 'Models are downloaded, but OCR runtime is not ready';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.downloading':
        return 'Downloading...';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.installed':
        return ({required Object count, required Object size}) =>
            'Installed: ${count} files (${size})';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.actions.download':
        return 'Download models';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.actions.redownload':
        return 'Re-download';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.actions.delete':
        return 'Delete models';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete.title':
        return 'Delete downloaded OCR models?';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete.body':
        return 'Local desktop OCR may stop working until models are downloaded again.';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete.confirm':
        return 'Delete';
      case 'settings.mediaAnnotation.audioTranscribe.title':
        return 'Audio transcription';
      case 'settings.mediaAnnotation.audioTranscribe.enabled.title':
        return 'Transcribe audio attachments';
      case 'settings.mediaAnnotation.audioTranscribe.enabled.subtitle':
        return 'When you add audio, SecondLoop can transcribe it and save encrypted transcript text for playback and search.';
      case 'settings.mediaAnnotation.audioTranscribe.engine.title':
        return 'Transcription engine';
      case 'settings.mediaAnnotation.audioTranscribe.engine.subtitle':
        return 'Choose which engine to use for audio transcription.';
      case 'settings.mediaAnnotation.audioTranscribe.engine.notAvailable':
        return 'Unavailable';
      case 'settings.mediaAnnotation.audioTranscribe.engine.labels.whisper':
        return 'Whisper';
      case 'settings.mediaAnnotation.audioTranscribe.engine.labels.multimodalLlm':
        return 'Multimodal LLM';
      case 'settings.mediaAnnotation.audioTranscribe.engine.labels.auto':
        return 'Auto';
      case 'settings.mediaAnnotation.audioTranscribe.engine.descriptions.whisper':
        return 'Stable default for speech transcription. (Recommended)';
      case 'settings.mediaAnnotation.audioTranscribe.engine.descriptions.multimodalLlm':
        return 'Use a multimodal chat model when available.';
      case 'settings.mediaAnnotation.audioTranscribe.engine.descriptions.auto':
        return 'Let SecondLoop choose the best available engine.';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.title':
        return 'Configure transcription API';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.subtitle':
        return 'Pro users can use SecondLoop Cloud. Free users can use an OpenAI-compatible API key profile from Ask AI settings.';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.body':
        return 'Audio transcription can run with SecondLoop Cloud (requires Pro + sign-in) or an OpenAI-compatible API key profile from Ask AI settings.';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.openCloud':
        return 'Open Cloud account';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.openApiKeys':
        return 'Open API keys';
      case 'settings.mediaAnnotation.imageCaption.title':
        return 'Image captions';
      case 'settings.mediaAnnotation.providerSettings.title':
        return 'Image caption provider';
      case 'settings.mediaAnnotation.setupRequired.title':
        return 'Image annotations setup required';
      case 'settings.mediaAnnotation.setupRequired.body':
        return 'To annotate images, SecondLoop needs a multimodal model.';
      case 'settings.mediaAnnotation.setupRequired.reasons.cloudUnavailable':
        return 'SecondLoop Cloud is not available in this build.';
      case 'settings.mediaAnnotation.setupRequired.reasons.cloudRequiresPro':
        return 'SecondLoop Cloud requires Pro.';
      case 'settings.mediaAnnotation.setupRequired.reasons.cloudSignIn':
        return 'Sign in to SecondLoop Cloud to use the Cloud model.';
      case 'settings.mediaAnnotation.setupRequired.reasons.byokOpenAiCompatible':
        return 'Add an OpenAI‑compatible API key profile.';
      case 'settings.mediaAnnotation.setupRequired.reasons.followAskAi':
        return 'Ask AI must use an OpenAI‑compatible profile, or choose a different multimodal model in Advanced.';
      case 'settings.mediaAnnotation.annotateEnabled.title':
        return 'Annotate images';
      case 'settings.mediaAnnotation.annotateEnabled.subtitle':
        return 'When you add a photo, SecondLoop may send it to AI to generate an encrypted caption.';
      case 'settings.mediaAnnotation.searchEnabled.title':
        return 'Use annotations for search';
      case 'settings.mediaAnnotation.searchEnabled.subtitle':
        return 'Include image captions when building search data.';
      case 'settings.mediaAnnotation.searchToggleConfirm.title':
        return 'Update search index?';
      case 'settings.mediaAnnotation.searchToggleConfirm.bodyEnable':
        return 'Turning this on will rebuild search data so image captions become searchable.';
      case 'settings.mediaAnnotation.searchToggleConfirm.bodyDisable':
        return 'Turning this off will rebuild search data to remove image captions from search.';
      case 'settings.mediaAnnotation.advanced.title':
        return 'Advanced';
      case 'settings.mediaAnnotation.providerMode.title':
        return 'Multimodal model';
      case 'settings.mediaAnnotation.providerMode.subtitle':
        return 'Use a different provider/model for image captions.';
      case 'settings.mediaAnnotation.providerMode.labels.followAskAi':
        return 'Follow Ask AI';
      case 'settings.mediaAnnotation.providerMode.labels.cloudGateway':
        return 'SecondLoop Cloud';
      case 'settings.mediaAnnotation.providerMode.labels.byokProfile':
        return 'API key (profile)';
      case 'settings.mediaAnnotation.providerMode.descriptions.followAskAi':
        return 'Use the same setup as Ask AI. (Recommended)';
      case 'settings.mediaAnnotation.providerMode.descriptions.cloudGateway':
        return 'Use SecondLoop Cloud when available. (Requires Pro)';
      case 'settings.mediaAnnotation.providerMode.descriptions.byokProfile':
        return 'Use a specific API key profile (OpenAI‑compatible).';
      case 'settings.mediaAnnotation.cloudModelName.title':
        return 'Cloud model name';
      case 'settings.mediaAnnotation.cloudModelName.subtitle':
        return 'Override the cloud multimodal model name (optional).';
      case 'settings.mediaAnnotation.cloudModelName.hint':
        return 'e.g. gpt-4o-mini';
      case 'settings.mediaAnnotation.cloudModelName.followAskAi':
        return 'Follow Ask AI';
      case 'settings.mediaAnnotation.byokProfile.title':
        return 'API key profile';
      case 'settings.mediaAnnotation.byokProfile.subtitle':
        return 'Pick which profile to use for image captions.';
      case 'settings.mediaAnnotation.byokProfile.unset':
        return 'Not set';
      case 'settings.mediaAnnotation.byokProfile.missingBackend':
        return 'Not available in this build.';
      case 'settings.mediaAnnotation.byokProfile.noOpenAiCompatibleProfiles':
        return 'No OpenAI‑compatible profiles found. Add one in API keys.';
      case 'settings.mediaAnnotation.allowCellular.title':
        return 'Allow cellular data';
      case 'settings.mediaAnnotation.allowCellular.subtitle':
        return 'Use mobile data to annotate images. (Wi‑Fi only by default.)';
      case 'settings.mediaAnnotation.allowCellularConfirm.title':
        return 'Use cellular data for image annotations?';
      case 'settings.mediaAnnotation.allowCellularConfirm.body':
        return 'Annotating images may upload photos to your chosen AI provider and can use significant data.';
      case 'settings.cloudEmbeddings.title':
        return 'Smarter search';
      case 'settings.cloudEmbeddings.subtitleEnabled':
        return 'On. Improves search. Uses your Cloud quota.';
      case 'settings.cloudEmbeddings.subtitleDisabled':
        return 'Off. Search runs without cloud processing.';
      case 'settings.cloudEmbeddings.subtitleUnset':
        return 'Not set. We\'ll ask when it\'s first needed.';
      case 'settings.cloudEmbeddings.subtitleRequiresPro':
        return 'Requires SecondLoop Pro.';
      case 'settings.cloudEmbeddings.dialogTitle':
        return 'Turn on smarter search?';
      case 'settings.cloudEmbeddings.dialogBody':
        return 'To improve search and memory recall, SecondLoop can send small pieces of text (message previews, todo titles, follow‑ups) to SecondLoop Cloud to generate search data.\n\nThe text is processed confidentially (not logged or stored). Your vault key and sync key are never uploaded.\n\nThis uses your Cloud quota.';
      case 'settings.cloudEmbeddings.dialogActions.enable':
        return 'Enable';
      case 'settings.cloudAccount.title':
        return 'Cloud account';
      case 'settings.cloudAccount.subtitle':
        return 'Sign in to SecondLoop Cloud';
      case 'settings.cloudAccount.signedInAs':
        return ({required Object email}) => 'Signed in as ${email}';
      case 'settings.cloudAccount.benefits.title':
        return 'Create a cloud account to subscribe';
      case 'settings.cloudAccount.benefits.items.purchase.title':
        return 'Subscribe to SecondLoop Pro';
      case 'settings.cloudAccount.benefits.items.purchase.body':
        return 'A cloud account is required to purchase a subscription.';
      case 'settings.cloudAccount.errors.missingWebApiKey':
        return 'Cloud sign-in isn\'t available in this build. If you\'re running from source, run `pixi run init-env` (or copy `.env.example` → `.env.local`), set `SECONDLOOP_FIREBASE_WEB_API_KEY`, then restart the app.';
      case 'settings.cloudAccount.fields.email':
        return 'Email';
      case 'settings.cloudAccount.fields.password':
        return 'Password';
      case 'settings.cloudAccount.actions.signIn':
        return 'Sign in';
      case 'settings.cloudAccount.actions.signUp':
        return 'Create account';
      case 'settings.cloudAccount.actions.signOut':
        return 'Sign out';
      case 'settings.cloudAccount.emailVerification.title':
        return 'Email verification';
      case 'settings.cloudAccount.emailVerification.status.unknown':
        return 'Unknown';
      case 'settings.cloudAccount.emailVerification.status.verified':
        return 'Verified';
      case 'settings.cloudAccount.emailVerification.status.notVerified':
        return 'Not verified';
      case 'settings.cloudAccount.emailVerification.labels.status':
        return 'Status:';
      case 'settings.cloudAccount.emailVerification.labels.help':
        return 'Verify your email to use SecondLoop Cloud Ask AI.';
      case 'settings.cloudAccount.emailVerification.labels.verifiedHelp':
        return 'Email is verified. You can continue to subscribe.';
      case 'settings.cloudAccount.emailVerification.labels.loadFailed':
        return ({required Object error}) => 'Failed to load: ${error}';
      case 'settings.cloudAccount.emailVerification.actions.resend':
        return 'Resend verification email';
      case 'settings.cloudAccount.emailVerification.actions.resendCooldown':
        return ({required Object seconds}) => 'Resend in ${seconds}s';
      case 'settings.cloudAccount.emailVerification.messages.verificationEmailSent':
        return 'Verification email sent';
      case 'settings.cloudAccount.emailVerification.messages.verificationAlreadyDone':
        return 'Email is already verified.';
      case 'settings.cloudAccount.emailVerification.messages.signUpVerificationPrompt':
        return 'Account created. Please verify your email before subscribing.';
      case 'settings.cloudAccount.emailVerification.messages.verificationEmailSendFailed':
        return ({required Object error}) =>
            'Failed to send verification email: ${error}';
      case 'settings.cloudUsage.title':
        return 'Cloud usage';
      case 'settings.cloudUsage.subtitle':
        return 'Usage for current billing period';
      case 'settings.cloudUsage.actions.refresh':
        return 'Refresh';
      case 'settings.cloudUsage.labels.gatewayNotConfigured':
        return 'Cloud usage isn\'t available in this build.';
      case 'settings.cloudUsage.labels.signInRequired':
        return 'Sign in to view usage.';
      case 'settings.cloudUsage.labels.usage':
        return 'Usage:';
      case 'settings.cloudUsage.labels.askAiUsage':
        return 'Ask AI:';
      case 'settings.cloudUsage.labels.embeddingsUsage':
        return 'Smarter search:';
      case 'settings.cloudUsage.labels.inputTokensUsed30d':
        return 'Input tokens (30d):';
      case 'settings.cloudUsage.labels.outputTokensUsed30d':
        return 'Output tokens (30d):';
      case 'settings.cloudUsage.labels.tokensUsed30d':
        return 'Tokens (30d):';
      case 'settings.cloudUsage.labels.requestsUsed30d':
        return 'Requests (30d):';
      case 'settings.cloudUsage.labels.resetAt':
        return 'Resets on:';
      case 'settings.cloudUsage.labels.paymentRequired':
        return 'Subscription required to view cloud usage.';
      case 'settings.cloudUsage.labels.loadFailed':
        return ({required Object error}) => 'Failed to load: ${error}';
      case 'settings.vaultUsage.title':
        return 'Vault storage';
      case 'settings.vaultUsage.subtitle':
        return 'Storage used by your synced data';
      case 'settings.vaultUsage.actions.refresh':
        return 'Refresh';
      case 'settings.vaultUsage.labels.notConfigured':
        return 'Vault storage isn\'t available in this build.';
      case 'settings.vaultUsage.labels.signInRequired':
        return 'Sign in to view vault storage.';
      case 'settings.vaultUsage.labels.used':
        return 'Used:';
      case 'settings.vaultUsage.labels.limit':
        return 'Limit:';
      case 'settings.vaultUsage.labels.attachments':
        return 'Photos & files:';
      case 'settings.vaultUsage.labels.ops':
        return 'Sync history:';
      case 'settings.vaultUsage.labels.loadFailed':
        return ({required Object error}) => 'Failed to load: ${error}';
      case 'settings.diagnostics.title':
        return 'Diagnostics';
      case 'settings.diagnostics.subtitle':
        return 'Share a diagnostics report with support';
      case 'settings.diagnostics.privacyNote':
        return 'This report does not include your notes or API keys.';
      case 'settings.diagnostics.loading':
        return 'Loading diagnostics…';
      case 'settings.diagnostics.messages.copied':
        return 'Diagnostics copied to clipboard';
      case 'settings.diagnostics.messages.copyFailed':
        return ({required Object error}) =>
            'Failed to copy diagnostics: ${error}';
      case 'settings.diagnostics.messages.shareFailed':
        return ({required Object error}) =>
            'Failed to share diagnostics: ${error}';
      case 'settings.byokUsage.title':
        return 'API key usage';
      case 'settings.byokUsage.subtitle':
        return 'Active profile • requests and tokens (if available)';
      case 'settings.byokUsage.loading':
        return 'Loading…';
      case 'settings.byokUsage.noData':
        return 'No data';
      case 'settings.byokUsage.errors.unavailable':
        return ({required Object error}) => 'Usage unavailable: ${error}';
      case 'settings.byokUsage.sections.today':
        return ({required Object day}) => 'Today (${day})';
      case 'settings.byokUsage.sections.last30d':
        return ({required Object start, required Object end}) =>
            'Last 30 days (${start} → ${end})';
      case 'settings.byokUsage.labels.requests':
        return ({required Object purpose}) => '${purpose} requests';
      case 'settings.byokUsage.labels.tokens':
        return ({required Object purpose}) =>
            '${purpose} tokens (in/out/total)';
      case 'settings.byokUsage.purposes.semanticParse':
        return 'Semantic parse';
      case 'settings.byokUsage.purposes.mediaAnnotation':
        return 'Image annotations';
      case 'settings.subscription.title':
        return 'Subscription';
      case 'settings.subscription.subtitle':
        return 'Manage SecondLoop Pro';
      case 'settings.subscription.benefits.title':
        return 'SecondLoop Pro unlocks';
      case 'settings.subscription.benefits.items.noSetup.title':
        return 'AI without setup';
      case 'settings.subscription.benefits.items.noSetup.body':
        return 'No setup. Subscribe and start using built-in AI.';
      case 'settings.subscription.benefits.items.cloudSync.title':
        return 'Cloud storage + sync';
      case 'settings.subscription.benefits.items.cloudSync.body':
        return 'Your data stays in sync across devices.';
      case 'settings.subscription.benefits.items.mobileSearch.title':
        return 'Smarter search on mobile';
      case 'settings.subscription.benefits.items.mobileSearch.body':
        return 'Find things even if you remember different words.';
      case 'settings.subscription.status.unknown':
        return 'Unknown';
      case 'settings.subscription.status.entitled':
        return 'Active';
      case 'settings.subscription.status.notEntitled':
        return 'Inactive';
      case 'settings.subscription.actions.purchase':
        return 'Subscribe';
      case 'settings.subscription.labels.status':
        return 'Status:';
      case 'settings.subscription.labels.purchaseUnavailable':
        return 'Purchases are not available yet.';
      case 'settings.subscription.labels.loadFailed':
        return ({required Object error}) => 'Failed to load: ${error}';
      case 'settings.sync.title':
        return 'Sync';
      case 'settings.sync.subtitle':
        return 'Choose where your data syncs (Cloud / WebDAV / folder)';
      case 'settings.resetLocalDataThisDeviceOnly.dialogTitle':
        return 'Reset local data?';
      case 'settings.resetLocalDataThisDeviceOnly.dialogBody':
        return 'This will delete local messages and clear synced remote data for this device only. It will NOT delete your master password or your AI/sync settings. You will need to unlock again.';
      case 'settings.resetLocalDataThisDeviceOnly.failed':
        return ({required Object error}) => 'Reset failed: ${error}';
      case 'settings.resetLocalDataAllDevices.dialogTitle':
        return 'Reset local data?';
      case 'settings.resetLocalDataAllDevices.dialogBody':
        return 'This will delete local messages and clear all synced remote data. It will NOT delete your master password or your AI/sync settings. You will need to unlock again.';
      case 'settings.resetLocalDataAllDevices.failed':
        return ({required Object error}) => 'Reset failed: ${error}';
      case 'settings.debugResetLocalDataThisDeviceOnly.title':
        return 'Debug: Reset local data (this device)';
      case 'settings.debugResetLocalDataThisDeviceOnly.subtitle':
        return 'Delete local messages + clear remote data for this device only';
      case 'settings.debugResetLocalDataAllDevices.title':
        return 'Debug: Reset local data (all devices)';
      case 'settings.debugResetLocalDataAllDevices.subtitle':
        return 'Delete local messages + clear all remote data';
      case 'settings.debugSemanticSearch.title':
        return 'Debug: Semantic search';
      case 'settings.debugSemanticSearch.subtitle':
        return 'Search similar messages + rebuild embeddings index';
      case 'lock.masterPasswordRequired':
        return 'Master password required';
      case 'lock.passwordsDoNotMatch':
        return 'Passwords do not match';
      case 'lock.setupTitle':
        return 'Set master password';
      case 'lock.unlockTitle':
        return 'Unlock';
      case 'lock.unlockReason':
        return 'Unlock SecondLoop';
      case 'lock.missingSavedSessionKey':
        return 'Missing saved session key. Unlock with master password once.';
      case 'lock.creating':
        return 'Creating…';
      case 'lock.unlocking':
        return 'Unlocking…';
      case 'chat.mainStreamTitle':
        return 'Main Stream';
      case 'chat.attachTooltip':
        return 'Add attachment';
      case 'chat.attachPickMedia':
        return 'Choose media';
      case 'chat.attachTakePhoto':
        return 'Take photo';
      case 'chat.attachRecordAudio':
        return 'Record audio';
      case 'chat.switchToVoiceInput':
        return 'Switch to voice';
      case 'chat.switchToKeyboardInput':
        return 'Switch to keyboard';
      case 'chat.holdToTalk':
        return 'Hold to talk';
      case 'chat.releaseToConvert':
        return 'Release to convert to text';
      case 'chat.recordingInProgress':
        return 'Recording…';
      case 'chat.recordingHint':
        return 'Tap Stop to send audio, or Cancel to discard.';
      case 'chat.cameraTooltip':
        return 'Take photo';
      case 'chat.photoMessage':
        return 'Photo';
      case 'chat.editMessageTitle':
        return 'Edit message';
      case 'chat.messageUpdated':
        return 'Message updated';
      case 'chat.messageDeleted':
        return 'Message deleted';
      case 'chat.deleteMessageDialog.title':
        return 'Delete message?';
      case 'chat.deleteMessageDialog.message':
        return 'This will permanently delete this message and its attachments.';
      case 'chat.photoFailed':
        return ({required Object error}) => 'Photo failed: ${error}';
      case 'chat.audioRecordPermissionDenied':
        return 'Microphone permission is required to record audio.';
      case 'chat.audioRecordFailed':
        return ({required Object error}) => 'Audio record failed: ${error}';
      case 'chat.editFailed':
        return ({required Object error}) => 'Edit failed: ${error}';
      case 'chat.deleteFailed':
        return ({required Object error}) => 'Delete failed: ${error}';
      case 'chat.noMessagesYet':
        return 'No messages yet';
      case 'chat.viewFull':
        return 'View full';
      case 'chat.messageActions.convertToTodo':
        return 'Convert to task';
      case 'chat.messageActions.convertTodoToInfo':
        return 'Convert to note';
      case 'chat.messageActions.convertTodoToInfoConfirmTitle':
        return 'Convert to note?';
      case 'chat.messageActions.convertTodoToInfoConfirmBody':
        return 'This will remove the task, but keep the original message.';
      case 'chat.messageActions.openTodo':
        return 'Jump to task';
      case 'chat.messageActions.linkOtherTodo':
        return 'Link to another task';
      case 'chat.messageViewer.title':
        return 'Message';
      case 'chat.markdownEditor.openButton':
        return 'Markdown';
      case 'chat.markdownEditor.title':
        return 'Markdown editor';
      case 'chat.markdownEditor.apply':
        return 'Apply';
      case 'chat.markdownEditor.editorLabel':
        return 'Editor';
      case 'chat.markdownEditor.previewLabel':
        return 'Preview';
      case 'chat.markdownEditor.emptyPreview':
        return 'Preview will appear as you type.';
      case 'chat.markdownEditor.shortcutHint':
        return 'Tip: Cmd/Ctrl + Enter applies changes instantly.';
      case 'chat.markdownEditor.listContinuationHint':
        return 'Press Enter in a list item to continue it automatically.';
      case 'chat.markdownEditor.quickActionsLabel':
        return 'Quick formatting';
      case 'chat.markdownEditor.themeLabel':
        return 'Preview theme';
      case 'chat.markdownEditor.themeStudio':
        return 'Studio';
      case 'chat.markdownEditor.themePaper':
        return 'Paper';
      case 'chat.markdownEditor.themeOcean':
        return 'Ocean';
      case 'chat.markdownEditor.themeNight':
        return 'Night';
      case 'chat.markdownEditor.exportMenu':
        return 'Export preview';
      case 'chat.markdownEditor.exportPng':
        return 'Export as PNG';
      case 'chat.markdownEditor.exportPdf':
        return 'Export as PDF';
      case 'chat.markdownEditor.exportDone':
        return ({required Object format}) => 'Exported as ${format}';
      case 'chat.markdownEditor.exportSavedPath':
        return ({required Object path}) => 'Saved to ${path}';
      case 'chat.markdownEditor.exportFailed':
        return ({required Object error}) => 'Export failed: ${error}';
      case 'chat.markdownEditor.stats':
        return ({required Object lines, required Object characters}) =>
            '${lines} lines · ${characters} chars';
      case 'chat.markdownEditor.simpleInput':
        return 'Simple input';
      case 'chat.markdownEditor.actions.heading':
        return 'Heading';
      case 'chat.markdownEditor.actions.headingLevel':
        return ({required Object level}) => 'Heading ${level}';
      case 'chat.markdownEditor.actions.bold':
        return 'Bold';
      case 'chat.markdownEditor.actions.italic':
        return 'Italic';
      case 'chat.markdownEditor.actions.strike':
        return 'Strikethrough';
      case 'chat.markdownEditor.actions.code':
        return 'Inline code';
      case 'chat.markdownEditor.actions.link':
        return 'Insert link';
      case 'chat.markdownEditor.actions.blockquote':
        return 'Blockquote';
      case 'chat.markdownEditor.actions.bulletList':
        return 'Bullet list';
      case 'chat.markdownEditor.actions.orderedList':
        return 'Ordered list';
      case 'chat.markdownEditor.actions.taskList':
        return 'Task list';
      case 'chat.markdownEditor.actions.codeBlock':
        return 'Code block';
      case 'chat.focus.tooltip':
        return 'Focus';
      case 'chat.focus.allMemories':
        return 'Focus: All memories';
      case 'chat.focus.thisThread':
        return 'Focus: This thread';
      case 'chat.askAiSetup.title':
        return 'Ask AI setup required';
      case 'chat.askAiSetup.body':
        return 'To use Ask AI, add your own API key (AI profile) or subscribe to SecondLoop Cloud.';
      case 'chat.askAiSetup.actions.subscribe':
        return 'Subscribe';
      case 'chat.askAiSetup.actions.configureByok':
        return 'Add API key';
      case 'chat.cloudGateway.emailNotVerified':
        return 'Email not verified. Verify your email to use SecondLoop Cloud Ask AI.';
      case 'chat.cloudGateway.fallback.auth':
        return 'Cloud sign-in required. Using your API key for this request.';
      case 'chat.cloudGateway.fallback.entitlement':
        return 'Cloud subscription required. Using your API key for this request.';
      case 'chat.cloudGateway.fallback.rateLimited':
        return 'Cloud is busy. Using your API key for this request.';
      case 'chat.cloudGateway.fallback.generic':
        return 'Cloud request failed. Using your API key for this request.';
      case 'chat.cloudGateway.errors.auth':
        return 'Cloud sign-in required. Open Cloud account and sign in again.';
      case 'chat.cloudGateway.errors.entitlement':
        return 'Cloud subscription required. Add an API key or try again later.';
      case 'chat.cloudGateway.errors.rateLimited':
        return 'Cloud is rate limited. Please try again later.';
      case 'chat.cloudGateway.errors.generic':
        return 'Cloud request failed.';
      case 'chat.askAiFailedTemporary':
        return 'Ask AI failed. Please try again.';
      case 'chat.askAiConsent.title':
        return 'Before we use AI';
      case 'chat.askAiConsent.body':
        return 'SecondLoop may send the text you type and a few relevant snippets to your chosen AI provider to power AI features.\n\nIt will not upload your master password or your full history.';
      case 'chat.askAiConsent.dontShowAgain':
        return 'Don\'t show again';
      case 'chat.embeddingsConsent.title':
        return 'Use cloud embeddings for semantic search?';
      case 'chat.embeddingsConsent.body':
        return 'Benefits:\n- Better cross-language recall\n- Better todo linking suggestions\n\nPrivacy:\n- We only upload the minimum text needed to generate embeddings\n- The snippets are sent to SecondLoop Cloud Gateway and kept confidential (not logged or stored)\n- We never upload your vault key or sync key\n\nUsage:\n- Cloud embeddings count toward your cloud usage quota';
      case 'chat.embeddingsConsent.dontShowAgain':
        return 'Remember my choice';
      case 'chat.embeddingsConsent.actions.useLocal':
        return 'Use local';
      case 'chat.embeddingsConsent.actions.enableCloud':
        return 'Enable cloud embeddings';
      case 'chat.semanticParseStatusRunning':
        return 'AI analyzing…';
      case 'chat.semanticParseStatusSlow':
        return 'AI is taking longer. Continuing in background…';
      case 'chat.attachmentAnnotationNeedsSetup':
        return 'Image annotations need setup';
      case 'chat.semanticParseStatusFailed':
        return 'AI analysis failed';
      case 'chat.semanticParseStatusCanceled':
        return 'AI analysis canceled';
      case 'chat.semanticParseStatusCreated':
        return ({required Object title}) => 'Created task: ${title}';
      case 'chat.semanticParseStatusUpdated':
        return ({required Object title}) => 'Updated task: ${title}';
      case 'chat.semanticParseStatusUpdatedGeneric':
        return 'Updated task';
      case 'chat.semanticParseStatusUndone':
        return 'Undid auto action';
      case 'chat.askAiRecoveredDetached':
        return 'Recovered the completed cloud answer.';
      case 'chat.topicThread.filterTooltip':
        return 'Topic thread filter';
      case 'chat.topicThread.actionLabel':
        return 'Topic thread';
      case 'chat.topicThread.create':
        return 'Create topic thread';
      case 'chat.topicThread.clearFilter':
        return 'Clear topic thread filter';
      case 'chat.topicThread.clear':
        return 'Clear thread';
      case 'chat.topicThread.manage':
        return 'Manage thread';
      case 'chat.topicThread.rename':
        return 'Rename thread';
      case 'chat.topicThread.delete':
        return 'Delete thread';
      case 'chat.topicThread.deleteDialog.title':
        return 'Delete topic thread?';
      case 'chat.topicThread.deleteDialog.message':
        return 'Deleting removes this thread and its message memberships.';
      case 'chat.topicThread.deleteDialog.confirm':
        return 'Delete';
      case 'chat.topicThread.addMessage':
        return 'Add this message';
      case 'chat.topicThread.removeMessage':
        return 'Remove this message';
      case 'chat.topicThread.createDialogTitle':
        return 'Create topic thread';
      case 'chat.topicThread.renameDialogTitle':
        return 'Rename topic thread';
      case 'chat.topicThread.titleFieldLabel':
        return 'Thread title (optional)';
      case 'chat.topicThread.untitled':
        return 'Untitled topic thread';
      case 'chat.tagFilter.tooltip':
        return 'Tag filter';
      case 'chat.tagFilter.clearFilter':
        return 'Clear tag filter';
      case 'chat.tagFilter.sheet.title':
        return 'Filter by tags';
      case 'chat.tagFilter.sheet.apply':
        return 'Apply';
      case 'chat.tagFilter.sheet.clear':
        return 'Clear';
      case 'chat.tagFilter.sheet.includeHint':
        return 'Tap: Include';
      case 'chat.tagFilter.sheet.excludeHint':
        return 'Tap again: Exclude';
      case 'chat.tagFilter.sheet.empty':
        return 'No tags yet';
      case 'chat.tagPicker.title':
        return 'Manage tags';
      case 'chat.tagPicker.suggested':
        return 'Suggested tags';
      case 'chat.tagPicker.mergeSuggestions':
        return 'Merge suggestions';
      case 'chat.tagPicker.mergeAction':
        return 'Merge';
      case 'chat.tagPicker.mergeDismissAction':
        return 'Dismiss';
      case 'chat.tagPicker.mergeLaterAction':
        return 'Later';
      case 'chat.tagPicker.mergeSuggestionMessages':
        return ({required Object count}) => 'Affects ${count} tagged messages';
      case 'chat.tagPicker.mergeReasonSystemDomain':
        return 'Matches system domain';
      case 'chat.tagPicker.mergeReasonNameCompact':
        return 'Likely duplicate name';
      case 'chat.tagPicker.mergeReasonNameContains':
        return 'Very similar name';
      case 'chat.tagPicker.mergeDialog.title':
        return 'Merge tags?';
      case 'chat.tagPicker.mergeDialog.message':
        return ({required Object source, required Object target}) =>
            'Merge "${source}" into "${target}"? This updates existing message tags.';
      case 'chat.tagPicker.mergeDialog.confirm':
        return 'Merge';
      case 'chat.tagPicker.mergeApplied':
        return ({required Object count}) => 'Merged ${count} messages';
      case 'chat.tagPicker.mergeDismissed':
        return 'Merge suggestion dismissed';
      case 'chat.tagPicker.mergeSavedForLater':
        return 'Merge suggestion saved for later';
      case 'chat.tagPicker.all':
        return 'All tags';
      case 'chat.tagPicker.inputHint':
        return 'Type a tag name';
      case 'chat.tagPicker.add':
        return 'Add';
      case 'chat.tagPicker.save':
        return 'Save';
      case 'chat.tagPicker.tagActionLabel':
        return 'Tags';
      case 'chat.askScopeEmpty.title':
        return 'No results in current scope';
      case 'chat.askScopeEmpty.actions.expandTimeWindow':
        return 'Expand time window';
      case 'chat.askScopeEmpty.actions.removeIncludeTags':
        return 'Remove include tags';
      case 'chat.askScopeEmpty.actions.switchScopeToAll':
        return 'Switch scope to All';
      case 'attachments.metadata.format':
        return 'Format';
      case 'attachments.metadata.size':
        return 'Size';
      case 'attachments.metadata.capturedAt':
        return 'Captured';
      case 'attachments.metadata.location':
        return 'Location';
      case 'attachments.url.originalUrl':
        return 'Original URL';
      case 'attachments.url.canonicalUrl':
        return 'Canonical URL';
      case 'attachments.content.summary':
        return 'Summary';
      case 'attachments.content.excerpt':
        return 'Excerpt';
      case 'attachments.content.fullText':
        return 'Full text';
      case 'attachments.content.ocrTitle':
        return 'OCR';
      case 'attachments.content.needsOcrTitle':
        return 'OCR required';
      case 'attachments.content.needsOcrSubtitle':
        return 'This PDF appears to contain no selectable text.';
      case 'attachments.content.runOcr':
        return 'Run OCR';
      case 'attachments.content.rerunOcr':
        return 'Re-run OCR';
      case 'attachments.content.ocrRunning':
        return 'OCR in progress…';
      case 'attachments.content.ocrReadySubtitle':
        return 'Text is available. You can re-run OCR if needed.';
      case 'attachments.content.keepForegroundHint':
        return 'Keep the app in foreground while OCR is running.';
      case 'attachments.content.openWithSystem':
        return 'Open with system app';
      case 'attachments.content.previewUnavailable':
        return 'Preview unavailable';
      case 'attachments.content.ocrFinished':
        return 'OCR finished. Refreshing preview…';
      case 'attachments.content.ocrFailed':
        return 'OCR failed on this device.';
      case 'attachments.content.speechTranscribeIssue.title':
        return 'Speech transcription unavailable';
      case 'attachments.content.speechTranscribeIssue.openSettings':
        return 'Open settings';
      case 'attachments.content.speechTranscribeIssue.openSettingsFailed':
        return 'Unable to open system settings automatically. Please check speech permission and Dictation manually.';
      case 'attachments.content.speechTranscribeIssue.permissionDenied':
        return 'Speech permission was denied. Tap Retry to request it again, or open system settings if it remains blocked.';
      case 'attachments.content.speechTranscribeIssue.permissionRestricted':
        return 'Speech recognition is restricted by system policy. Check Screen Time or device management policy.';
      case 'attachments.content.speechTranscribeIssue.serviceDisabled':
        return 'Siri and Dictation are disabled. Please enable them before retrying.';
      case 'attachments.content.speechTranscribeIssue.runtimeUnavailable':
        return 'Speech runtime is currently unavailable on this device. Please retry later.';
      case 'attachments.content.speechTranscribeIssue.permissionRequest':
        return 'Local speech transcription needs speech permission. Tap Retry and allow the system permission prompt.';
      case 'attachments.content.speechTranscribeIssue.offlineUnavailable':
        return 'On-device offline speech recognition is unavailable for this device or language. Install speech packs or switch to cloud transcription.';
      case 'attachments.content.videoInsights.contentKind.knowledge':
        return 'Knowledge video';
      case 'attachments.content.videoInsights.contentKind.nonKnowledge':
        return 'Non-knowledge video';
      case 'attachments.content.videoInsights.contentKind.unknown':
        return 'Unknown';
      case 'attachments.content.videoInsights.detail.knowledgeMarkdown':
        return 'Knowledge markdown';
      case 'attachments.content.videoInsights.detail.videoDescription':
        return 'Video description';
      case 'attachments.content.videoInsights.detail.extractedContent':
        return 'Extracted content';
      case 'attachments.content.videoInsights.fields.contentType':
        return 'Content type';
      case 'attachments.content.videoInsights.fields.segments':
        return 'Segments';
      case 'attachments.content.videoInsights.fields.summary':
        return 'Video summary';
      case 'semanticSearch.preparing':
        return 'Preparing semantic search…';
      case 'semanticSearch.indexingMessages':
        return ({required Object count}) =>
            'Indexing messages… (${count} indexed)';
      case 'semanticSearchDebug.title':
        return 'Semantic Search (Debug)';
      case 'semanticSearchDebug.embeddingModelLoading':
        return 'Embedding model: (loading...)';
      case 'semanticSearchDebug.embeddingModel':
        return ({required Object model}) => 'Embedding model: ${model}';
      case 'semanticSearchDebug.switchedModelReindex':
        return 'Switched embedding model; re-index pending';
      case 'semanticSearchDebug.modelAlreadyActive':
        return 'Embedding model already active';
      case 'semanticSearchDebug.processedPending':
        return ({required Object count}) =>
            'Processed ${count} pending embeddings';
      case 'semanticSearchDebug.rebuilt':
        return ({required Object count}) =>
            'Rebuilt embeddings for ${count} messages';
      case 'semanticSearchDebug.runSearchToSeeResults':
        return 'Run a search to see results';
      case 'semanticSearchDebug.noResults':
        return 'No results';
      case 'semanticSearchDebug.resultSubtitle':
        return (
                {required Object distance,
                required Object role,
                required Object conversationId}) =>
            'distance=${distance} • role=${role} • convo=${conversationId}';
      case 'sync.title':
        return 'Sync settings';
      case 'sync.progressDialog.title':
        return 'Syncing…';
      case 'sync.progressDialog.preparing':
        return 'Preparing…';
      case 'sync.progressDialog.pulling':
        return 'Downloading changes…';
      case 'sync.progressDialog.pushing':
        return 'Uploading changes…';
      case 'sync.progressDialog.uploadingMedia':
        return 'Uploading media…';
      case 'sync.progressDialog.finalizing':
        return 'Finalizing…';
      case 'sync.sections.automation':
        return 'Auto sync';
      case 'sync.sections.backend':
        return 'Sync method';
      case 'sync.sections.mediaPreview':
        return 'Media downloads';
      case 'sync.sections.mediaBackup':
        return 'Media uploads';
      case 'sync.sections.securityActions':
        return 'Security & manual sync';
      case 'sync.autoSync.title':
        return 'Auto sync';
      case 'sync.autoSync.subtitle':
        return 'Keeps your devices in sync automatically.';
      case 'sync.autoSync.wifiOnlyTitle':
        return 'Auto sync on Wi‑Fi only';
      case 'sync.autoSync.wifiOnlySubtitle':
        return 'Save mobile data by syncing automatically only on Wi‑Fi';
      case 'sync.mediaPreview.chatThumbnailsWifiOnlyTitle':
        return 'Download media files on Wi‑Fi only';
      case 'sync.mediaPreview.chatThumbnailsWifiOnlySubtitle':
        return 'If an attachment isn\'t on this device yet, download it only on Wi‑Fi';
      case 'sync.mediaBackup.title':
        return 'Media uploads';
      case 'sync.mediaBackup.subtitle':
        return 'Uploads encrypted images for cross‑device viewing and memory recall';
      case 'sync.mediaBackup.wifiOnlyTitle':
        return 'Upload on Wi‑Fi only';
      case 'sync.mediaBackup.wifiOnlySubtitle':
        return 'Avoid using mobile data for large uploads';
      case 'sync.mediaBackup.description':
        return 'Uploads encrypted image attachments to your sync storage. Images are downloaded on demand when viewing on another device.';
      case 'sync.mediaBackup.stats':
        return (
                {required Object pending,
                required Object failed,
                required Object uploaded}) =>
            'Queued ${pending} · Failed ${failed} · Uploaded ${uploaded}';
      case 'sync.mediaBackup.lastUploaded':
        return ({required Object at}) => 'Last upload: ${at}';
      case 'sync.mediaBackup.lastError':
        return ({required Object error}) => 'Last error: ${error}';
      case 'sync.mediaBackup.lastErrorWithTime':
        return ({required Object at, required Object error}) =>
            'Last error (${at}): ${error}';
      case 'sync.mediaBackup.backfillButton':
        return 'Queue existing images';
      case 'sync.mediaBackup.uploadNowButton':
        return 'Upload now';
      case 'sync.mediaBackup.backfillEnqueued':
        return ({required Object count}) => 'Queued ${count} images for upload';
      case 'sync.mediaBackup.backfillFailed':
        return ({required Object error}) =>
            'Couldn\'t queue existing images: ${error}';
      case 'sync.mediaBackup.notEnabled':
        return 'Turn on Media uploads first.';
      case 'sync.mediaBackup.managedVaultOnly':
        return 'Media uploads are available with WebDAV or SecondLoop Cloud sync.';
      case 'sync.mediaBackup.wifiOnlyBlocked':
        return 'Wi‑Fi only is on. Connect to Wi‑Fi, or allow mobile data just this once.';
      case 'sync.mediaBackup.uploaded':
        return 'Upload complete';
      case 'sync.mediaBackup.nothingToUpload':
        return 'Nothing to upload';
      case 'sync.mediaBackup.uploadFailed':
        return ({required Object error}) => 'Upload failed: ${error}';
      case 'sync.mediaBackup.cellularDialog.title':
        return 'Use mobile data?';
      case 'sync.mediaBackup.cellularDialog.message':
        return 'Wi‑Fi only is on. Uploading over mobile data may use a lot of data.';
      case 'sync.mediaBackup.cellularDialog.confirm':
        return 'Use mobile data';
      case 'sync.localCache.button':
        return 'Clear local storage';
      case 'sync.localCache.subtitle':
        return 'Deletes cached attachment files on this device (remote copies are kept and can be re-downloaded). Make sure sync/upload has completed.';
      case 'sync.localCache.cleared':
        return 'Cleared local cache';
      case 'sync.localCache.failed':
        return ({required Object error}) => 'Clear failed: ${error}';
      case 'sync.localCache.dialog.title':
        return 'Clear local storage?';
      case 'sync.localCache.dialog.message':
        return 'This deletes cached photos and files on this device to save space. Your remote sync storage keeps a copy; items will be re-downloaded on demand when viewed again.';
      case 'sync.localCache.dialog.confirm':
        return 'Clear';
      case 'sync.backendLabel':
        return 'Sync method';
      case 'sync.backendWebdav':
        return 'WebDAV (your server)';
      case 'sync.backendLocalDir':
        return 'Folder on this computer (desktop)';
      case 'sync.backendManagedVault':
        return 'SecondLoop Cloud';
      case 'sync.cloudManagedVault.signInRequired':
        return 'Sign in to use SecondLoop Cloud sync.';
      case 'sync.cloudManagedVault.paymentRequired':
        return 'Cloud sync is paused. Renew your subscription to continue syncing.';
      case 'sync.cloudManagedVault.graceReadonlyUntil':
        return ({required Object until}) =>
            'Cloud sync is read-only until ${until}.';
      case 'sync.cloudManagedVault.storageQuotaExceeded':
        return 'Cloud storage is full. Uploads are paused.';
      case 'sync.cloudManagedVault.storageQuotaExceededWithUsage':
        return ({required Object used, required Object limit}) =>
            'Cloud storage is full (${used} / ${limit}). Uploads are paused.';
      case 'sync.cloudManagedVault.switchDialog.title':
        return 'Switch to SecondLoop Cloud sync?';
      case 'sync.cloudManagedVault.switchDialog.message':
        return 'Your subscription is active. Switch your sync method to SecondLoop Cloud? You can change this anytime.';
      case 'sync.cloudManagedVault.switchDialog.cancel':
        return 'Not now';
      case 'sync.cloudManagedVault.switchDialog.confirm':
        return 'Switch';
      case 'sync.cloudManagedVault.setPassphraseDialog.title':
        return 'Set sync passphrase';
      case 'sync.cloudManagedVault.setPassphraseDialog.confirm':
        return 'Save passphrase';
      case 'sync.remoteRootRequired':
        return 'Folder name is required';
      case 'sync.baseUrlRequired':
        return 'Server address is required';
      case 'sync.localDirRequired':
        return 'Folder path is required';
      case 'sync.connectionOk':
        return 'Connection OK';
      case 'sync.connectionFailed':
        return ({required Object error}) => 'Connection failed: ${error}';
      case 'sync.saveFailed':
        return ({required Object error}) => 'Save failed: ${error}';
      case 'sync.missingSyncKey':
        return 'Enter your sync passphrase and tap Save first.';
      case 'sync.pushedOps':
        return ({required Object count}) => 'Uploaded ${count} changes';
      case 'sync.pulledOps':
        return ({required Object count}) => 'Downloaded ${count} changes';
      case 'sync.noNewChanges':
        return 'No new changes';
      case 'sync.pushFailed':
        return ({required Object error}) => 'Upload failed: ${error}';
      case 'sync.pullFailed':
        return ({required Object error}) => 'Download failed: ${error}';
      case 'sync.fields.baseUrl.label':
        return 'Server address';
      case 'sync.fields.baseUrl.hint':
        return 'https://example.com/dav';
      case 'sync.fields.username.label':
        return 'Username (optional)';
      case 'sync.fields.password.label':
        return 'Password (optional)';
      case 'sync.fields.localDir.label':
        return 'Folder path';
      case 'sync.fields.localDir.hint':
        return '/Users/me/SecondLoopVault';
      case 'sync.fields.localDir.helper':
        return 'Best for desktop; mobile platforms may not support this path.';
      case 'sync.fields.managedVaultBaseUrl.label':
        return 'Cloud server address (advanced)';
      case 'sync.fields.managedVaultBaseUrl.hint':
        return 'https://vault.example.com';
      case 'sync.fields.vaultId.label':
        return 'Cloud account ID';
      case 'sync.fields.vaultId.hint':
        return 'Auto';
      case 'sync.fields.remoteRoot.label':
        return 'Folder name';
      case 'sync.fields.remoteRoot.hint':
        return 'SecondLoop';
      case 'sync.fields.passphrase.label':
        return 'Sync passphrase';
      case 'sync.fields.passphrase.helper':
        return 'Use the same passphrase on all devices. It’s never uploaded.';
      case 'llmProfiles.title':
        return 'AI profiles';
      case 'llmProfiles.refreshTooltip':
        return 'Refresh';
      case 'llmProfiles.activeProfileHelp':
        return 'The active profile is reused as the general LLM API profile across intelligence features.';
      case 'llmProfiles.noProfilesYet':
        return 'No profiles yet.';
      case 'llmProfiles.addProfile':
        return 'Add profile';
      case 'llmProfiles.deleted':
        return 'AI profile deleted';
      case 'llmProfiles.validationError':
        return 'Name, API key, and model are required.';
      case 'llmProfiles.deleteDialog.title':
        return 'Delete profile?';
      case 'llmProfiles.deleteDialog.message':
        return ({required Object name}) =>
            'Delete "${name}"? This removes it from this device.';
      case 'llmProfiles.fields.name':
        return 'Name';
      case 'llmProfiles.fields.provider':
        return 'Provider';
      case 'llmProfiles.fields.baseUrlOptional':
        return 'API endpoint (optional)';
      case 'llmProfiles.fields.modelName':
        return 'Model';
      case 'llmProfiles.fields.apiKey':
        return 'API key';
      case 'llmProfiles.providers.openaiCompatible':
        return 'OpenAI-compatible';
      case 'llmProfiles.providers.geminiCompatible':
        return 'Gemini';
      case 'llmProfiles.providers.anthropicCompatible':
        return 'Anthropic';
      case 'llmProfiles.savedActivated':
        return 'AI profile saved and activated';
      case 'llmProfiles.actions.saveActivate':
        return 'Save & Activate';
      case 'llmProfiles.actions.cancel':
        return 'Cancel';
      case 'llmProfiles.actions.delete':
        return 'Delete';
      case 'embeddingProfiles.title':
        return 'Embedding profiles';
      case 'embeddingProfiles.refreshTooltip':
        return 'Refresh';
      case 'embeddingProfiles.activeProfileHelp':
        return 'Active profile is used for embeddings (semantic search / RAG).';
      case 'embeddingProfiles.noProfilesYet':
        return 'No profiles yet.';
      case 'embeddingProfiles.addProfile':
        return 'Add profile';
      case 'embeddingProfiles.deleted':
        return 'Embedding profile deleted';
      case 'embeddingProfiles.validationError':
        return 'Name, API key, and model are required.';
      case 'embeddingProfiles.reindexDialog.title':
        return 'Rebuild embeddings index?';
      case 'embeddingProfiles.reindexDialog.message':
        return 'Activating this profile may rebuild your local embeddings index using your API key/credits. This may take a while and can incur costs.';
      case 'embeddingProfiles.reindexDialog.actions.continueLabel':
        return 'Continue';
      case 'embeddingProfiles.deleteDialog.title':
        return 'Delete profile?';
      case 'embeddingProfiles.deleteDialog.message':
        return ({required Object name}) =>
            'Delete "${name}"? This removes it from this device.';
      case 'embeddingProfiles.fields.name':
        return 'Name';
      case 'embeddingProfiles.fields.provider':
        return 'Provider';
      case 'embeddingProfiles.fields.baseUrlOptional':
        return 'API endpoint (optional)';
      case 'embeddingProfiles.fields.modelName':
        return 'Model';
      case 'embeddingProfiles.fields.apiKey':
        return 'API key';
      case 'embeddingProfiles.providers.openaiCompatible':
        return 'OpenAI-compatible';
      case 'embeddingProfiles.savedActivated':
        return 'Embedding profile saved and activated';
      case 'embeddingProfiles.actions.saveActivate':
        return 'Save & Activate';
      case 'embeddingProfiles.actions.cancel':
        return 'Cancel';
      case 'embeddingProfiles.actions.delete':
        return 'Delete';
      case 'inbox.defaultTitle':
        return 'Inbox';
      case 'inbox.noConversationsYet':
        return 'No conversations yet';
      default:
        return null;
    }
  }
}

extension on _StringsZhCn {
  dynamic _flatMapFunction(String path) {
    switch (path) {
      case 'app.title':
        return 'SecondLoop';
      case 'app.tabs.main':
        return '主线';
      case 'app.tabs.settings':
        return '设置';
      case 'common.actions.cancel':
        return '取消';
      case 'common.actions.notNow':
        return '暂不';
      case 'common.actions.allow':
        return '允许';
      case 'common.actions.save':
        return '保存';
      case 'common.actions.copy':
        return '复制';
      case 'common.actions.reset':
        return '重置';
      case 'common.actions.continueLabel':
        return '继续';
      case 'common.actions.send':
        return '发送';
      case 'common.actions.askAi':
        return 'AI 对话';
      case 'common.actions.configureAi':
        return '配置 AI';
      case 'common.actions.stop':
        return '停止';
      case 'common.actions.stopping':
        return '正在停止…';
      case 'common.actions.edit':
        return '编辑';
      case 'common.actions.delete':
        return '删除';
      case 'common.actions.undo':
        return '撤销';
      case 'common.actions.open':
        return '打开';
      case 'common.actions.retry':
        return '重试';
      case 'common.actions.ignore':
        return '忽略';
      case 'common.actions.refresh':
        return '刷新';
      case 'common.actions.share':
        return '分享';
      case 'common.actions.search':
        return '搜索';
      case 'common.actions.useModel':
        return '使用模型';
      case 'common.actions.processPending':
        return '处理待处理';
      case 'common.actions.rebuildEmbeddings':
        return '重建向量索引';
      case 'common.actions.push':
        return '上传';
      case 'common.actions.pull':
        return '下载';
      case 'common.actions.lockNow':
        return '立即锁定';
      case 'common.fields.masterPassword':
        return '主密码';
      case 'common.fields.confirm':
        return '确认';
      case 'common.fields.message':
        return '消息';
      case 'common.fields.quickCapture':
        return '快速记录';
      case 'common.fields.query':
        return '查询';
      case 'common.labels.elapsedSeconds':
        return ({required Object seconds}) => '耗时：${seconds}s';
      case 'common.labels.topK':
        return 'Top‑K：';
      case 'errors.initFailed':
        return ({required Object error}) => '初始化失败：${error}';
      case 'errors.loadFailed':
        return ({required Object error}) => '加载失败：${error}';
      case 'errors.saveFailed':
        return ({required Object error}) => '保存失败：${error}';
      case 'errors.lockGateError':
        return ({required Object error}) => '锁定流程错误：${error}';
      case 'errors.missingMainStream':
        return '缺少主线对话';
      case 'actions.capture.title':
        return '要把它变成提醒吗？';
      case 'actions.capture.pickTime':
        return '选择时间';
      case 'actions.capture.reviewLater':
        return '先放着，之后提醒我确认';
      case 'actions.capture.justSave':
        return '只保存为记录';
      case 'actions.reviewQueue.title':
        return '待确认';
      case 'actions.reviewQueue.banner':
        return ({required Object count}) => '有 ${count} 条待确认事项';
      case 'actions.reviewQueue.empty':
        return '没有需要确认的事项';
      case 'actions.reviewQueue.snoozedUntil':
        return ({required Object when}) => '已延期到 ${when}';
      case 'actions.reviewQueue.inAppFallback.message':
        return ({required Object count}) => '有 ${count} 条事项正在等待你确认';
      case 'actions.reviewQueue.inAppFallback.open':
        return '打开待确认队列';
      case 'actions.reviewQueue.inAppFallback.dismiss':
        return '稍后再说';
      case 'actions.reviewQueue.actions.schedule':
        return '安排时间';
      case 'actions.reviewQueue.actions.snooze':
        return '明早提醒';
      case 'actions.reviewQueue.actions.start':
        return '开始';
      case 'actions.reviewQueue.actions.done':
        return '完成';
      case 'actions.reviewQueue.actions.dismiss':
        return '忽略';
      case 'actions.todoStatus.inbox':
        return '待确认';
      case 'actions.todoStatus.open':
        return '未开始';
      case 'actions.todoStatus.inProgress':
        return '进行中';
      case 'actions.todoStatus.done':
        return '已完成';
      case 'actions.todoStatus.dismissed':
        return '已删除';
      case 'actions.todoLink.title':
        return '要更新哪个待办？';
      case 'actions.todoLink.subtitle':
        return ({required Object status}) => '默认标记为：${status}';
      case 'actions.todoLink.updated':
        return ({required Object title, required Object status}) =>
            '已更新「${title}」为：${status}';
      case 'actions.todoNoteLink.action':
        return '关联到待办';
      case 'actions.todoNoteLink.actionShort':
        return '关联';
      case 'actions.todoNoteLink.title':
        return '要关联到哪个待办？';
      case 'actions.todoNoteLink.subtitle':
        return '将这条消息作为跟进记录添加';
      case 'actions.todoNoteLink.noMatches':
        return '没有匹配的待办';
      case 'actions.todoNoteLink.suggest':
        return '要把这条消息关联到待办吗？';
      case 'actions.todoNoteLink.linked':
        return ({required Object title}) => '已关联到「${title}」';
      case 'actions.todoAuto.created':
        return ({required Object title}) => '已创建「${title}」';
      case 'actions.todoDetail.title':
        return '待办详情';
      case 'actions.todoDetail.emptyTimeline':
        return '暂无跟进记录';
      case 'actions.todoDetail.noteHint':
        return '补充跟进…';
      case 'actions.todoDetail.addNote':
        return '添加';
      case 'actions.todoDetail.attach':
        return '添加附件';
      case 'actions.todoDetail.pickAttachment':
        return '选择附件';
      case 'actions.todoDetail.noAttachments':
        return '暂无附件';
      case 'actions.todoDetail.attachmentNoteDefault':
        return '添加了附件';
      case 'actions.todoDelete.dialog.title':
        return '删除待办？';
      case 'actions.todoDelete.dialog.message':
        return '这将永久删除该待办，并删除所有关联的聊天消息。';
      case 'actions.todoDelete.dialog.confirm':
        return '删除';
      case 'actions.todoRecurrenceEditScope.title':
        return '重复任务如何应用修改';
      case 'actions.todoRecurrenceEditScope.message':
        return '这次更改要如何应用？';
      case 'actions.todoRecurrenceEditScope.thisOnly':
        return '仅本次';
      case 'actions.todoRecurrenceEditScope.thisAndFuture':
        return '本次及以后';
      case 'actions.todoRecurrenceEditScope.wholeSeries':
        return '整个系列';
      case 'actions.todoRecurrenceRule.title':
        return '编辑重复规则';
      case 'actions.todoRecurrenceRule.edit':
        return '重复';
      case 'actions.todoRecurrenceRule.frequencyLabel':
        return '频率';
      case 'actions.todoRecurrenceRule.intervalLabel':
        return '间隔';
      case 'actions.todoRecurrenceRule.daily':
        return '每天';
      case 'actions.todoRecurrenceRule.weekly':
        return '每周';
      case 'actions.todoRecurrenceRule.monthly':
        return '每月';
      case 'actions.todoRecurrenceRule.yearly':
        return '每年';
      case 'actions.history.title':
        return '回溯';
      case 'actions.history.empty':
        return '该时间范围内没有记录';
      case 'actions.history.presets.thisWeek':
        return '本周';
      case 'actions.history.presets.lastWeek':
        return '上周';
      case 'actions.history.presets.lastTwoWeeks':
        return '上两周';
      case 'actions.history.presets.custom':
        return '自定义范围';
      case 'actions.history.actions.copy':
        return '复制';
      case 'actions.history.actions.copied':
        return '已复制';
      case 'actions.history.sections.created':
        return '新增';
      case 'actions.history.sections.started':
        return '开始';
      case 'actions.history.sections.done':
        return '完成';
      case 'actions.history.sections.dismissed':
        return '不再提醒';
      case 'actions.agenda.title':
        return '待办';
      case 'actions.agenda.summary':
        return ({required Object due, required Object overdue}) =>
            '今天 ${due} 条 · 逾期 ${overdue} 条';
      case 'actions.agenda.upcomingSummary':
        return ({required Object count}) => '接下来 ${count} 条';
      case 'actions.agenda.viewAll':
        return '查看全部';
      case 'actions.agenda.empty':
        return '暂无待办';
      case 'actions.calendar.title':
        return '添加到日历？';
      case 'actions.calendar.pickTime':
        return '选择开始时间';
      case 'actions.calendar.noAutoTime':
        return '未找到可自动解析的时间';
      case 'actions.calendar.pickCustom':
        return '选择日期时间';
      case 'settings.title':
        return '设置';
      case 'settings.sections.appearance':
        return '外观';
      case 'settings.sections.security':
        return '安全';
      case 'settings.sections.cloud':
        return 'SecondLoop Cloud';
      case 'settings.sections.aiAdvanced':
        return '高级（自带 API Key）';
      case 'settings.sections.storage':
        return '同步与存储';
      case 'settings.sections.actions':
        return '行动';
      case 'settings.sections.support':
        return '帮助与支持';
      case 'settings.sections.debug':
        return '调试';
      case 'settings.actionsReview.morningTime.title':
        return '早上提醒时间';
      case 'settings.actionsReview.morningTime.subtitle':
        return '未排期事项的默认提醒时间';
      case 'settings.actionsReview.dayEndTime.title':
        return '日终时间';
      case 'settings.actionsReview.dayEndTime.subtitle':
        return '到此时间仍未处理，将降低提醒频率';
      case 'settings.actionsReview.weeklyTime.title':
        return '每周提醒时间';
      case 'settings.actionsReview.weeklyTime.subtitle':
        return '每周提醒时间（周日）';
      case 'settings.actionsReview.inAppFallback.title':
        return '应用内提醒';
      case 'settings.actionsReview.inAppFallback.subtitle':
        return '在应用内显示待办事项通知';
      case 'settings.quickCaptureHotkey.title':
        return '快速记录快捷键';
      case 'settings.quickCaptureHotkey.subtitle':
        return '用于从任何地方打开快速记录';
      case 'settings.quickCaptureHotkey.dialogTitle':
        return '快速记录快捷键';
      case 'settings.quickCaptureHotkey.dialogBody':
        return '按下新的按键组合来录制快捷键。';
      case 'settings.quickCaptureHotkey.saved':
        return '快速记录快捷键已更新';
      case 'settings.quickCaptureHotkey.actions.resetDefault':
        return '恢复默认';
      case 'settings.quickCaptureHotkey.validation.missingModifier':
        return '至少包含一个修饰键（Ctrl/Alt/Shift 等）';
      case 'settings.quickCaptureHotkey.validation.modifierOnly':
        return '快捷键必须包含一个非修饰键。';
      case 'settings.quickCaptureHotkey.validation.systemConflict':
        return ({required Object name}) => '与系统快捷键冲突：${name}';
      case 'settings.quickCaptureHotkey.conflicts.macosSpotlight':
        return 'Spotlight';
      case 'settings.quickCaptureHotkey.conflicts.macosFinderSearch':
        return 'Finder 搜索';
      case 'settings.quickCaptureHotkey.conflicts.macosInputSourceSwitch':
        return '切换输入法';
      case 'settings.quickCaptureHotkey.conflicts.macosEmojiPicker':
        return '表情与符号';
      case 'settings.quickCaptureHotkey.conflicts.macosScreenshot':
        return '截屏';
      case 'settings.quickCaptureHotkey.conflicts.macosAppSwitcher':
        return '应用切换器';
      case 'settings.quickCaptureHotkey.conflicts.macosForceQuit':
        return '强制退出';
      case 'settings.quickCaptureHotkey.conflicts.macosLockScreen':
        return '锁定屏幕';
      case 'settings.quickCaptureHotkey.conflicts.windowsLock':
        return '锁定屏幕';
      case 'settings.quickCaptureHotkey.conflicts.windowsShowDesktop':
        return '显示桌面';
      case 'settings.quickCaptureHotkey.conflicts.windowsFileExplorer':
        return '文件资源管理器';
      case 'settings.quickCaptureHotkey.conflicts.windowsRun':
        return '运行';
      case 'settings.quickCaptureHotkey.conflicts.windowsSearch':
        return '搜索';
      case 'settings.quickCaptureHotkey.conflicts.windowsSettings':
        return '设置';
      case 'settings.quickCaptureHotkey.conflicts.windowsTaskView':
        return '任务视图';
      case 'settings.quickCaptureHotkey.conflicts.windowsLanguageSwitch':
        return '切换输入法';
      case 'settings.quickCaptureHotkey.conflicts.windowsAppSwitcher':
        return '应用切换器';
      case 'settings.desktopBoot.startWithSystem.title':
        return '随系统启动';
      case 'settings.desktopBoot.startWithSystem.subtitle':
        return '登录系统后自动启动 SecondLoop';
      case 'settings.desktopBoot.silentStartup.title':
        return '静默启动';
      case 'settings.desktopBoot.silentStartup.subtitle':
        return '自动启动时在后台运行，不弹出主窗口';
      case 'settings.desktopBoot.keepRunningInBackground.title':
        return '关闭时常驻后台';
      case 'settings.desktopBoot.keepRunningInBackground.subtitle':
        return '关闭窗口时最小化到通知栏，而不是直接退出';
      case 'settings.desktopTray.menu.hide':
        return '隐藏';
      case 'settings.desktopTray.menu.quit':
        return '退出';
      case 'settings.desktopTray.pro.signedIn':
        return '已登录';
      case 'settings.desktopTray.pro.aiUsage':
        return 'AI 用量';
      case 'settings.desktopTray.pro.storageUsage':
        return '存储用量';
      case 'settings.language.title':
        return '语言';
      case 'settings.language.subtitle':
        return '跟随系统或手动选择语言';
      case 'settings.language.dialogTitle':
        return '语言';
      case 'settings.language.options.system':
        return '系统';
      case 'settings.language.options.systemWithValue':
        return ({required Object value}) => '系统（${value}）';
      case 'settings.language.options.en':
        return 'English';
      case 'settings.language.options.zhCn':
        return '简体中文';
      case 'settings.theme.title':
        return '主题';
      case 'settings.theme.subtitle':
        return '跟随系统，或选择明亮/深色';
      case 'settings.theme.dialogTitle':
        return '主题';
      case 'settings.theme.options.system':
        return '系统';
      case 'settings.theme.options.light':
        return '明亮';
      case 'settings.theme.options.dark':
        return '深色';
      case 'settings.autoLock.title':
        return '自动锁定';
      case 'settings.autoLock.subtitle':
        return '需要解锁才能访问应用';
      case 'settings.systemUnlock.titleMobile':
        return '使用生物识别';
      case 'settings.systemUnlock.titleDesktop':
        return '使用系统解锁';
      case 'settings.systemUnlock.subtitleMobile':
        return '使用生物识别解锁，而不是主密码';
      case 'settings.systemUnlock.subtitleDesktop':
        return '使用 Touch ID / Windows Hello 解锁，而不是主密码';
      case 'settings.lockNow.title':
        return '立即锁定';
      case 'settings.lockNow.subtitle':
        return '返回解锁页面';
      case 'settings.llmProfiles.title':
        return 'API Key（AI 对话）';
      case 'settings.llmProfiles.subtitle':
        return '高级：使用你自己的服务商与 Key';
      case 'settings.embeddingProfiles.title':
        return 'API Key（语义搜索）';
      case 'settings.embeddingProfiles.subtitle':
        return '高级：使用你自己的服务商与 Key';
      case 'settings.aiSelection.title':
        return '智能化';
      case 'settings.aiSelection.subtitle':
        return '统一设置 AI 问答、智能检索（Embedding）、图片读字（OCR）和语音转文字。';
      case 'settings.aiSelection.askAi.title':
        return 'AI 对话';
      case 'settings.aiSelection.askAi.description':
        return '决定“AI 对话”使用哪种服务来源（Cloud 或 API 密钥）。';
      case 'settings.aiSelection.askAi.setupHint':
        return '还没完成“AI 对话”设置，请先登录 Cloud 或添加 API 密钥。';
      case 'settings.aiSelection.askAi.preferenceUnavailableHint':
        return '你选择的“AI 对话”来源暂时不可用，请先完成 Cloud 或 API 密钥设置。';
      case 'settings.aiSelection.askAi.status.loading':
        return '正在检查当前使用来源...';
      case 'settings.aiSelection.askAi.status.cloud':
        return '当前使用：SecondLoop Cloud';
      case 'settings.aiSelection.askAi.status.byok':
        return '当前使用：API 密钥（BYOK）';
      case 'settings.aiSelection.askAi.status.notConfigured':
        return '当前使用：未完成设置';
      case 'settings.aiSelection.askAi.preference.auto.title':
        return '自动';
      case 'settings.aiSelection.askAi.preference.auto.description':
        return '自动选择可用服务：优先 Cloud，不可用时改用 API 密钥（BYOK）。';
      case 'settings.aiSelection.askAi.preference.cloud.title':
        return 'SecondLoop Cloud';
      case 'settings.aiSelection.askAi.preference.cloud.description':
        return '固定使用 Cloud。Cloud 不可用时，“AI 对话”会暂时不可用。';
      case 'settings.aiSelection.askAi.preference.byok.title':
        return 'API 密钥（BYOK）';
      case 'settings.aiSelection.askAi.preference.byok.description':
        return '固定使用你自己的 API 密钥（BYOK）。没有可用配置时，“AI 对话”会暂时不可用。';
      case 'settings.aiSelection.askAi.actions.openCloud':
        return '打开 Cloud 账户';
      case 'settings.aiSelection.askAi.actions.openByok':
        return '打开 API 密钥';
      case 'settings.aiSelection.embeddings.title':
        return '智能检索（Embedding）';
      case 'settings.aiSelection.embeddings.description':
        return '给消息和待办生成检索索引，这是基础智能检索能力；开启下方“云端增强检索”后，结果通常更准确。';
      case 'settings.aiSelection.embeddings.preferenceUnavailableHint':
        return '你选择的智能检索来源暂时不可用，已自动切换到可用方案。';
      case 'settings.aiSelection.embeddings.status.loading':
        return '正在检查当前使用来源...';
      case 'settings.aiSelection.embeddings.status.cloud':
        return '当前使用：SecondLoop Cloud';
      case 'settings.aiSelection.embeddings.status.byok':
        return '当前使用：API 密钥（Embedding/BYOK）';
      case 'settings.aiSelection.embeddings.status.local':
        return '当前使用：本机智能检索';
      case 'settings.aiSelection.embeddings.preference.auto.title':
        return '自动';
      case 'settings.aiSelection.embeddings.preference.auto.description':
        return '自动选择：优先 Cloud，其次 API 密钥（BYOK），最后本机能力。';
      case 'settings.aiSelection.embeddings.preference.cloud.title':
        return 'SecondLoop Cloud';
      case 'settings.aiSelection.embeddings.preference.cloud.description':
        return '优先使用 Cloud。Cloud 不可用时自动切换到 API 密钥或本机能力。';
      case 'settings.aiSelection.embeddings.preference.byok.title':
        return 'API 密钥（BYOK）';
      case 'settings.aiSelection.embeddings.preference.byok.description':
        return '优先使用 API 密钥（BYOK）。失败时自动切换到本机能力。';
      case 'settings.aiSelection.embeddings.preference.local.title':
        return '本地能力';
      case 'settings.aiSelection.embeddings.preference.local.description':
        return '尽量只在本机生成检索索引（Embedding）。';
      case 'settings.aiSelection.embeddings.actions.openEmbeddingProfiles':
        return '打开向量 API 密钥';
      case 'settings.aiSelection.embeddings.actions.openCloudAccount':
        return '打开 Cloud 账户';
      case 'settings.aiSelection.mediaUnderstanding.title':
        return '图片与音频理解';
      case 'settings.aiSelection.mediaUnderstanding.description':
        return '决定图片读字（OCR）、图片说明和语音转文字由谁处理。';
      case 'settings.aiSelection.mediaUnderstanding.preferenceUnavailableHint':
        return '你选择的图片/音频处理来源暂时不可用，已自动切换到可用方案。';
      case 'settings.aiSelection.mediaUnderstanding.status.loading':
        return '正在检查当前使用来源...';
      case 'settings.aiSelection.mediaUnderstanding.status.cloud':
        return '当前使用：SecondLoop Cloud';
      case 'settings.aiSelection.mediaUnderstanding.status.byok':
        return '当前使用：API 密钥（BYOK）';
      case 'settings.aiSelection.mediaUnderstanding.status.local':
        return '当前使用：本机能力（系统自带）';
      case 'settings.aiSelection.mediaUnderstanding.preference.auto.title':
        return '自动';
      case 'settings.aiSelection.mediaUnderstanding.preference.auto.description':
        return '自动选择：优先 Cloud，其次 API 密钥（BYOK），最后本机能力。';
      case 'settings.aiSelection.mediaUnderstanding.preference.cloud.title':
        return 'SecondLoop Cloud';
      case 'settings.aiSelection.mediaUnderstanding.preference.cloud.description':
        return '优先使用 Cloud。Cloud 不可用时自动切换到 API 密钥或本机能力。';
      case 'settings.aiSelection.mediaUnderstanding.preference.byok.title':
        return 'API 密钥（BYOK）';
      case 'settings.aiSelection.mediaUnderstanding.preference.byok.description':
        return '优先使用 API 密钥（BYOK）。失败时自动切换到本机能力。';
      case 'settings.aiSelection.mediaUnderstanding.preference.local.title':
        return '本地能力';
      case 'settings.aiSelection.mediaUnderstanding.preference.local.description':
        return '优先使用本机能力（系统自带）。';
      case 'settings.aiSelection.mediaUnderstanding.actions.openSettings':
        return '打开媒体理解设置';
      case 'settings.aiSelection.mediaUnderstanding.actions.openCloudAccount':
        return '打开 Cloud 账户';
      case 'settings.aiSelection.mediaUnderstanding.actions.openByok':
        return '打开 API 密钥';
      case 'settings.semanticParseAutoActions.title':
        return '更智能的语义分析';
      case 'settings.semanticParseAutoActions.subtitleEnabled':
        return '已开启增强模式。在本地语义分析基础上，会使用 Cloud/BYOK 提升自动整理准确度。';
      case 'settings.semanticParseAutoActions.subtitleDisabled':
        return '已关闭增强模式。仍会使用本地语义分析。';
      case 'settings.semanticParseAutoActions.subtitleUnset':
        return '尚未设置，默认关闭增强模式（仍会使用本地语义分析）。';
      case 'settings.semanticParseAutoActions.subtitleRequiresSetup':
        return '需先登录 SecondLoop Pro 或配置 API 密钥（BYOK）后，才能开启增强模式。';
      case 'settings.semanticParseAutoActions.dialogTitle':
        return '开启更智能的语义分析？';
      case 'settings.semanticParseAutoActions.dialogBody':
        return '本地语义分析始终开启。开启增强模式后，SecondLoop 会在本地分析基础上，将消息文本发送给 AI 做更智能的语义理解（Semantic Parse）。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这会消耗 Cloud 额度或你自己的服务商额度。';
      case 'settings.semanticParseAutoActions.dialogActions.enable':
        return '开启';
      case 'settings.mediaAnnotation.title':
        return '媒体理解';
      case 'settings.mediaAnnotation.subtitle':
        return '可选：OCR、图片注释与音频转写，增强检索与存储体验';
      case 'settings.mediaAnnotation.routingGuide.title':
        return '先选择 AI 来源';
      case 'settings.mediaAnnotation.routingGuide.pro':
        return 'Pro 且已登录：默认使用 SecondLoop Cloud。';
      case 'settings.mediaAnnotation.routingGuide.byok':
        return '免费/BYOK：请先在「AI 对话」里添加 OpenAI-compatible 配置档，并设为当前使用。';
      case 'settings.mediaAnnotation.documentOcr.title':
        return '文档 OCR';
      case 'settings.mediaAnnotation.documentOcr.enabled.title':
        return '启用 OCR';
      case 'settings.mediaAnnotation.documentOcr.enabled.subtitle':
        return '当文档文本提取不足时，对扫描 PDF 和视频关键帧执行 OCR。';
      case 'settings.mediaAnnotation.documentOcr.languageHints.title':
        return '语言提示';
      case 'settings.mediaAnnotation.documentOcr.languageHints.subtitle':
        return '选择 OCR 识别优先语言。';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.devicePlusEn':
        return '设备语言 + 英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.en':
        return '英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.zhEn':
        return '中文 + 英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.jaEn':
        return '日文 + 英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.koEn':
        return '韩文 + 英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.frEn':
        return '法文 + 英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.deEn':
        return '德文 + 英文';
      case 'settings.mediaAnnotation.documentOcr.languageHints.labels.esEn':
        return '西班牙文 + 英文';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.title':
        return '自动 OCR 页数上限';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.subtitle':
        return '超过该页数的 PDF 会保持 needs_ocr，需在查看页手动执行。';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.manualOnly':
        return '仅手动';
      case 'settings.mediaAnnotation.documentOcr.pdfAutoMaxPages.pages':
        return ({required Object count}) => '${count} 页';
      case 'settings.mediaAnnotation.documentOcr.pdfDpi.title':
        return 'OCR DPI';
      case 'settings.mediaAnnotation.documentOcr.pdfDpi.subtitle':
        return '更高 DPI 可能提升识别率，但处理更慢。';
      case 'settings.mediaAnnotation.documentOcr.pdfDpi.value':
        return ({required Object dpi}) => '${dpi} dpi';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.title':
        return '桌面 OCR 模型';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.subtitle':
        return '为桌面端（Linux/macOS/Windows）下载本地 OCR 模型文件。';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.notInstalled':
        return '未安装';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.runtimeMissing':
        return '模型已下载，但 OCR 运行环境未就绪';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.downloading':
        return '下载中...';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.status.installed':
        return ({required Object count, required Object size}) =>
            '已安装：${count} 个文件（${size}）';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.actions.download':
        return '下载模型';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.actions.redownload':
        return '重新下载';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.actions.delete':
        return '删除模型';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete.title':
        return '删除已下载 OCR 模型？';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete.body':
        return '删除后，桌面端本地 OCR 可能不可用，直到再次下载。';
      case 'settings.mediaAnnotation.documentOcr.linuxModels.confirmDelete.confirm':
        return '删除';
      case 'settings.mediaAnnotation.audioTranscribe.title':
        return '音频转写';
      case 'settings.mediaAnnotation.audioTranscribe.enabled.title':
        return '转写音频附件';
      case 'settings.mediaAnnotation.audioTranscribe.enabled.subtitle':
        return '添加音频后，SecondLoop 可自动转写并保存加密文本，用于播放与搜索。';
      case 'settings.mediaAnnotation.audioTranscribe.engine.title':
        return '转写引擎';
      case 'settings.mediaAnnotation.audioTranscribe.engine.subtitle':
        return '选择音频转写使用的引擎。';
      case 'settings.mediaAnnotation.audioTranscribe.engine.notAvailable':
        return '不可用';
      case 'settings.mediaAnnotation.audioTranscribe.engine.labels.whisper':
        return 'Whisper';
      case 'settings.mediaAnnotation.audioTranscribe.engine.labels.multimodalLlm':
        return '多模态 LLM';
      case 'settings.mediaAnnotation.audioTranscribe.engine.labels.auto':
        return '自动';
      case 'settings.mediaAnnotation.audioTranscribe.engine.descriptions.whisper':
        return '语音转写稳定默认方案（推荐）。';
      case 'settings.mediaAnnotation.audioTranscribe.engine.descriptions.multimodalLlm':
        return '可用时使用多模态聊天模型。';
      case 'settings.mediaAnnotation.audioTranscribe.engine.descriptions.auto':
        return '由 SecondLoop 自动选择最可用的引擎。';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.title':
        return '配置转写 API';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.subtitle':
        return 'Pro 用户可用 SecondLoop Cloud；免费用户可用「AI 对话」中的 OpenAI-compatible API Key 配置档。';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.body':
        return '音频转写可使用 SecondLoop Cloud（需要 Pro + 登录）或“AI 对话”里的 OpenAI-compatible API Key 配置档。';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.openCloud':
        return '打开 Cloud 账号';
      case 'settings.mediaAnnotation.audioTranscribe.configureApi.openApiKeys':
        return '打开 API Key';
      case 'settings.mediaAnnotation.imageCaption.title':
        return '图片注释';
      case 'settings.mediaAnnotation.providerSettings.title':
        return '图片注释服务来源';
      case 'settings.mediaAnnotation.setupRequired.title':
        return '图片注释需要先配置';
      case 'settings.mediaAnnotation.setupRequired.body':
        return '要注释图片，SecondLoop 需要一个多模态模型。';
      case 'settings.mediaAnnotation.setupRequired.reasons.cloudUnavailable':
        return '当前构建未启用 SecondLoop Cloud。';
      case 'settings.mediaAnnotation.setupRequired.reasons.cloudRequiresPro':
        return 'SecondLoop Cloud 需要 Pro。';
      case 'settings.mediaAnnotation.setupRequired.reasons.cloudSignIn':
        return '请先登录 SecondLoop Cloud。';
      case 'settings.mediaAnnotation.setupRequired.reasons.byokOpenAiCompatible':
        return '请先添加 OpenAI-compatible 的 API Key 配置档。';
      case 'settings.mediaAnnotation.setupRequired.reasons.followAskAi':
        return '“AI 对话”需要使用 OpenAI-compatible 配置档，或在高级设置里选择其它多模态模型。';
      case 'settings.mediaAnnotation.annotateEnabled.title':
        return '注释图片';
      case 'settings.mediaAnnotation.annotateEnabled.subtitle':
        return '添加图片后，SecondLoop 可能会将图片发送给 AI 生成加密注释。';
      case 'settings.mediaAnnotation.searchEnabled.title':
        return '注释用于搜索';
      case 'settings.mediaAnnotation.searchEnabled.subtitle':
        return '将图片注释加入搜索索引。';
      case 'settings.mediaAnnotation.searchToggleConfirm.title':
        return '更新搜索索引？';
      case 'settings.mediaAnnotation.searchToggleConfirm.bodyEnable':
        return '开启后会重新生成搜索数据，让图片注释可被检索。';
      case 'settings.mediaAnnotation.searchToggleConfirm.bodyDisable':
        return '关闭后会重新生成搜索数据，从检索中移除图片注释。';
      case 'settings.mediaAnnotation.advanced.title':
        return '高级设置';
      case 'settings.mediaAnnotation.providerMode.title':
        return '多模态模型';
      case 'settings.mediaAnnotation.providerMode.subtitle':
        return '为图片注释选择独立于“AI 对话”的服务商/模型。';
      case 'settings.mediaAnnotation.providerMode.labels.followAskAi':
        return '跟随 AI 对话';
      case 'settings.mediaAnnotation.providerMode.labels.cloudGateway':
        return 'SecondLoop Cloud';
      case 'settings.mediaAnnotation.providerMode.labels.byokProfile':
        return 'API Key（配置档）';
      case 'settings.mediaAnnotation.providerMode.descriptions.followAskAi':
        return '使用与“AI 对话”相同的设置（推荐）。';
      case 'settings.mediaAnnotation.providerMode.descriptions.cloudGateway':
        return '优先使用 SecondLoop Cloud（需要 Pro，且需可用）。';
      case 'settings.mediaAnnotation.providerMode.descriptions.byokProfile':
        return '使用指定的 API Key 配置档（仅支持 OpenAI-compatible）。';
      case 'settings.mediaAnnotation.cloudModelName.title':
        return 'Cloud 模型名';
      case 'settings.mediaAnnotation.cloudModelName.subtitle':
        return '可选：覆盖云端多模态模型名。';
      case 'settings.mediaAnnotation.cloudModelName.hint':
        return '例如 gpt-4o-mini';
      case 'settings.mediaAnnotation.cloudModelName.followAskAi':
        return '跟随 AI 对话';
      case 'settings.mediaAnnotation.byokProfile.title':
        return 'API Key 配置档';
      case 'settings.mediaAnnotation.byokProfile.subtitle':
        return '选择图片注释使用哪个配置档。';
      case 'settings.mediaAnnotation.byokProfile.unset':
        return '未设置';
      case 'settings.mediaAnnotation.byokProfile.missingBackend':
        return '当前构建不可用。';
      case 'settings.mediaAnnotation.byokProfile.noOpenAiCompatibleProfiles':
        return '没有可用的 OpenAI-compatible 配置档，请先在“API Key（AI 对话）”里添加。';
      case 'settings.mediaAnnotation.allowCellular.title':
        return '允许蜂窝网络';
      case 'settings.mediaAnnotation.allowCellular.subtitle':
        return '允许用蜂窝网络进行图片注释（默认仅 Wi‑Fi）。';
      case 'settings.mediaAnnotation.allowCellularConfirm.title':
        return '允许使用蜂窝网络注释图片？';
      case 'settings.mediaAnnotation.allowCellularConfirm.body':
        return '图片注释可能会向你选择的 AI 服务商上传图片，并消耗一定流量。';
      case 'settings.cloudEmbeddings.title':
        return '云端增强检索（Embedding）';
      case 'settings.cloudEmbeddings.subtitleEnabled':
        return '已开启。在智能检索基础上，额外使用 Cloud 生成索引，搜索和回忆通常更准确。';
      case 'settings.cloudEmbeddings.subtitleDisabled':
        return '已关闭。你仍可使用智能检索，但仅使用本机索引。';
      case 'settings.cloudEmbeddings.subtitleUnset':
        return '尚未设置，首次需要云端增强时会询问你是否开启。';
      case 'settings.cloudEmbeddings.subtitleRequiresPro':
        return '需要 SecondLoop Pro。';
      case 'settings.cloudEmbeddings.dialogTitle':
        return '开启云端增强检索？';
      case 'settings.cloudEmbeddings.dialogBody':
        return '“智能检索”默认使用本机索引。开启后，SecondLoop 可以将少量文本（消息预览、待办标题、跟进）发送到 SecondLoop Cloud 生成更高质量的检索索引（Embedding），从而提高搜索和回忆准确度。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这会消耗 Cloud 额度。';
      case 'settings.cloudEmbeddings.dialogActions.enable':
        return '开启';
      case 'settings.cloudAccount.title':
        return 'Cloud 账号';
      case 'settings.cloudAccount.subtitle':
        return '登录 SecondLoop Cloud';
      case 'settings.cloudAccount.signedInAs':
        return ({required Object email}) => '已登录：${email}';
      case 'settings.cloudAccount.benefits.title':
        return '创建 Cloud 账号以购买订阅';
      case 'settings.cloudAccount.benefits.items.purchase.title':
        return '购买 SecondLoop Pro 订阅';
      case 'settings.cloudAccount.benefits.items.purchase.body':
        return '需要 Cloud 账号才能开通订阅。';
      case 'settings.cloudAccount.errors.missingWebApiKey':
        return '当前版本暂不支持 Cloud 登录。如果你是从源码运行，请先执行 `pixi run init-env`（或复制 `.env.example` → `.env.local`），填入 `SECONDLOOP_FIREBASE_WEB_API_KEY`，然后重启 App。';
      case 'settings.cloudAccount.fields.email':
        return '邮箱';
      case 'settings.cloudAccount.fields.password':
        return '密码';
      case 'settings.cloudAccount.actions.signIn':
        return '登录';
      case 'settings.cloudAccount.actions.signUp':
        return '创建账号';
      case 'settings.cloudAccount.actions.signOut':
        return '退出登录';
      case 'settings.cloudAccount.emailVerification.title':
        return '邮箱验证';
      case 'settings.cloudAccount.emailVerification.status.unknown':
        return '未知';
      case 'settings.cloudAccount.emailVerification.status.verified':
        return '已验证';
      case 'settings.cloudAccount.emailVerification.status.notVerified':
        return '未验证';
      case 'settings.cloudAccount.emailVerification.labels.status':
        return '状态：';
      case 'settings.cloudAccount.emailVerification.labels.help':
        return '验证邮箱后才能使用 SecondLoop Cloud 的 AI 对话。';
      case 'settings.cloudAccount.emailVerification.labels.verifiedHelp':
        return '邮箱已验证，可继续订阅。';
      case 'settings.cloudAccount.emailVerification.labels.loadFailed':
        return ({required Object error}) => '加载失败：${error}';
      case 'settings.cloudAccount.emailVerification.actions.resend':
        return '重新发送验证邮件';
      case 'settings.cloudAccount.emailVerification.actions.resendCooldown':
        return ({required Object seconds}) => '${seconds} 秒后可重新发送';
      case 'settings.cloudAccount.emailVerification.messages.verificationEmailSent':
        return '验证邮件已发送';
      case 'settings.cloudAccount.emailVerification.messages.verificationAlreadyDone':
        return '邮箱已完成验证。';
      case 'settings.cloudAccount.emailVerification.messages.signUpVerificationPrompt':
        return '账号已创建，请先完成邮箱验证再进行订阅。';
      case 'settings.cloudAccount.emailVerification.messages.verificationEmailSendFailed':
        return ({required Object error}) => '发送验证邮件失败：${error}';
      case 'settings.cloudUsage.title':
        return '云端用量';
      case 'settings.cloudUsage.subtitle':
        return '当前账期用量';
      case 'settings.cloudUsage.actions.refresh':
        return '刷新';
      case 'settings.cloudUsage.labels.gatewayNotConfigured':
        return '当前版本暂不支持查看云端用量。';
      case 'settings.cloudUsage.labels.signInRequired':
        return '登录后才能查看用量。';
      case 'settings.cloudUsage.labels.usage':
        return '用量：';
      case 'settings.cloudUsage.labels.askAiUsage':
        return 'AI 对话：';
      case 'settings.cloudUsage.labels.embeddingsUsage':
        return '智能搜索：';
      case 'settings.cloudUsage.labels.inputTokensUsed30d':
        return '输入 Tokens（30 天）：';
      case 'settings.cloudUsage.labels.outputTokensUsed30d':
        return '输出 Tokens（30 天）：';
      case 'settings.cloudUsage.labels.tokensUsed30d':
        return 'Tokens（30 天）：';
      case 'settings.cloudUsage.labels.requestsUsed30d':
        return '请求数（30 天）：';
      case 'settings.cloudUsage.labels.resetAt':
        return '重置时间：';
      case 'settings.cloudUsage.labels.paymentRequired':
        return '需订阅后才能查看云端用量。';
      case 'settings.cloudUsage.labels.loadFailed':
        return ({required Object error}) => '加载失败：${error}';
      case 'settings.vaultUsage.title':
        return '云端存储';
      case 'settings.vaultUsage.subtitle':
        return '你的同步数据占用的云端存储';
      case 'settings.vaultUsage.actions.refresh':
        return '刷新';
      case 'settings.vaultUsage.labels.notConfigured':
        return '当前版本暂不支持查看云端存储用量。';
      case 'settings.vaultUsage.labels.signInRequired':
        return '登录后才能查看云端存储用量。';
      case 'settings.vaultUsage.labels.used':
        return '已用：';
      case 'settings.vaultUsage.labels.limit':
        return '上限：';
      case 'settings.vaultUsage.labels.attachments':
        return '照片与文件：';
      case 'settings.vaultUsage.labels.ops':
        return '同步记录：';
      case 'settings.vaultUsage.labels.loadFailed':
        return ({required Object error}) => '加载失败：${error}';
      case 'settings.diagnostics.title':
        return '诊断信息';
      case 'settings.diagnostics.subtitle':
        return '导出诊断信息以便支持排查';
      case 'settings.diagnostics.privacyNote':
        return '该报告不会包含你的记录正文或 API Key。';
      case 'settings.diagnostics.loading':
        return '正在加载诊断信息…';
      case 'settings.diagnostics.messages.copied':
        return '诊断信息已复制';
      case 'settings.diagnostics.messages.copyFailed':
        return ({required Object error}) => '复制诊断信息失败：${error}';
      case 'settings.diagnostics.messages.shareFailed':
        return ({required Object error}) => '分享诊断信息失败：${error}';
      case 'settings.byokUsage.title':
        return 'API Key 用量';
      case 'settings.byokUsage.subtitle':
        return '当前配置 • 请求数与 Token（如可获取）';
      case 'settings.byokUsage.loading':
        return '加载中…';
      case 'settings.byokUsage.noData':
        return '暂无数据';
      case 'settings.byokUsage.errors.unavailable':
        return ({required Object error}) => '用量不可用：${error}';
      case 'settings.byokUsage.sections.today':
        return ({required Object day}) => '今日（${day}）';
      case 'settings.byokUsage.sections.last30d':
        return ({required Object start, required Object end}) =>
            '近 30 天（${start} → ${end}）';
      case 'settings.byokUsage.labels.requests':
        return ({required Object purpose}) => '${purpose} 请求数';
      case 'settings.byokUsage.labels.tokens':
        return ({required Object purpose}) => '${purpose} tokens（输入/输出/总计）';
      case 'settings.byokUsage.purposes.semanticParse':
        return '语义解析';
      case 'settings.byokUsage.purposes.mediaAnnotation':
        return '图片注释';
      case 'settings.subscription.title':
        return '订阅';
      case 'settings.subscription.subtitle':
        return '管理 SecondLoop Pro';
      case 'settings.subscription.benefits.title':
        return 'SecondLoop Pro 可解锁';
      case 'settings.subscription.benefits.items.noSetup.title':
        return '免配置直接用 AI';
      case 'settings.subscription.benefits.items.noSetup.body':
        return '不用做任何配置，订阅后就能直接使用 AI 对话。';
      case 'settings.subscription.benefits.items.cloudSync.title':
        return '云存储 + 多设备同步';
      case 'settings.subscription.benefits.items.cloudSync.body':
        return '手机/电脑自动同步，换设备也不丢。';
      case 'settings.subscription.benefits.items.mobileSearch.title':
        return '手机也能按意思搜索';
      case 'settings.subscription.benefits.items.mobileSearch.body':
        return '就算记不住原话，用相近的说法也能搜到。';
      case 'settings.subscription.status.unknown':
        return '未知';
      case 'settings.subscription.status.entitled':
        return '已生效';
      case 'settings.subscription.status.notEntitled':
        return '未生效';
      case 'settings.subscription.actions.purchase':
        return '订阅';
      case 'settings.subscription.labels.status':
        return '状态：';
      case 'settings.subscription.labels.purchaseUnavailable':
        return '订阅购买暂未开放。';
      case 'settings.subscription.labels.loadFailed':
        return ({required Object error}) => '加载失败：${error}';
      case 'settings.sync.title':
        return '同步';
      case 'settings.sync.subtitle':
        return '选择同步存储位置（SecondLoop Cloud / WebDAV 网盘 / 本地文件夹）';
      case 'settings.resetLocalDataThisDeviceOnly.dialogTitle':
        return '重置本地数据？';
      case 'settings.resetLocalDataThisDeviceOnly.dialogBody':
        return '这将删除本地消息，并清空「当前设备」已同步的远端数据（不影响其他设备）。不会删除你的主密码或本地 AI/同步设置。你需要重新解锁。';
      case 'settings.resetLocalDataThisDeviceOnly.failed':
        return ({required Object error}) => '重置失败：${error}';
      case 'settings.resetLocalDataAllDevices.dialogTitle':
        return '重置本地数据？';
      case 'settings.resetLocalDataAllDevices.dialogBody':
        return '这将删除本地消息，并清空「所有设备」已同步的远端数据。不会删除你的主密码或本地 AI/同步设置。你需要重新解锁。';
      case 'settings.resetLocalDataAllDevices.failed':
        return ({required Object error}) => '重置失败：${error}';
      case 'settings.debugResetLocalDataThisDeviceOnly.title':
        return '调试：重置本地数据（仅本设备）';
      case 'settings.debugResetLocalDataThisDeviceOnly.subtitle':
        return '删除本地消息 + 清空本设备远端数据（其他设备保留）';
      case 'settings.debugResetLocalDataAllDevices.title':
        return '调试：重置本地数据（所有设备）';
      case 'settings.debugResetLocalDataAllDevices.subtitle':
        return '删除本地消息 + 清空所有设备远端数据';
      case 'settings.debugSemanticSearch.title':
        return '调试：语义检索';
      case 'settings.debugSemanticSearch.subtitle':
        return '搜索相似消息 + 重建向量索引';
      case 'lock.masterPasswordRequired':
        return '需要主密码';
      case 'lock.passwordsDoNotMatch':
        return '两次输入的密码不一致';
      case 'lock.setupTitle':
        return '设置主密码';
      case 'lock.unlockTitle':
        return '解锁';
      case 'lock.unlockReason':
        return '解锁 SecondLoop';
      case 'lock.missingSavedSessionKey':
        return '缺少已保存的会话密钥。请先用主密码解锁一次。';
      case 'lock.creating':
        return '正在创建…';
      case 'lock.unlocking':
        return '正在解锁…';
      case 'chat.mainStreamTitle':
        return '主线';
      case 'chat.attachTooltip':
        return '添加附件';
      case 'chat.attachPickMedia':
        return '选择媒体文件';
      case 'chat.attachTakePhoto':
        return '拍照';
      case 'chat.attachRecordAudio':
        return '录音';
      case 'chat.switchToVoiceInput':
        return '切换到语音输入';
      case 'chat.switchToKeyboardInput':
        return '切换到键盘输入';
      case 'chat.holdToTalk':
        return '按住说话';
      case 'chat.releaseToConvert':
        return '松开后转为文字';
      case 'chat.recordingInProgress':
        return '正在录音…';
      case 'chat.recordingHint':
        return '点击停止发送音频，或点击取消放弃。';
      case 'chat.cameraTooltip':
        return '拍照';
      case 'chat.photoMessage':
        return '照片';
      case 'chat.editMessageTitle':
        return '编辑消息';
      case 'chat.messageUpdated':
        return '消息已更新';
      case 'chat.messageDeleted':
        return '消息已删除';
      case 'chat.deleteMessageDialog.title':
        return '删除信息？';
      case 'chat.deleteMessageDialog.message':
        return '这将永久删除该信息及其附件。';
      case 'chat.photoFailed':
        return ({required Object error}) => '拍照失败：${error}';
      case 'chat.audioRecordPermissionDenied':
        return '需要麦克风权限才能录音。';
      case 'chat.audioRecordFailed':
        return ({required Object error}) => '录音失败：${error}';
      case 'chat.editFailed':
        return ({required Object error}) => '编辑失败：${error}';
      case 'chat.deleteFailed':
        return ({required Object error}) => '删除失败：${error}';
      case 'chat.noMessagesYet':
        return '暂无消息';
      case 'chat.viewFull':
        return '查看全文';
      case 'chat.messageActions.convertToTodo':
        return '转化为待办项';
      case 'chat.messageActions.convertTodoToInfo':
        return '转为普通信息';
      case 'chat.messageActions.convertTodoToInfoConfirmTitle':
        return '转为普通信息？';
      case 'chat.messageActions.convertTodoToInfoConfirmBody':
        return '这会移除该事项，但保留原消息内容。';
      case 'chat.messageActions.openTodo':
        return '跳转到事项';
      case 'chat.messageActions.linkOtherTodo':
        return '关联到其他事项';
      case 'chat.messageViewer.title':
        return '全文';
      case 'chat.markdownEditor.openButton':
        return 'Markdown';
      case 'chat.markdownEditor.title':
        return 'Markdown 编辑器';
      case 'chat.markdownEditor.apply':
        return '应用';
      case 'chat.markdownEditor.editorLabel':
        return '编辑区';
      case 'chat.markdownEditor.previewLabel':
        return '预览区';
      case 'chat.markdownEditor.emptyPreview':
        return '输入后会在这里实时预览。';
      case 'chat.markdownEditor.shortcutHint':
        return '提示：按 Cmd/Ctrl + Enter 可快速应用内容。';
      case 'chat.markdownEditor.listContinuationHint':
        return '在列表项中按 Enter 可自动续写列表。';
      case 'chat.markdownEditor.quickActionsLabel':
        return '快捷格式';
      case 'chat.markdownEditor.themeLabel':
        return '预览主题';
      case 'chat.markdownEditor.themeStudio':
        return '经典';
      case 'chat.markdownEditor.themePaper':
        return '纸张';
      case 'chat.markdownEditor.themeOcean':
        return '海洋';
      case 'chat.markdownEditor.themeNight':
        return '夜色';
      case 'chat.markdownEditor.exportMenu':
        return '导出预览';
      case 'chat.markdownEditor.exportPng':
        return '导出为 PNG';
      case 'chat.markdownEditor.exportPdf':
        return '导出为 PDF';
      case 'chat.markdownEditor.exportDone':
        return ({required Object format}) => '已导出为 ${format}';
      case 'chat.markdownEditor.exportSavedPath':
        return ({required Object path}) => '已保存到：${path}';
      case 'chat.markdownEditor.exportFailed':
        return ({required Object error}) => '导出失败：${error}';
      case 'chat.markdownEditor.stats':
        return ({required Object lines, required Object characters}) =>
            '${lines} 行 · ${characters} 字符';
      case 'chat.markdownEditor.simpleInput':
        return '简易输入';
      case 'chat.markdownEditor.actions.heading':
        return '标题';
      case 'chat.markdownEditor.actions.headingLevel':
        return ({required Object level}) => '${level} 级标题';
      case 'chat.markdownEditor.actions.bold':
        return '加粗';
      case 'chat.markdownEditor.actions.italic':
        return '斜体';
      case 'chat.markdownEditor.actions.strike':
        return '删除线';
      case 'chat.markdownEditor.actions.code':
        return '行内代码';
      case 'chat.markdownEditor.actions.link':
        return '插入链接';
      case 'chat.markdownEditor.actions.blockquote':
        return '引用';
      case 'chat.markdownEditor.actions.bulletList':
        return '无序列表';
      case 'chat.markdownEditor.actions.orderedList':
        return '有序列表';
      case 'chat.markdownEditor.actions.taskList':
        return '任务列表';
      case 'chat.markdownEditor.actions.codeBlock':
        return '代码块';
      case 'chat.focus.tooltip':
        return '聚焦';
      case 'chat.focus.allMemories':
        return '聚焦：所有记忆';
      case 'chat.focus.thisThread':
        return '聚焦：当前对话';
      case 'chat.askAiSetup.title':
        return 'AI 对话需要先配置';
      case 'chat.askAiSetup.body':
        return '要使用「AI 对话」，请先添加你自己的 API Key（AI 配置），或订阅 SecondLoop Cloud。';
      case 'chat.askAiSetup.actions.subscribe':
        return '订阅';
      case 'chat.askAiSetup.actions.configureByok':
        return '添加 API Key';
      case 'chat.cloudGateway.emailNotVerified':
        return '邮箱未验证。验证邮箱后才能使用 SecondLoop Cloud 的 AI 对话。';
      case 'chat.cloudGateway.fallback.auth':
        return 'Cloud 登录已失效。本次将使用你的 API Key。';
      case 'chat.cloudGateway.fallback.entitlement':
        return '需要订阅 SecondLoop Cloud。本次将使用你的 API Key。';
      case 'chat.cloudGateway.fallback.rateLimited':
        return 'Cloud 正忙。本次将使用你的 API Key。';
      case 'chat.cloudGateway.fallback.generic':
        return 'Cloud 请求失败。本次将使用你的 API Key。';
      case 'chat.cloudGateway.errors.auth':
        return 'Cloud 登录已失效，请在 Cloud 账号页重新登录。';
      case 'chat.cloudGateway.errors.entitlement':
        return '需要订阅 SecondLoop Cloud。请添加 API Key 或稍后再试。';
      case 'chat.cloudGateway.errors.rateLimited':
        return 'Cloud 触发限速，请稍后再试。';
      case 'chat.cloudGateway.errors.generic':
        return 'Cloud 请求失败。';
      case 'chat.askAiFailedTemporary':
        return 'AI 对话失败了，请重试。';
      case 'chat.askAiConsent.title':
        return '使用 AI 前确认';
      case 'chat.askAiConsent.body':
        return 'SecondLoop 可能会将你输入的文本及少量相关片段发送到你选择的 AI 服务商，以提供 AI 功能。\n\n不会上传你的主密码或完整历史。';
      case 'chat.askAiConsent.dontShowAgain':
        return '不再提示';
      case 'chat.embeddingsConsent.title':
        return '是否使用云端向量进行语义检索？';
      case 'chat.embeddingsConsent.body':
        return '好处：\n- 跨语言/同义改写召回更好\n- 待办关联建议更准确\n\n隐私：\n- 仅上传生成向量所需的最小文本片段\n- 文本会上传到 SecondLoop Cloud，并会被保密处理（不写入日志/存储）\n- 不会上传你的 vault key 或 sync key\n\n用量：\n- 云端向量会消耗 Cloud 使用额度';
      case 'chat.embeddingsConsent.dontShowAgain':
        return '记住我的选择';
      case 'chat.embeddingsConsent.actions.useLocal':
        return '使用本地';
      case 'chat.embeddingsConsent.actions.enableCloud':
        return '开启云端向量';
      case 'chat.semanticParseStatusRunning':
        return 'AI 分析中…';
      case 'chat.semanticParseStatusSlow':
        return 'AI 分析较慢，后台继续…';
      case 'chat.attachmentAnnotationNeedsSetup':
        return '图片注释需要先配置';
      case 'chat.semanticParseStatusFailed':
        return 'AI 分析失败';
      case 'chat.semanticParseStatusCanceled':
        return '已取消 AI 分析';
      case 'chat.semanticParseStatusCreated':
        return ({required Object title}) => '已创建待办：${title}';
      case 'chat.semanticParseStatusUpdated':
        return ({required Object title}) => '已更新待办：${title}';
      case 'chat.semanticParseStatusUpdatedGeneric':
        return '已更新待办';
      case 'chat.semanticParseStatusUndone':
        return '已撤销自动动作';
      case 'chat.askAiRecoveredDetached':
        return '已恢复已完成的云端回答。';
      case 'chat.topicThread.filterTooltip':
        return '主题线程筛选';
      case 'chat.topicThread.actionLabel':
        return '主题线程';
      case 'chat.topicThread.create':
        return '新建主题线程';
      case 'chat.topicThread.clearFilter':
        return '清除线程筛选';
      case 'chat.topicThread.clear':
        return '清除线程';
      case 'chat.topicThread.manage':
        return '管理线程';
      case 'chat.topicThread.rename':
        return '重命名线程';
      case 'chat.topicThread.delete':
        return '删除线程';
      case 'chat.topicThread.deleteDialog.title':
        return '删除主题线程？';
      case 'chat.topicThread.deleteDialog.message':
        return '删除后将移除该线程及其消息归属，且无法撤销。';
      case 'chat.topicThread.deleteDialog.confirm':
        return '删除';
      case 'chat.topicThread.addMessage':
        return '加入此消息';
      case 'chat.topicThread.removeMessage':
        return '移除此消息';
      case 'chat.topicThread.createDialogTitle':
        return '新建主题线程';
      case 'chat.topicThread.renameDialogTitle':
        return '重命名主题线程';
      case 'chat.topicThread.titleFieldLabel':
        return '线程标题（可选）';
      case 'chat.topicThread.untitled':
        return '未命名主题线程';
      case 'chat.tagFilter.tooltip':
        return '标签筛选';
      case 'chat.tagFilter.clearFilter':
        return '清空标签筛选';
      case 'chat.tagFilter.sheet.title':
        return '按标签筛选';
      case 'chat.tagFilter.sheet.apply':
        return '应用';
      case 'chat.tagFilter.sheet.clear':
        return '清空';
      case 'chat.tagFilter.sheet.includeHint':
        return '点击：包含';
      case 'chat.tagFilter.sheet.excludeHint':
        return '再次点击：排除';
      case 'chat.tagFilter.sheet.empty':
        return '暂无标签';
      case 'chat.tagPicker.title':
        return '管理标签';
      case 'chat.tagPicker.suggested':
        return '建议标签';
      case 'chat.tagPicker.mergeSuggestions':
        return '合并建议';
      case 'chat.tagPicker.mergeAction':
        return '合并';
      case 'chat.tagPicker.mergeDismissAction':
        return '忽略';
      case 'chat.tagPicker.mergeLaterAction':
        return '稍后';
      case 'chat.tagPicker.mergeSuggestionMessages':
        return ({required Object count}) => '将影响 ${count} 条已打标签消息';
      case 'chat.tagPicker.mergeReasonSystemDomain':
        return '匹配系统领域标签';
      case 'chat.tagPicker.mergeReasonNameCompact':
        return '可能是重复标签';
      case 'chat.tagPicker.mergeReasonNameContains':
        return '名称高度相似';
      case 'chat.tagPicker.mergeDialog.title':
        return '确认合并标签？';
      case 'chat.tagPicker.mergeDialog.message':
        return ({required Object source, required Object target}) =>
            '将“${source}”合并到“${target}”？这会更新已有消息上的标签。';
      case 'chat.tagPicker.mergeDialog.confirm':
        return '合并';
      case 'chat.tagPicker.mergeApplied':
        return ({required Object count}) => '已合并 ${count} 条消息';
      case 'chat.tagPicker.mergeDismissed':
        return '已忽略该合并建议';
      case 'chat.tagPicker.mergeSavedForLater':
        return '已暂存该合并建议';
      case 'chat.tagPicker.all':
        return '全部标签';
      case 'chat.tagPicker.inputHint':
        return '输入标签名称';
      case 'chat.tagPicker.add':
        return '添加';
      case 'chat.tagPicker.save':
        return '保存';
      case 'chat.tagPicker.tagActionLabel':
        return '标签';
      case 'chat.askScopeEmpty.title':
        return '当前范围未找到结果';
      case 'chat.askScopeEmpty.actions.expandTimeWindow':
        return '扩大时间窗口';
      case 'chat.askScopeEmpty.actions.removeIncludeTags':
        return '移除包含标签';
      case 'chat.askScopeEmpty.actions.switchScopeToAll':
        return '切换范围到全部';
      case 'attachments.metadata.format':
        return '格式';
      case 'attachments.metadata.size':
        return '大小';
      case 'attachments.metadata.capturedAt':
        return '拍摄时间';
      case 'attachments.metadata.location':
        return '地点';
      case 'attachments.url.originalUrl':
        return '原始链接';
      case 'attachments.url.canonicalUrl':
        return '规范链接';
      case 'attachments.content.summary':
        return '摘要';
      case 'attachments.content.excerpt':
        return '摘要';
      case 'attachments.content.fullText':
        return '全文';
      case 'attachments.content.ocrTitle':
        return 'OCR';
      case 'attachments.content.needsOcrTitle':
        return '需要 OCR';
      case 'attachments.content.needsOcrSubtitle':
        return '此 PDF 可能不包含可复制文本。';
      case 'attachments.content.runOcr':
        return '运行 OCR';
      case 'attachments.content.rerunOcr':
        return '重新识别';
      case 'attachments.content.ocrRunning':
        return 'OCR 处理中…';
      case 'attachments.content.ocrReadySubtitle':
        return '已可用文本，如有需要可重新识别。';
      case 'attachments.content.keepForegroundHint':
        return 'OCR 进行中，请尽量保持应用在前台。';
      case 'attachments.content.openWithSystem':
        return '用系统应用打开';
      case 'attachments.content.previewUnavailable':
        return '预览不可用';
      case 'attachments.content.ocrFinished':
        return 'OCR 已完成，正在刷新预览…';
      case 'attachments.content.ocrFailed':
        return '此设备上 OCR 执行失败。';
      case 'attachments.content.speechTranscribeIssue.title':
        return '语音转录暂不可用';
      case 'attachments.content.speechTranscribeIssue.openSettings':
        return '打开系统设置';
      case 'attachments.content.speechTranscribeIssue.openSettingsFailed':
        return '无法自动打开系统设置，请手动检查系统的语音识别权限与听写开关。';
      case 'attachments.content.speechTranscribeIssue.permissionDenied':
        return '语音识别权限被拒绝。请先点击“重试”再次触发系统授权弹窗；若仍被拦截，请前往系统设置开启权限。';
      case 'attachments.content.speechTranscribeIssue.permissionRestricted':
        return '语音识别被系统策略限制。请检查屏幕使用时间或设备管理策略。';
      case 'attachments.content.speechTranscribeIssue.serviceDisabled':
        return '系统“听写与 Siri”已关闭。请先启用后再重试。';
      case 'attachments.content.speechTranscribeIssue.runtimeUnavailable':
        return '当前设备暂时无法使用语音识别运行时。请稍后重试。';
      case 'attachments.content.speechTranscribeIssue.permissionRequest':
        return '本地语音转录需要语音识别权限。请点击“重试”，并在系统弹窗中允许授权。';
      case 'attachments.content.speechTranscribeIssue.offlineUnavailable':
        return '当前设备或语言暂不支持离线语音识别。请先安装系统语音包，或切换到云端转录。';
      case 'attachments.content.videoInsights.contentKind.knowledge':
        return '知识类视频';
      case 'attachments.content.videoInsights.contentKind.nonKnowledge':
        return '非知识类视频';
      case 'attachments.content.videoInsights.contentKind.unknown':
        return '未知';
      case 'attachments.content.videoInsights.detail.knowledgeMarkdown':
        return '知识文稿';
      case 'attachments.content.videoInsights.detail.videoDescription':
        return '视频描述';
      case 'attachments.content.videoInsights.detail.extractedContent':
        return '提取内容';
      case 'attachments.content.videoInsights.fields.contentType':
        return '内容类型';
      case 'attachments.content.videoInsights.fields.segments':
        return '分段处理';
      case 'attachments.content.videoInsights.fields.summary':
        return '视频概要';
      case 'semanticSearch.preparing':
        return '正在准备语义检索…';
      case 'semanticSearch.indexingMessages':
        return ({required Object count}) => '正在索引消息…（已索引 ${count} 条）';
      case 'semanticSearchDebug.title':
        return '语义检索（调试）';
      case 'semanticSearchDebug.embeddingModelLoading':
        return '向量模型：（加载中…）';
      case 'semanticSearchDebug.embeddingModel':
        return ({required Object model}) => '向量模型：${model}';
      case 'semanticSearchDebug.switchedModelReindex':
        return '已切换向量模型；待重新索引';
      case 'semanticSearchDebug.modelAlreadyActive':
        return '向量模型已处于激活状态';
      case 'semanticSearchDebug.processedPending':
        return ({required Object count}) => '已处理 ${count} 条待处理向量';
      case 'semanticSearchDebug.rebuilt':
        return ({required Object count}) => '已为 ${count} 条消息重建向量';
      case 'semanticSearchDebug.runSearchToSeeResults':
        return '运行一次搜索以查看结果';
      case 'semanticSearchDebug.noResults':
        return '没有结果';
      case 'semanticSearchDebug.resultSubtitle':
        return (
                {required Object distance,
                required Object role,
                required Object conversationId}) =>
            'distance=${distance} • role=${role} • convo=${conversationId}';
      case 'sync.title':
        return '同步设置';
      case 'sync.progressDialog.title':
        return '正在同步…';
      case 'sync.progressDialog.preparing':
        return '正在准备…';
      case 'sync.progressDialog.pulling':
        return '正在下载更改…';
      case 'sync.progressDialog.pushing':
        return '正在上传更改…';
      case 'sync.progressDialog.uploadingMedia':
        return '正在上传媒体…';
      case 'sync.progressDialog.finalizing':
        return '正在收尾…';
      case 'sync.sections.automation':
        return '自动同步';
      case 'sync.sections.backend':
        return '同步方式';
      case 'sync.sections.mediaPreview':
        return '媒体下载';
      case 'sync.sections.mediaBackup':
        return '媒体上传';
      case 'sync.sections.securityActions':
        return '安全与手动同步';
      case 'sync.autoSync.title':
        return '自动同步';
      case 'sync.autoSync.subtitle':
        return '自动保持你的设备间数据同步。';
      case 'sync.autoSync.wifiOnlyTitle':
        return '仅在 Wi‑Fi 下自动同步';
      case 'sync.autoSync.wifiOnlySubtitle':
        return '节省流量：自动同步只在 Wi‑Fi 下进行';
      case 'sync.mediaPreview.chatThumbnailsWifiOnlyTitle':
        return '仅在 Wi‑Fi 下下载媒体文件';
      case 'sync.mediaPreview.chatThumbnailsWifiOnlySubtitle':
        return '当附件在本机缺失时，仅在 Wi‑Fi 下自动下载';
      case 'sync.mediaBackup.title':
        return '媒体上传';
      case 'sync.mediaBackup.subtitle':
        return '后台上传加密图片，用于跨设备回看与回溯记忆';
      case 'sync.mediaBackup.wifiOnlyTitle':
        return '仅在 Wi‑Fi 下上传';
      case 'sync.mediaBackup.wifiOnlySubtitle':
        return '节省流量：只在 Wi‑Fi 下上传';
      case 'sync.mediaBackup.description':
        return '将加密的图片附件上传到同步存储，用于跨设备回看，并支持后续的回溯记忆功能。附件在本机缺失时可按需下载。';
      case 'sync.mediaBackup.stats':
        return (
                {required Object pending,
                required Object failed,
                required Object uploaded}) =>
            '待上传 ${pending} · 失败 ${failed} · 已上传 ${uploaded}';
      case 'sync.mediaBackup.lastUploaded':
        return ({required Object at}) => '最近一次上传：${at}';
      case 'sync.mediaBackup.lastError':
        return ({required Object error}) => '最近一次错误：${error}';
      case 'sync.mediaBackup.lastErrorWithTime':
        return ({required Object at, required Object error}) =>
            '最近一次错误（${at}）：${error}';
      case 'sync.mediaBackup.backfillButton':
        return '加入历史图片';
      case 'sync.mediaBackup.uploadNowButton':
        return '立即上传';
      case 'sync.mediaBackup.backfillEnqueued':
        return ({required Object count}) => '已将 ${count} 张图片加入上传队列';
      case 'sync.mediaBackup.backfillFailed':
        return ({required Object error}) => '加入失败：${error}';
      case 'sync.mediaBackup.notEnabled':
        return '请先开启媒体上传。';
      case 'sync.mediaBackup.managedVaultOnly':
        return '媒体上传仅适用于 WebDAV 或 SecondLoop 云同步。';
      case 'sync.mediaBackup.wifiOnlyBlocked':
        return '已开启仅 Wi‑Fi。请连接 Wi‑Fi，或仅本次允许使用蜂窝数据。';
      case 'sync.mediaBackup.uploaded':
        return '上传完成';
      case 'sync.mediaBackup.nothingToUpload':
        return '暂无可上传内容';
      case 'sync.mediaBackup.uploadFailed':
        return ({required Object error}) => '上传失败：${error}';
      case 'sync.mediaBackup.cellularDialog.title':
        return '使用蜂窝数据？';
      case 'sync.mediaBackup.cellularDialog.message':
        return '已开启仅 Wi‑Fi。使用蜂窝数据上传可能消耗较多流量。';
      case 'sync.mediaBackup.cellularDialog.confirm':
        return '仍然使用';
      case 'sync.localCache.button':
        return '清理本地存储';
      case 'sync.localCache.subtitle':
        return '删除本机缓存的附件文件（远端保留，需要时可重新下载）。请确保已完成同步/上传。';
      case 'sync.localCache.cleared':
        return '已清理本地缓存';
      case 'sync.localCache.failed':
        return ({required Object error}) => '清理失败：${error}';
      case 'sync.localCache.dialog.title':
        return '清理本地存储？';
      case 'sync.localCache.dialog.message':
        return '这将删除本机缓存的照片与文件，以节省本地空间。远端同步存储会保留副本；之后查看时会按需重新下载。';
      case 'sync.localCache.dialog.confirm':
        return '清理';
      case 'sync.backendLabel':
        return '同步方式';
      case 'sync.backendWebdav':
        return 'WebDAV（你自己的服务器）';
      case 'sync.backendLocalDir':
        return '本机文件夹（桌面端）';
      case 'sync.backendManagedVault':
        return 'SecondLoop Cloud';
      case 'sync.cloudManagedVault.signInRequired':
        return '请先登录 SecondLoop Cloud 才能使用云同步。';
      case 'sync.cloudManagedVault.paymentRequired':
        return '云同步已暂停。请续费订阅以继续同步。';
      case 'sync.cloudManagedVault.graceReadonlyUntil':
        return ({required Object until}) => '云同步处于只读状态（宽限期至 ${until}）。';
      case 'sync.cloudManagedVault.storageQuotaExceeded':
        return '云端存储已满，已暂停上传。';
      case 'sync.cloudManagedVault.storageQuotaExceededWithUsage':
        return ({required Object used, required Object limit}) =>
            '云端存储已满（${used} / ${limit}），已暂停上传。';
      case 'sync.cloudManagedVault.switchDialog.title':
        return '切换到 SecondLoop Cloud 同步？';
      case 'sync.cloudManagedVault.switchDialog.message':
        return '你的订阅已生效。是否将同步方式切换到 SecondLoop Cloud？你可以随时切换回来。';
      case 'sync.cloudManagedVault.switchDialog.cancel':
        return '暂不';
      case 'sync.cloudManagedVault.switchDialog.confirm':
        return '切换';
      case 'sync.cloudManagedVault.setPassphraseDialog.title':
        return '设置同步口令';
      case 'sync.cloudManagedVault.setPassphraseDialog.confirm':
        return '保存口令';
      case 'sync.remoteRootRequired':
        return '必须填写文件夹名称';
      case 'sync.baseUrlRequired':
        return '必须填写服务器地址';
      case 'sync.localDirRequired':
        return '必须填写文件夹路径';
      case 'sync.connectionOk':
        return '连接成功';
      case 'sync.connectionFailed':
        return ({required Object error}) => '连接失败：${error}';
      case 'sync.saveFailed':
        return ({required Object error}) => '保存失败：${error}';
      case 'sync.missingSyncKey':
        return '缺少同步口令。请先输入口令并点击保存。';
      case 'sync.pushedOps':
        return ({required Object count}) => '已上传 ${count} 个更改';
      case 'sync.pulledOps':
        return ({required Object count}) => '已下载 ${count} 个更改';
      case 'sync.noNewChanges':
        return '已是最新';
      case 'sync.pushFailed':
        return ({required Object error}) => '上传失败：${error}';
      case 'sync.pullFailed':
        return ({required Object error}) => '下载失败：${error}';
      case 'sync.fields.baseUrl.label':
        return '服务器地址';
      case 'sync.fields.baseUrl.hint':
        return 'https://example.com/dav';
      case 'sync.fields.username.label':
        return '用户名（可选）';
      case 'sync.fields.password.label':
        return '密码（可选）';
      case 'sync.fields.localDir.label':
        return '文件夹路径';
      case 'sync.fields.localDir.hint':
        return '/Users/me/SecondLoopVault';
      case 'sync.fields.localDir.helper':
        return '更适合桌面端；移动端可能不支持该路径。';
      case 'sync.fields.managedVaultBaseUrl.label':
        return 'Cloud 服务器地址（高级）';
      case 'sync.fields.managedVaultBaseUrl.hint':
        return 'https://vault.example.com';
      case 'sync.fields.vaultId.label':
        return 'Cloud 账号 ID';
      case 'sync.fields.vaultId.hint':
        return '自动填写';
      case 'sync.fields.remoteRoot.label':
        return '文件夹名称';
      case 'sync.fields.remoteRoot.hint':
        return 'SecondLoop';
      case 'sync.fields.passphrase.label':
        return '同步口令';
      case 'sync.fields.passphrase.helper':
        return '所有设备请使用同一口令。口令不会被上传。';
      case 'llmProfiles.title':
        return 'AI 配置';
      case 'llmProfiles.refreshTooltip':
        return '刷新';
      case 'llmProfiles.activeProfileHelp':
        return '当前选择的配置会作为通用 LLM API 配置，被多项智能能力复用。';
      case 'llmProfiles.noProfilesYet':
        return '暂无配置。';
      case 'llmProfiles.addProfile':
        return '添加配置';
      case 'llmProfiles.deleted':
        return '配置已删除';
      case 'llmProfiles.validationError':
        return '名称、API Key 和模型名称为必填项。';
      case 'llmProfiles.deleteDialog.title':
        return '删除配置？';
      case 'llmProfiles.deleteDialog.message':
        return ({required Object name}) => '确定删除「${name}」？该操作会从本设备移除。';
      case 'llmProfiles.fields.name':
        return '名称';
      case 'llmProfiles.fields.provider':
        return '提供商';
      case 'llmProfiles.fields.baseUrlOptional':
        return '接口地址（可选）';
      case 'llmProfiles.fields.modelName':
        return '模型名称';
      case 'llmProfiles.fields.apiKey':
        return 'API Key';
      case 'llmProfiles.providers.openaiCompatible':
        return 'OpenAI 兼容';
      case 'llmProfiles.providers.geminiCompatible':
        return 'Gemini';
      case 'llmProfiles.providers.anthropicCompatible':
        return 'Anthropic';
      case 'llmProfiles.savedActivated':
        return '已保存并设为当前配置';
      case 'llmProfiles.actions.saveActivate':
        return '保存并启用';
      case 'llmProfiles.actions.cancel':
        return '取消';
      case 'llmProfiles.actions.delete':
        return '删除';
      case 'embeddingProfiles.title':
        return '向量配置';
      case 'embeddingProfiles.refreshTooltip':
        return '刷新';
      case 'embeddingProfiles.activeProfileHelp':
        return '当前选择的配置将用于 embeddings（语义检索 / RAG）。';
      case 'embeddingProfiles.noProfilesYet':
        return '暂无配置。';
      case 'embeddingProfiles.addProfile':
        return '添加配置';
      case 'embeddingProfiles.deleted':
        return '向量配置已删除';
      case 'embeddingProfiles.validationError':
        return '名称、API Key 和模型名称为必填项。';
      case 'embeddingProfiles.reindexDialog.title':
        return '重新索引向量？';
      case 'embeddingProfiles.reindexDialog.message':
        return '启用该配置可能会使用你的 API key/额度重新向量化本地内容（可能耗时并产生费用）。';
      case 'embeddingProfiles.reindexDialog.actions.continueLabel':
        return '继续';
      case 'embeddingProfiles.deleteDialog.title':
        return '删除配置？';
      case 'embeddingProfiles.deleteDialog.message':
        return ({required Object name}) => '确定删除「${name}」？该操作会从本设备移除。';
      case 'embeddingProfiles.fields.name':
        return '名称';
      case 'embeddingProfiles.fields.provider':
        return '提供商';
      case 'embeddingProfiles.fields.baseUrlOptional':
        return '接口地址（可选）';
      case 'embeddingProfiles.fields.modelName':
        return '模型名称';
      case 'embeddingProfiles.fields.apiKey':
        return 'API Key';
      case 'embeddingProfiles.providers.openaiCompatible':
        return 'OpenAI 兼容';
      case 'embeddingProfiles.savedActivated':
        return '已保存并设为当前配置';
      case 'embeddingProfiles.actions.saveActivate':
        return '保存并启用';
      case 'embeddingProfiles.actions.cancel':
        return '取消';
      case 'embeddingProfiles.actions.delete':
        return '删除';
      case 'inbox.defaultTitle':
        return '收件箱';
      case 'inbox.noConversationsYet':
        return '暂无会话';
      default:
        return null;
    }
  }
}
