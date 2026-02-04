/// Generated file. Do not edit.
///
/// Original: lib/i18n
/// To regenerate, run: `dart run slang`
///
/// Locales: 2
/// Strings: 970 (485 per locale)
///
/// Built on 2026-02-04 at 10:20 UTC

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
  late final _StringsSettingsSemanticParseAutoActionsEn
      semanticParseAutoActions =
      _StringsSettingsSemanticParseAutoActionsEn._(_root);
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
  String get cameraTooltip => 'Take photo';
  String get photoMessage => 'Photo';
  String get editMessageTitle => 'Edit message';
  String get messageUpdated => 'Message updated';
  String get messageDeleted => 'Message deleted';
  String photoFailed({required Object error}) => 'Photo failed: ${error}';
  String editFailed({required Object error}) => 'Edit failed: ${error}';
  String deleteFailed({required Object error}) => 'Delete failed: ${error}';
  String get noMessagesYet => 'No messages yet';
  String get viewFull => 'View full';
  late final _StringsChatMessageActionsEn messageActions =
      _StringsChatMessageActionsEn._(_root);
  late final _StringsChatMessageViewerEn messageViewer =
      _StringsChatMessageViewerEn._(_root);
  late final _StringsChatFocusEn focus = _StringsChatFocusEn._(_root);
  late final _StringsChatAskAiSetupEn askAiSetup =
      _StringsChatAskAiSetupEn._(_root);
  late final _StringsChatCloudGatewayEn cloudGateway =
      _StringsChatCloudGatewayEn._(_root);
  String get askAiFailedTemporary =>
      'Ask AI failed. Please try again. This message will be removed in 3 seconds.';
  late final _StringsChatAskAiConsentEn askAiConsent =
      _StringsChatAskAiConsentEn._(_root);
  late final _StringsChatEmbeddingsConsentEn embeddingsConsent =
      _StringsChatEmbeddingsConsentEn._(_root);
  String get semanticParseStatusRunning => 'AI analyzing…';
  String get semanticParseStatusSlow =>
      'AI is taking longer. Continuing in background…';
  String get semanticParseStatusFailed => 'AI analysis failed';
  String get semanticParseStatusCanceled => 'AI analysis canceled';
  String semanticParseStatusCreated({required Object title}) =>
      'Created task: ${title}';
  String semanticParseStatusUpdated({required Object title}) =>
      'Updated task: ${title}';
  String get semanticParseStatusUpdatedGeneric => 'Updated task';
  String get semanticParseStatusUndone => 'Undid auto action';
}

// Path: attachments
class _StringsAttachmentsEn {
  _StringsAttachmentsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final _StringsAttachmentsMetadataEn metadata =
      _StringsAttachmentsMetadataEn._(_root);
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
  String get activeProfileHelp => 'Active profile is used for Ask AI.';
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
  String get save => 'Save';
  String get copy => 'Copy';
  String get reset => 'Reset';
  String get continueLabel => 'Continue';
  String get send => 'Send';
  String get askAi => 'Ask AI';
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

// Path: settings.semanticParseAutoActions
class _StringsSettingsSemanticParseAutoActionsEn {
  _StringsSettingsSemanticParseAutoActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'AI semantic actions';
  String get subtitleEnabled =>
      'On. Messages may be sent to AI to create or update todos automatically.';
  String get subtitleDisabled =>
      'Off. Messages won\'t be sent for automatic actions.';
  String get subtitleUnset => 'Not set. Default is off.';
  String get subtitleRequiresSetup =>
      'Requires SecondLoop Pro or an API key (BYOK).';
  String get dialogTitle => 'Turn on AI semantic actions?';
  String get dialogBody =>
      'To automatically create or update todos, SecondLoop can send message text to an AI model.\n\nThe text is processed confidentially (not logged or stored). Your vault key and sync key are never uploaded.\n\nThis may use Cloud quota or your own provider quota.';
  late final _StringsSettingsSemanticParseAutoActionsDialogActionsEn
      dialogActions =
      _StringsSettingsSemanticParseAutoActionsDialogActionsEn._(_root);
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
  String get mediaPreview => 'Media previews';
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
  String get chatThumbnailsWifiOnlyTitle => 'Image previews on Wi‑Fi only';
  String get chatThumbnailsWifiOnlySubtitle =>
      'If a photo isn\'t on this device yet, download its preview only on Wi‑Fi';
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

// Path: actions.reviewQueue.actions
class _StringsActionsReviewQueueActionsEn {
  _StringsActionsReviewQueueActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get schedule => 'Schedule';
  String get snooze => 'Snooze';
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

// Path: settings.semanticParseAutoActions.dialogActions
class _StringsSettingsSemanticParseAutoActionsDialogActionsEn {
  _StringsSettingsSemanticParseAutoActionsDialogActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get enable => 'Enable';
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
  String loadFailed({required Object error}) => 'Failed to load: ${error}';
}

// Path: settings.cloudAccount.emailVerification.actions
class _StringsSettingsCloudAccountEmailVerificationActionsEn {
  _StringsSettingsCloudAccountEmailVerificationActionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get resend => 'Resend verification email';
}

// Path: settings.cloudAccount.emailVerification.messages
class _StringsSettingsCloudAccountEmailVerificationMessagesEn {
  _StringsSettingsCloudAccountEmailVerificationMessagesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get verificationEmailSent => 'Verification email sent';
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
  late final _StringsSettingsSemanticParseAutoActionsZhCn
      semanticParseAutoActions =
      _StringsSettingsSemanticParseAutoActionsZhCn._(_root);
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
  String photoFailed({required Object error}) => '拍照失败：${error}';
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
  late final _StringsChatFocusZhCn focus = _StringsChatFocusZhCn._(_root);
  @override
  late final _StringsChatAskAiSetupZhCn askAiSetup =
      _StringsChatAskAiSetupZhCn._(_root);
  @override
  late final _StringsChatCloudGatewayZhCn cloudGateway =
      _StringsChatCloudGatewayZhCn._(_root);
  @override
  String get askAiFailedTemporary => '问 AI 失败了，请重试。本提醒将在 3 秒后自动删除。';
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
  String get activeProfileHelp => '当前选择的配置将用于「问 AI」。';
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
  String get askAi => '问 AI';
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
  String get title => 'API Key（问 AI）';
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
  String get title => 'AI 语义动作';
  @override
  String get subtitleEnabled => '已开启。消息可能会发送给 AI 来自动创建或更新待办。';
  @override
  String get subtitleDisabled => '已关闭。消息不会用于自动动作。';
  @override
  String get subtitleUnset => '尚未设置，默认关闭。';
  @override
  String get subtitleRequiresSetup => '需要 SecondLoop Pro 或 API Key（BYOK）。';
  @override
  String get dialogTitle => '开启 AI 语义动作？';
  @override
  String get dialogBody =>
      '为了自动创建或更新待办，SecondLoop 可以将消息文本发送给 AI 模型。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这可能会消耗 Cloud 额度或你自己的服务商额度。';
  @override
  late final _StringsSettingsSemanticParseAutoActionsDialogActionsZhCn
      dialogActions =
      _StringsSettingsSemanticParseAutoActionsDialogActionsZhCn._(_root);
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
  String get title => '更智能的搜索';
  @override
  String get subtitleEnabled => '已开启。搜索更准，会消耗 Cloud 额度。';
  @override
  String get subtitleDisabled => '已关闭。搜索只使用本地数据。';
  @override
  String get subtitleUnset => '尚未设置，首次需要时会询问。';
  @override
  String get subtitleRequiresPro => '需要 SecondLoop Pro。';
  @override
  String get dialogTitle => '开启更智能的搜索？';
  @override
  String get dialogBody =>
      '为了让搜索和回忆更准确，SecondLoop 可以将少量文本（消息预览、待办标题、跟进）发送到 SecondLoop Cloud 生成搜索数据。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这会消耗 Cloud 额度。';
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
  String get title => '问 AI 需要先配置';
  @override
  String get body => '要使用「问 AI」，请先添加你自己的 API Key（AI 配置），或订阅 SecondLoop Cloud。';
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
  String get emailNotVerified => '邮箱未验证。验证邮箱后才能使用 SecondLoop Cloud Ask AI。';
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
  String get mediaPreview => '媒体预览';
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
  String get chatThumbnailsWifiOnlyTitle => '仅在 Wi‑Fi 下下载图片预览';
  @override
  String get chatThumbnailsWifiOnlySubtitle => '当图片在本机缺失时，仅在 Wi‑Fi 下自动下载预览';
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
  String get snooze => '稍后提醒';
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
  String get askAiUsage => 'Ask AI：';
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
  String get help => '验证邮箱后才能使用 SecondLoop Cloud Ask AI。';
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
  String get body => '不用做任何配置，订阅后就能直接问 AI。';
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
      case 'actions.reviewQueue.actions.schedule':
        return 'Schedule';
      case 'actions.reviewQueue.actions.snooze':
        return 'Snooze';
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
      case 'settings.semanticParseAutoActions.title':
        return 'AI semantic actions';
      case 'settings.semanticParseAutoActions.subtitleEnabled':
        return 'On. Messages may be sent to AI to create or update todos automatically.';
      case 'settings.semanticParseAutoActions.subtitleDisabled':
        return 'Off. Messages won\'t be sent for automatic actions.';
      case 'settings.semanticParseAutoActions.subtitleUnset':
        return 'Not set. Default is off.';
      case 'settings.semanticParseAutoActions.subtitleRequiresSetup':
        return 'Requires SecondLoop Pro or an API key (BYOK).';
      case 'settings.semanticParseAutoActions.dialogTitle':
        return 'Turn on AI semantic actions?';
      case 'settings.semanticParseAutoActions.dialogBody':
        return 'To automatically create or update todos, SecondLoop can send message text to an AI model.\n\nThe text is processed confidentially (not logged or stored). Your vault key and sync key are never uploaded.\n\nThis may use Cloud quota or your own provider quota.';
      case 'settings.semanticParseAutoActions.dialogActions.enable':
        return 'Enable';
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
      case 'settings.cloudAccount.emailVerification.labels.loadFailed':
        return ({required Object error}) => 'Failed to load: ${error}';
      case 'settings.cloudAccount.emailVerification.actions.resend':
        return 'Resend verification email';
      case 'settings.cloudAccount.emailVerification.messages.verificationEmailSent':
        return 'Verification email sent';
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
      case 'chat.photoFailed':
        return ({required Object error}) => 'Photo failed: ${error}';
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
        return 'Ask AI failed. Please try again. This message will be removed in 3 seconds.';
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
      case 'attachments.metadata.format':
        return 'Format';
      case 'attachments.metadata.size':
        return 'Size';
      case 'attachments.metadata.capturedAt':
        return 'Captured';
      case 'attachments.metadata.location':
        return 'Location';
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
        return 'Media previews';
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
        return 'Image previews on Wi‑Fi only';
      case 'sync.mediaPreview.chatThumbnailsWifiOnlySubtitle':
        return 'If a photo isn\'t on this device yet, download its preview only on Wi‑Fi';
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
        return 'Active profile is used for Ask AI.';
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
        return '问 AI';
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
      case 'actions.reviewQueue.actions.schedule':
        return '安排时间';
      case 'actions.reviewQueue.actions.snooze':
        return '稍后提醒';
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
        return 'API Key（问 AI）';
      case 'settings.llmProfiles.subtitle':
        return '高级：使用你自己的服务商与 Key';
      case 'settings.embeddingProfiles.title':
        return 'API Key（语义搜索）';
      case 'settings.embeddingProfiles.subtitle':
        return '高级：使用你自己的服务商与 Key';
      case 'settings.semanticParseAutoActions.title':
        return 'AI 语义动作';
      case 'settings.semanticParseAutoActions.subtitleEnabled':
        return '已开启。消息可能会发送给 AI 来自动创建或更新待办。';
      case 'settings.semanticParseAutoActions.subtitleDisabled':
        return '已关闭。消息不会用于自动动作。';
      case 'settings.semanticParseAutoActions.subtitleUnset':
        return '尚未设置，默认关闭。';
      case 'settings.semanticParseAutoActions.subtitleRequiresSetup':
        return '需要 SecondLoop Pro 或 API Key（BYOK）。';
      case 'settings.semanticParseAutoActions.dialogTitle':
        return '开启 AI 语义动作？';
      case 'settings.semanticParseAutoActions.dialogBody':
        return '为了自动创建或更新待办，SecondLoop 可以将消息文本发送给 AI 模型。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这可能会消耗 Cloud 额度或你自己的服务商额度。';
      case 'settings.semanticParseAutoActions.dialogActions.enable':
        return '开启';
      case 'settings.cloudEmbeddings.title':
        return '更智能的搜索';
      case 'settings.cloudEmbeddings.subtitleEnabled':
        return '已开启。搜索更准，会消耗 Cloud 额度。';
      case 'settings.cloudEmbeddings.subtitleDisabled':
        return '已关闭。搜索只使用本地数据。';
      case 'settings.cloudEmbeddings.subtitleUnset':
        return '尚未设置，首次需要时会询问。';
      case 'settings.cloudEmbeddings.subtitleRequiresPro':
        return '需要 SecondLoop Pro。';
      case 'settings.cloudEmbeddings.dialogTitle':
        return '开启更智能的搜索？';
      case 'settings.cloudEmbeddings.dialogBody':
        return '为了让搜索和回忆更准确，SecondLoop 可以将少量文本（消息预览、待办标题、跟进）发送到 SecondLoop Cloud 生成搜索数据。\n\n文本会被保密处理（不写入日志/不存储）。你的 vault key 和 sync key 永远不会上传。\n\n这会消耗 Cloud 额度。';
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
        return '验证邮箱后才能使用 SecondLoop Cloud Ask AI。';
      case 'settings.cloudAccount.emailVerification.labels.loadFailed':
        return ({required Object error}) => '加载失败：${error}';
      case 'settings.cloudAccount.emailVerification.actions.resend':
        return '重新发送验证邮件';
      case 'settings.cloudAccount.emailVerification.messages.verificationEmailSent':
        return '验证邮件已发送';
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
        return 'Ask AI：';
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
      case 'settings.subscription.title':
        return '订阅';
      case 'settings.subscription.subtitle':
        return '管理 SecondLoop Pro';
      case 'settings.subscription.benefits.title':
        return 'SecondLoop Pro 可解锁';
      case 'settings.subscription.benefits.items.noSetup.title':
        return '免配置直接用 AI';
      case 'settings.subscription.benefits.items.noSetup.body':
        return '不用做任何配置，订阅后就能直接问 AI。';
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
      case 'chat.photoFailed':
        return ({required Object error}) => '拍照失败：${error}';
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
      case 'chat.focus.tooltip':
        return '聚焦';
      case 'chat.focus.allMemories':
        return '聚焦：所有记忆';
      case 'chat.focus.thisThread':
        return '聚焦：当前对话';
      case 'chat.askAiSetup.title':
        return '问 AI 需要先配置';
      case 'chat.askAiSetup.body':
        return '要使用「问 AI」，请先添加你自己的 API Key（AI 配置），或订阅 SecondLoop Cloud。';
      case 'chat.askAiSetup.actions.subscribe':
        return '订阅';
      case 'chat.askAiSetup.actions.configureByok':
        return '添加 API Key';
      case 'chat.cloudGateway.emailNotVerified':
        return '邮箱未验证。验证邮箱后才能使用 SecondLoop Cloud Ask AI。';
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
        return '问 AI 失败了，请重试。本提醒将在 3 秒后自动删除。';
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
      case 'attachments.metadata.format':
        return '格式';
      case 'attachments.metadata.size':
        return '大小';
      case 'attachments.metadata.capturedAt':
        return '拍摄时间';
      case 'attachments.metadata.location':
        return '地点';
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
        return '媒体预览';
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
        return '仅在 Wi‑Fi 下下载图片预览';
      case 'sync.mediaPreview.chatThumbnailsWifiOnlySubtitle':
        return '当图片在本机缺失时，仅在 Wi‑Fi 下自动下载预览';
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
        return '当前选择的配置将用于「问 AI」。';
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
