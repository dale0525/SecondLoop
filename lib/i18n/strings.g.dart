/// Generated file. Do not edit.
///
/// Original: lib/i18n
/// To regenerate, run: `dart run slang`
///
/// Locales: 2
/// Strings: 502 (251 per locale)
///
/// Built on 2026-01-25 at 05:18 UTC

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
  late final _StringsSemanticSearchEn semanticSearch =
      _StringsSemanticSearchEn._(_root);
  late final _StringsSemanticSearchDebugEn semanticSearchDebug =
      _StringsSemanticSearchDebugEn._(_root);
  late final _StringsSyncEn sync = _StringsSyncEn._(_root);
  late final _StringsLlmProfilesEn llmProfiles = _StringsLlmProfilesEn._(_root);
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
  late final _StringsActionsTodoDetailEn todoDetail =
      _StringsActionsTodoDetailEn._(_root);
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
  late final _StringsSettingsLanguageEn language =
      _StringsSettingsLanguageEn._(_root);
  late final _StringsSettingsAutoLockEn autoLock =
      _StringsSettingsAutoLockEn._(_root);
  late final _StringsSettingsSystemUnlockEn systemUnlock =
      _StringsSettingsSystemUnlockEn._(_root);
  late final _StringsSettingsLockNowEn lockNow =
      _StringsSettingsLockNowEn._(_root);
  late final _StringsSettingsLlmProfilesEn llmProfiles =
      _StringsSettingsLlmProfilesEn._(_root);
  late final _StringsSettingsCloudAccountEn cloudAccount =
      _StringsSettingsCloudAccountEn._(_root);
  late final _StringsSettingsCloudUsageEn cloudUsage =
      _StringsSettingsCloudUsageEn._(_root);
  late final _StringsSettingsSubscriptionEn subscription =
      _StringsSettingsSubscriptionEn._(_root);
  late final _StringsSettingsSyncEn sync = _StringsSettingsSyncEn._(_root);
  late final _StringsSettingsResetLocalDataEn resetLocalData =
      _StringsSettingsResetLocalDataEn._(_root);
  late final _StringsSettingsDebugResetLocalDataEn debugResetLocalData =
      _StringsSettingsDebugResetLocalDataEn._(_root);
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
  String get editMessageTitle => 'Edit message';
  String get messageUpdated => 'Message updated';
  String get messageDeleted => 'Message deleted';
  String editFailed({required Object error}) => 'Edit failed: ${error}';
  String deleteFailed({required Object error}) => 'Delete failed: ${error}';
  String get noMessagesYet => 'No messages yet';
  late final _StringsChatFocusEn focus = _StringsChatFocusEn._(_root);
  late final _StringsChatAskAiSetupEn askAiSetup =
      _StringsChatAskAiSetupEn._(_root);
  late final _StringsChatCloudGatewayEn cloudGateway =
      _StringsChatCloudGatewayEn._(_root);
  late final _StringsChatAskAiConsentEn askAiConsent =
      _StringsChatAskAiConsentEn._(_root);
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
  String get title => 'Vault Sync';
  late final _StringsSyncSectionsEn sections = _StringsSyncSectionsEn._(_root);
  late final _StringsSyncAutoSyncEn autoSync = _StringsSyncAutoSyncEn._(_root);
  String get backendLabel => 'Vault backend';
  String get backendWebdav => 'WebDAV';
  String get backendLocalDir => 'Local directory (desktop)';
  String get backendManagedVault => 'Cloud managed vault';
  late final _StringsSyncCloudManagedVaultEn cloudManagedVault =
      _StringsSyncCloudManagedVaultEn._(_root);
  String get remoteRootRequired => 'Remote root is required';
  String get baseUrlRequired => 'Base URL is required';
  String get localDirRequired => 'Local directory is required';
  String get connectionOk => 'Connection OK';
  String connectionFailed({required Object error}) =>
      'Connection failed: ${error}';
  String saveFailed({required Object error}) => 'Save failed: ${error}';
  String get missingSyncKey =>
      'Missing sync key. Enter a passphrase and Save first.';
  String pushedOps({required Object count}) => 'Pushed ${count} ops';
  String pulledOps({required Object count}) => 'Pulled ${count} ops';
  String pushFailed({required Object error}) => 'Push failed: ${error}';
  String pullFailed({required Object error}) => 'Pull failed: ${error}';
  late final _StringsSyncFieldsEn fields = _StringsSyncFieldsEn._(_root);
}

// Path: llmProfiles
class _StringsLlmProfilesEn {
  _StringsLlmProfilesEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'LLM Profiles';
  String get refreshTooltip => 'Refresh';
  String get activeProfileHelp => 'Active profile is used for Ask AI.';
  String get noProfilesYet => 'No profiles yet.';
  String get addProfile => 'Add profile';
  String get deleted => 'LLM profile deleted';
  String get validationError => 'Name, API key, and model name are required.';
  late final _StringsLlmProfilesDeleteDialogEn deleteDialog =
      _StringsLlmProfilesDeleteDialogEn._(_root);
  late final _StringsLlmProfilesFieldsEn fields =
      _StringsLlmProfilesFieldsEn._(_root);
  late final _StringsLlmProfilesProvidersEn providers =
      _StringsLlmProfilesProvidersEn._(_root);
  String get savedActivated => 'LLM profile saved and activated';
  late final _StringsLlmProfilesActionsEn actions =
      _StringsLlmProfilesActionsEn._(_root);
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
  String get reset => 'Reset';
  String get continueLabel => 'Continue';
  String get send => 'Send';
  String get askAi => 'Ask AI';
  String get stop => 'Stop';
  String get stopping => 'Stopping…';
  String get edit => 'Edit';
  String get delete => 'Delete';
  String get undo => 'Undo';
  String get refresh => 'Refresh';
  String get search => 'Search';
  String get useModel => 'Use model';
  String get processPending => 'Process pending';
  String get rebuildEmbeddings => 'Rebuild embeddings';
  String get push => 'Push';
  String get pull => 'Pull';
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

// Path: actions.todoDetail
class _StringsActionsTodoDetailEn {
  _StringsActionsTodoDetailEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Task';
  String get emptyTimeline => 'No updates yet';
  String get noteHint => 'Add a note…';
  String get addNote => 'Add';
}

// Path: actions.agenda
class _StringsActionsAgendaEn {
  _StringsActionsAgendaEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Tasks';
  String summary({required Object due, required Object overdue}) =>
      'Today ${due} • Overdue ${overdue}';
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
  String get general => 'General';
  String get actions => 'Actions';
  String get security => 'Security';
  String get connections => 'Connections';
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
  String get title => 'LLM profiles';
  String get subtitle => 'Configure BYOK for Ask AI';
}

// Path: settings.cloudAccount
class _StringsSettingsCloudAccountEn {
  _StringsSettingsCloudAccountEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Cloud account';
  String get subtitle => 'Sign in to SecondLoop Cloud';
  String signedInAs({required Object email}) => 'Signed in as ${email}';
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

// Path: settings.subscription
class _StringsSettingsSubscriptionEn {
  _StringsSettingsSubscriptionEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Subscription';
  String get subtitle => 'Manage SecondLoop Pro';
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
  String get subtitle => 'Vault backends + auto sync settings';
}

// Path: settings.resetLocalData
class _StringsSettingsResetLocalDataEn {
  _StringsSettingsResetLocalDataEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get dialogTitle => 'Reset local data?';
  String get dialogBody =>
      'This will delete local messages and clear synced remote data. It will NOT delete your master password or local LLM/sync config. You will need to unlock again.';
  String failed({required Object error}) => 'Reset failed: ${error}';
}

// Path: settings.debugResetLocalData
class _StringsSettingsDebugResetLocalDataEn {
  _StringsSettingsDebugResetLocalDataEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Debug: Reset local data';
  String get subtitle => 'Delete local messages + clear synced remote data';
}

// Path: settings.debugSemanticSearch
class _StringsSettingsDebugSemanticSearchEn {
  _StringsSettingsDebugSemanticSearchEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Debug: Semantic search';
  String get subtitle => 'Search similar messages + rebuild embeddings index';
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
      'Configure BYOK (LLM profiles) or subscribe to SecondLoop Cloud to use Ask AI.';
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
  String get title => 'Before you ask';
  String get body =>
      'SecondLoop will send your question and a few relevant snippets to your configured LLM provider to generate an answer.\n\nIt will NOT upload your vault key, sync key, or full history.';
  String get dontShowAgain => 'Don\'t show again';
}

// Path: sync.sections
class _StringsSyncSectionsEn {
  _StringsSyncSectionsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get automation => 'Automation';
  String get backend => 'Backend';
  String get securityActions => 'Security & Actions';
}

// Path: sync.autoSync
class _StringsSyncAutoSyncEn {
  _StringsSyncAutoSyncEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get title => 'Auto sync';
  String get subtitle =>
      'Foreground debounced push + background periodic sync (mobile)';
}

// Path: sync.cloudManagedVault
class _StringsSyncCloudManagedVaultEn {
  _StringsSyncCloudManagedVaultEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get signInRequired => 'Sign in to use Cloud managed vault.';
  String get paymentRequired =>
      'Cloud sync is unavailable. Renew your subscription to continue syncing.';
  String graceReadonlyUntil({required Object until}) =>
      'Cloud sync is read-only until ${until}.';
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
  String get baseUrlOptional => 'Base URL (optional)';
  String get modelName => 'Model name';
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

// Path: settings.cloudAccount.errors
class _StringsSettingsCloudAccountErrorsEn {
  _StringsSettingsCloudAccountErrorsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get missingWebApiKey =>
      'Cloud sign-in is not configured. Run `pixi run init-env` (or copy `.env.example` → `.env.local`) and set `SECONDLOOP_FIREBASE_WEB_API_KEY`, then restart the app.';
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
  String get gatewayNotConfigured => 'Cloud gateway is not configured.';
  String get signInRequired => 'Sign in to view usage.';
  String get usage => 'Usage:';
  String get inputTokensUsed30d => 'Input tokens (30d):';
  String get outputTokensUsed30d => 'Output tokens (30d):';
  String get tokensUsed30d => 'Tokens (30d):';
  String get requestsUsed30d => 'Requests (30d):';
  String get resetAt => 'Resets on:';
  String loadFailed({required Object error}) => 'Failed to load: ${error}';
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
  String get configureByok => 'Configure BYOK';
}

// Path: chat.cloudGateway.fallback
class _StringsChatCloudGatewayFallbackEn {
  _StringsChatCloudGatewayFallbackEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get auth => 'Cloud sign-in required. Using BYOK for this request.';
  String get entitlement =>
      'Cloud subscription required. Using BYOK for this request.';
  String get rateLimited =>
      'Cloud is rate limited. Using BYOK for this request.';
  String get generic => 'Cloud request failed. Using BYOK for this request.';
}

// Path: chat.cloudGateway.errors
class _StringsChatCloudGatewayErrorsEn {
  _StringsChatCloudGatewayErrorsEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get auth =>
      'Cloud sign-in required. Open Cloud account and sign in again.';
  String get entitlement =>
      'Cloud subscription required. Configure BYOK or try again later.';
  String get rateLimited => 'Cloud is rate limited. Please try again later.';
  String get generic => 'Cloud request failed.';
}

// Path: sync.fields.baseUrl
class _StringsSyncFieldsBaseUrlEn {
  _StringsSyncFieldsBaseUrlEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Base URL';
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
  String get label => 'Local directory path';
  String get hint => '/Users/me/SecondLoopVault';
  String get helper =>
      'Best for desktop; mobile platforms may not support this path.';
}

// Path: sync.fields.managedVaultBaseUrl
class _StringsSyncFieldsManagedVaultBaseUrlEn {
  _StringsSyncFieldsManagedVaultBaseUrlEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Managed Vault base URL';
  String get hint => 'https://vault.example.com';
}

// Path: sync.fields.vaultId
class _StringsSyncFieldsVaultIdEn {
  _StringsSyncFieldsVaultIdEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Vault ID';
  String get hint => 'Cloud UID';
}

// Path: sync.fields.remoteRoot
class _StringsSyncFieldsRemoteRootEn {
  _StringsSyncFieldsRemoteRootEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Remote root folder';
  String get hint => 'SecondLoop';
}

// Path: sync.fields.passphrase
class _StringsSyncFieldsPassphraseEn {
  _StringsSyncFieldsPassphraseEn._(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  String get label => 'Sync passphrase (not stored; derives a key)';
  String get helper => 'Use the same passphrase on all devices.';
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
  late final _StringsActionsTodoDetailZhCn todoDetail =
      _StringsActionsTodoDetailZhCn._(_root);
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
  late final _StringsSettingsLanguageZhCn language =
      _StringsSettingsLanguageZhCn._(_root);
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
  late final _StringsSettingsCloudAccountZhCn cloudAccount =
      _StringsSettingsCloudAccountZhCn._(_root);
  @override
  late final _StringsSettingsCloudUsageZhCn cloudUsage =
      _StringsSettingsCloudUsageZhCn._(_root);
  @override
  late final _StringsSettingsSubscriptionZhCn subscription =
      _StringsSettingsSubscriptionZhCn._(_root);
  @override
  late final _StringsSettingsSyncZhCn sync = _StringsSettingsSyncZhCn._(_root);
  @override
  late final _StringsSettingsResetLocalDataZhCn resetLocalData =
      _StringsSettingsResetLocalDataZhCn._(_root);
  @override
  late final _StringsSettingsDebugResetLocalDataZhCn debugResetLocalData =
      _StringsSettingsDebugResetLocalDataZhCn._(_root);
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
  String get editMessageTitle => '编辑消息';
  @override
  String get messageUpdated => '消息已更新';
  @override
  String get messageDeleted => '消息已删除';
  @override
  String editFailed({required Object error}) => '编辑失败：${error}';
  @override
  String deleteFailed({required Object error}) => '删除失败：${error}';
  @override
  String get noMessagesYet => '暂无消息';
  @override
  late final _StringsChatFocusZhCn focus = _StringsChatFocusZhCn._(_root);
  @override
  late final _StringsChatAskAiSetupZhCn askAiSetup =
      _StringsChatAskAiSetupZhCn._(_root);
  @override
  late final _StringsChatCloudGatewayZhCn cloudGateway =
      _StringsChatCloudGatewayZhCn._(_root);
  @override
  late final _StringsChatAskAiConsentZhCn askAiConsent =
      _StringsChatAskAiConsentZhCn._(_root);
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
  String get title => 'Vault 同步';
  @override
  late final _StringsSyncSectionsZhCn sections =
      _StringsSyncSectionsZhCn._(_root);
  @override
  late final _StringsSyncAutoSyncZhCn autoSync =
      _StringsSyncAutoSyncZhCn._(_root);
  @override
  String get backendLabel => 'Vault 后端';
  @override
  String get backendWebdav => 'WebDAV';
  @override
  String get backendLocalDir => '本地目录（桌面端）';
  @override
  String get backendManagedVault => '云托管 Vault';
  @override
  late final _StringsSyncCloudManagedVaultZhCn cloudManagedVault =
      _StringsSyncCloudManagedVaultZhCn._(_root);
  @override
  String get remoteRootRequired => '必须填写远端根目录';
  @override
  String get baseUrlRequired => '必须填写 Base URL';
  @override
  String get localDirRequired => '必须填写本地目录';
  @override
  String get connectionOk => '连接正常';
  @override
  String connectionFailed({required Object error}) => '连接失败：${error}';
  @override
  String saveFailed({required Object error}) => '保存失败：${error}';
  @override
  String get missingSyncKey => '缺少同步密钥。请先输入 passphrase 并点击保存。';
  @override
  String pushedOps({required Object count}) => '已推送 ${count} 条操作';
  @override
  String pulledOps({required Object count}) => '已拉取 ${count} 条操作';
  @override
  String pushFailed({required Object error}) => '推送失败：${error}';
  @override
  String pullFailed({required Object error}) => '拉取失败：${error}';
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
  String get title => 'LLM Profiles';
  @override
  String get refreshTooltip => '刷新';
  @override
  String get activeProfileHelp => '当前激活的 profile 用于 Ask AI。';
  @override
  String get noProfilesYet => '暂无 profile。';
  @override
  String get addProfile => '添加 profile';
  @override
  String get deleted => 'LLM profile 已删除';
  @override
  String get validationError => 'Name、API key、Model name 为必填项。';
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
  String get savedActivated => 'LLM profile 已保存并激活';
  @override
  late final _StringsLlmProfilesActionsZhCn actions =
      _StringsLlmProfilesActionsZhCn._(_root);
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
  String get refresh => '刷新';
  @override
  String get search => '搜索';
  @override
  String get useModel => '使用模型';
  @override
  String get processPending => '处理待处理';
  @override
  String get rebuildEmbeddings => '重建向量索引';
  @override
  String get push => '推送';
  @override
  String get pull => '拉取';
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
  String get general => '通用';
  @override
  String get actions => '行动';
  @override
  String get security => '安全';
  @override
  String get connections => '连接';
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
  String get title => 'LLM Profiles';
  @override
  String get subtitle => '为 Ask AI 配置 BYOK';
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
  String get title => 'Cloud 用量';
  @override
  String get subtitle => '当前账期用量';
  @override
  late final _StringsSettingsCloudUsageActionsZhCn actions =
      _StringsSettingsCloudUsageActionsZhCn._(_root);
  @override
  late final _StringsSettingsCloudUsageLabelsZhCn labels =
      _StringsSettingsCloudUsageLabelsZhCn._(_root);
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
  String get subtitle => 'Vault 后端 + 自动同步设置';
}

// Path: settings.resetLocalData
class _StringsSettingsResetLocalDataZhCn
    extends _StringsSettingsResetLocalDataEn {
  _StringsSettingsResetLocalDataZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => '重置本地数据？';
  @override
  String get dialogBody => '这将删除本地消息并清空已同步的远端数据。不会删除你的主密码或本地 LLM/同步配置。你需要重新解锁。';
  @override
  String failed({required Object error}) => '重置失败：${error}';
}

// Path: settings.debugResetLocalData
class _StringsSettingsDebugResetLocalDataZhCn
    extends _StringsSettingsDebugResetLocalDataEn {
  _StringsSettingsDebugResetLocalDataZhCn._(_StringsZhCn root)
      : this._root = root,
        super._(root);

  @override
  final _StringsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '调试：重置本地数据';
  @override
  String get subtitle => '删除本地消息 + 清空已同步的远端数据';
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
  String get body => '要使用「问 AI」，请先配置 BYOK（LLM Profiles）或订阅 SecondLoop Cloud。';
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
  String get title => '发送前确认';
  @override
  String get body =>
      'SecondLoop 会将你的问题与少量相关片段发送到你配置的 LLM 服务商以生成回答。\n\n不会上传：Vault 密钥、同步密钥、完整历史。';
  @override
  String get dontShowAgain => '不再提示';
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
  String get automation => '自动化';
  @override
  String get backend => '后端';
  @override
  String get securityActions => '安全与操作';
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
  String get subtitle => '前台防抖推送 + 后台周期同步（移动端）';
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
  String get signInRequired => '请先登录 Cloud 账号后再使用云托管 Vault。';
  @override
  String get paymentRequired => 'Cloud 同步不可用。请续费订阅以继续同步。';
  @override
  String graceReadonlyUntil({required Object until}) =>
      'Cloud 同步处于只读状态（宽限期至 ${until}）。';
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
  String get title => '删除 profile？';
  @override
  String message({required Object name}) =>
      '确定删除「${name}」？该操作会从本设备移除该 profile。';
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
  String get baseUrlOptional => 'Base URL（可选）';
  @override
  String get modelName => 'Model name';
  @override
  String get apiKey => 'API key';
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
  String get saveActivate => '保存并激活';
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
      'Cloud 登录未配置。请先运行 `pixi run init-env`（或复制 `.env.example` → `.env.local`），填入 `SECONDLOOP_FIREBASE_WEB_API_KEY`，然后重启 App。';
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
  String get gatewayNotConfigured => 'Cloud 网关未配置。';
  @override
  String get signInRequired => '登录后才能查看用量。';
  @override
  String get usage => '用量：';
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
  String get configureByok => '配置 BYOK';
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
  String get auth => 'Cloud 登录已失效。本次将回落到 BYOK。';
  @override
  String get entitlement => '需要订阅 SecondLoop Cloud。本次将回落到 BYOK。';
  @override
  String get rateLimited => 'Cloud 触发限速。本次将回落到 BYOK。';
  @override
  String get generic => 'Cloud 请求失败。本次将回落到 BYOK。';
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
  String get entitlement => '需要订阅 SecondLoop Cloud。请配置 BYOK 或稍后再试。';
  @override
  String get rateLimited => 'Cloud 触发限速，请稍后再试。';
  @override
  String get generic => 'Cloud 请求失败。';
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
  String get label => 'Base URL';
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
  String get label => '本地目录路径';
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
  String get label => '托管 Vault Base URL';
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
  String get label => 'Vault ID';
  @override
  String get hint => 'Cloud UID';
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
  String get label => '远端根目录';
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
  String get label => '同步口令（不会存储；用于派生密钥）';
  @override
  String get helper => '所有设备请使用同一口令。';
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
      case 'common.actions.refresh':
        return 'Refresh';
      case 'common.actions.search':
        return 'Search';
      case 'common.actions.useModel':
        return 'Use model';
      case 'common.actions.processPending':
        return 'Process pending';
      case 'common.actions.rebuildEmbeddings':
        return 'Rebuild embeddings';
      case 'common.actions.push':
        return 'Push';
      case 'common.actions.pull':
        return 'Pull';
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
      case 'actions.todoDetail.title':
        return 'Task';
      case 'actions.todoDetail.emptyTimeline':
        return 'No updates yet';
      case 'actions.todoDetail.noteHint':
        return 'Add a note…';
      case 'actions.todoDetail.addNote':
        return 'Add';
      case 'actions.agenda.title':
        return 'Tasks';
      case 'actions.agenda.summary':
        return ({required Object due, required Object overdue}) =>
            'Today ${due} • Overdue ${overdue}';
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
      case 'settings.sections.general':
        return 'General';
      case 'settings.sections.actions':
        return 'Actions';
      case 'settings.sections.security':
        return 'Security';
      case 'settings.sections.connections':
        return 'Connections';
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
        return 'LLM profiles';
      case 'settings.llmProfiles.subtitle':
        return 'Configure BYOK for Ask AI';
      case 'settings.cloudAccount.title':
        return 'Cloud account';
      case 'settings.cloudAccount.subtitle':
        return 'Sign in to SecondLoop Cloud';
      case 'settings.cloudAccount.signedInAs':
        return ({required Object email}) => 'Signed in as ${email}';
      case 'settings.cloudAccount.errors.missingWebApiKey':
        return 'Cloud sign-in is not configured. Run `pixi run init-env` (or copy `.env.example` → `.env.local`) and set `SECONDLOOP_FIREBASE_WEB_API_KEY`, then restart the app.';
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
        return 'Cloud gateway is not configured.';
      case 'settings.cloudUsage.labels.signInRequired':
        return 'Sign in to view usage.';
      case 'settings.cloudUsage.labels.usage':
        return 'Usage:';
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
      case 'settings.subscription.title':
        return 'Subscription';
      case 'settings.subscription.subtitle':
        return 'Manage SecondLoop Pro';
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
        return 'Vault backends + auto sync settings';
      case 'settings.resetLocalData.dialogTitle':
        return 'Reset local data?';
      case 'settings.resetLocalData.dialogBody':
        return 'This will delete local messages and clear synced remote data. It will NOT delete your master password or local LLM/sync config. You will need to unlock again.';
      case 'settings.resetLocalData.failed':
        return ({required Object error}) => 'Reset failed: ${error}';
      case 'settings.debugResetLocalData.title':
        return 'Debug: Reset local data';
      case 'settings.debugResetLocalData.subtitle':
        return 'Delete local messages + clear synced remote data';
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
      case 'chat.editMessageTitle':
        return 'Edit message';
      case 'chat.messageUpdated':
        return 'Message updated';
      case 'chat.messageDeleted':
        return 'Message deleted';
      case 'chat.editFailed':
        return ({required Object error}) => 'Edit failed: ${error}';
      case 'chat.deleteFailed':
        return ({required Object error}) => 'Delete failed: ${error}';
      case 'chat.noMessagesYet':
        return 'No messages yet';
      case 'chat.focus.tooltip':
        return 'Focus';
      case 'chat.focus.allMemories':
        return 'Focus: All memories';
      case 'chat.focus.thisThread':
        return 'Focus: This thread';
      case 'chat.askAiSetup.title':
        return 'Ask AI setup required';
      case 'chat.askAiSetup.body':
        return 'Configure BYOK (LLM profiles) or subscribe to SecondLoop Cloud to use Ask AI.';
      case 'chat.askAiSetup.actions.subscribe':
        return 'Subscribe';
      case 'chat.askAiSetup.actions.configureByok':
        return 'Configure BYOK';
      case 'chat.cloudGateway.emailNotVerified':
        return 'Email not verified. Verify your email to use SecondLoop Cloud Ask AI.';
      case 'chat.cloudGateway.fallback.auth':
        return 'Cloud sign-in required. Using BYOK for this request.';
      case 'chat.cloudGateway.fallback.entitlement':
        return 'Cloud subscription required. Using BYOK for this request.';
      case 'chat.cloudGateway.fallback.rateLimited':
        return 'Cloud is rate limited. Using BYOK for this request.';
      case 'chat.cloudGateway.fallback.generic':
        return 'Cloud request failed. Using BYOK for this request.';
      case 'chat.cloudGateway.errors.auth':
        return 'Cloud sign-in required. Open Cloud account and sign in again.';
      case 'chat.cloudGateway.errors.entitlement':
        return 'Cloud subscription required. Configure BYOK or try again later.';
      case 'chat.cloudGateway.errors.rateLimited':
        return 'Cloud is rate limited. Please try again later.';
      case 'chat.cloudGateway.errors.generic':
        return 'Cloud request failed.';
      case 'chat.askAiConsent.title':
        return 'Before you ask';
      case 'chat.askAiConsent.body':
        return 'SecondLoop will send your question and a few relevant snippets to your configured LLM provider to generate an answer.\n\nIt will NOT upload your vault key, sync key, or full history.';
      case 'chat.askAiConsent.dontShowAgain':
        return 'Don\'t show again';
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
        return 'Vault Sync';
      case 'sync.sections.automation':
        return 'Automation';
      case 'sync.sections.backend':
        return 'Backend';
      case 'sync.sections.securityActions':
        return 'Security & Actions';
      case 'sync.autoSync.title':
        return 'Auto sync';
      case 'sync.autoSync.subtitle':
        return 'Foreground debounced push + background periodic sync (mobile)';
      case 'sync.backendLabel':
        return 'Vault backend';
      case 'sync.backendWebdav':
        return 'WebDAV';
      case 'sync.backendLocalDir':
        return 'Local directory (desktop)';
      case 'sync.backendManagedVault':
        return 'Cloud managed vault';
      case 'sync.cloudManagedVault.signInRequired':
        return 'Sign in to use Cloud managed vault.';
      case 'sync.cloudManagedVault.paymentRequired':
        return 'Cloud sync is unavailable. Renew your subscription to continue syncing.';
      case 'sync.cloudManagedVault.graceReadonlyUntil':
        return ({required Object until}) =>
            'Cloud sync is read-only until ${until}.';
      case 'sync.remoteRootRequired':
        return 'Remote root is required';
      case 'sync.baseUrlRequired':
        return 'Base URL is required';
      case 'sync.localDirRequired':
        return 'Local directory is required';
      case 'sync.connectionOk':
        return 'Connection OK';
      case 'sync.connectionFailed':
        return ({required Object error}) => 'Connection failed: ${error}';
      case 'sync.saveFailed':
        return ({required Object error}) => 'Save failed: ${error}';
      case 'sync.missingSyncKey':
        return 'Missing sync key. Enter a passphrase and Save first.';
      case 'sync.pushedOps':
        return ({required Object count}) => 'Pushed ${count} ops';
      case 'sync.pulledOps':
        return ({required Object count}) => 'Pulled ${count} ops';
      case 'sync.pushFailed':
        return ({required Object error}) => 'Push failed: ${error}';
      case 'sync.pullFailed':
        return ({required Object error}) => 'Pull failed: ${error}';
      case 'sync.fields.baseUrl.label':
        return 'Base URL';
      case 'sync.fields.baseUrl.hint':
        return 'https://example.com/dav';
      case 'sync.fields.username.label':
        return 'Username (optional)';
      case 'sync.fields.password.label':
        return 'Password (optional)';
      case 'sync.fields.localDir.label':
        return 'Local directory path';
      case 'sync.fields.localDir.hint':
        return '/Users/me/SecondLoopVault';
      case 'sync.fields.localDir.helper':
        return 'Best for desktop; mobile platforms may not support this path.';
      case 'sync.fields.managedVaultBaseUrl.label':
        return 'Managed Vault base URL';
      case 'sync.fields.managedVaultBaseUrl.hint':
        return 'https://vault.example.com';
      case 'sync.fields.vaultId.label':
        return 'Vault ID';
      case 'sync.fields.vaultId.hint':
        return 'Cloud UID';
      case 'sync.fields.remoteRoot.label':
        return 'Remote root folder';
      case 'sync.fields.remoteRoot.hint':
        return 'SecondLoop';
      case 'sync.fields.passphrase.label':
        return 'Sync passphrase (not stored; derives a key)';
      case 'sync.fields.passphrase.helper':
        return 'Use the same passphrase on all devices.';
      case 'llmProfiles.title':
        return 'LLM Profiles';
      case 'llmProfiles.refreshTooltip':
        return 'Refresh';
      case 'llmProfiles.activeProfileHelp':
        return 'Active profile is used for Ask AI.';
      case 'llmProfiles.noProfilesYet':
        return 'No profiles yet.';
      case 'llmProfiles.addProfile':
        return 'Add profile';
      case 'llmProfiles.deleted':
        return 'LLM profile deleted';
      case 'llmProfiles.validationError':
        return 'Name, API key, and model name are required.';
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
        return 'Base URL (optional)';
      case 'llmProfiles.fields.modelName':
        return 'Model name';
      case 'llmProfiles.fields.apiKey':
        return 'API key';
      case 'llmProfiles.providers.openaiCompatible':
        return 'OpenAI-compatible';
      case 'llmProfiles.providers.geminiCompatible':
        return 'Gemini';
      case 'llmProfiles.providers.anthropicCompatible':
        return 'Anthropic';
      case 'llmProfiles.savedActivated':
        return 'LLM profile saved and activated';
      case 'llmProfiles.actions.saveActivate':
        return 'Save & Activate';
      case 'llmProfiles.actions.cancel':
        return 'Cancel';
      case 'llmProfiles.actions.delete':
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
      case 'common.actions.refresh':
        return '刷新';
      case 'common.actions.search':
        return '搜索';
      case 'common.actions.useModel':
        return '使用模型';
      case 'common.actions.processPending':
        return '处理待处理';
      case 'common.actions.rebuildEmbeddings':
        return '重建向量索引';
      case 'common.actions.push':
        return '推送';
      case 'common.actions.pull':
        return '拉取';
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
      case 'actions.todoDetail.title':
        return '待办详情';
      case 'actions.todoDetail.emptyTimeline':
        return '暂无跟进记录';
      case 'actions.todoDetail.noteHint':
        return '补充跟进…';
      case 'actions.todoDetail.addNote':
        return '添加';
      case 'actions.agenda.title':
        return '待办';
      case 'actions.agenda.summary':
        return ({required Object due, required Object overdue}) =>
            '今天 ${due} 条 · 逾期 ${overdue} 条';
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
      case 'settings.sections.general':
        return '通用';
      case 'settings.sections.actions':
        return '行动';
      case 'settings.sections.security':
        return '安全';
      case 'settings.sections.connections':
        return '连接';
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
        return 'LLM Profiles';
      case 'settings.llmProfiles.subtitle':
        return '为 Ask AI 配置 BYOK';
      case 'settings.cloudAccount.title':
        return 'Cloud 账号';
      case 'settings.cloudAccount.subtitle':
        return '登录 SecondLoop Cloud';
      case 'settings.cloudAccount.signedInAs':
        return ({required Object email}) => '已登录：${email}';
      case 'settings.cloudAccount.errors.missingWebApiKey':
        return 'Cloud 登录未配置。请先运行 `pixi run init-env`（或复制 `.env.example` → `.env.local`），填入 `SECONDLOOP_FIREBASE_WEB_API_KEY`，然后重启 App。';
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
        return 'Cloud 用量';
      case 'settings.cloudUsage.subtitle':
        return '当前账期用量';
      case 'settings.cloudUsage.actions.refresh':
        return '刷新';
      case 'settings.cloudUsage.labels.gatewayNotConfigured':
        return 'Cloud 网关未配置。';
      case 'settings.cloudUsage.labels.signInRequired':
        return '登录后才能查看用量。';
      case 'settings.cloudUsage.labels.usage':
        return '用量：';
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
      case 'settings.subscription.title':
        return '订阅';
      case 'settings.subscription.subtitle':
        return '管理 SecondLoop Pro';
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
        return 'Vault 后端 + 自动同步设置';
      case 'settings.resetLocalData.dialogTitle':
        return '重置本地数据？';
      case 'settings.resetLocalData.dialogBody':
        return '这将删除本地消息并清空已同步的远端数据。不会删除你的主密码或本地 LLM/同步配置。你需要重新解锁。';
      case 'settings.resetLocalData.failed':
        return ({required Object error}) => '重置失败：${error}';
      case 'settings.debugResetLocalData.title':
        return '调试：重置本地数据';
      case 'settings.debugResetLocalData.subtitle':
        return '删除本地消息 + 清空已同步的远端数据';
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
      case 'chat.editMessageTitle':
        return '编辑消息';
      case 'chat.messageUpdated':
        return '消息已更新';
      case 'chat.messageDeleted':
        return '消息已删除';
      case 'chat.editFailed':
        return ({required Object error}) => '编辑失败：${error}';
      case 'chat.deleteFailed':
        return ({required Object error}) => '删除失败：${error}';
      case 'chat.noMessagesYet':
        return '暂无消息';
      case 'chat.focus.tooltip':
        return '聚焦';
      case 'chat.focus.allMemories':
        return '聚焦：所有记忆';
      case 'chat.focus.thisThread':
        return '聚焦：当前对话';
      case 'chat.askAiSetup.title':
        return '问 AI 需要先配置';
      case 'chat.askAiSetup.body':
        return '要使用「问 AI」，请先配置 BYOK（LLM Profiles）或订阅 SecondLoop Cloud。';
      case 'chat.askAiSetup.actions.subscribe':
        return '订阅';
      case 'chat.askAiSetup.actions.configureByok':
        return '配置 BYOK';
      case 'chat.cloudGateway.emailNotVerified':
        return '邮箱未验证。验证邮箱后才能使用 SecondLoop Cloud Ask AI。';
      case 'chat.cloudGateway.fallback.auth':
        return 'Cloud 登录已失效。本次将回落到 BYOK。';
      case 'chat.cloudGateway.fallback.entitlement':
        return '需要订阅 SecondLoop Cloud。本次将回落到 BYOK。';
      case 'chat.cloudGateway.fallback.rateLimited':
        return 'Cloud 触发限速。本次将回落到 BYOK。';
      case 'chat.cloudGateway.fallback.generic':
        return 'Cloud 请求失败。本次将回落到 BYOK。';
      case 'chat.cloudGateway.errors.auth':
        return 'Cloud 登录已失效，请在 Cloud 账号页重新登录。';
      case 'chat.cloudGateway.errors.entitlement':
        return '需要订阅 SecondLoop Cloud。请配置 BYOK 或稍后再试。';
      case 'chat.cloudGateway.errors.rateLimited':
        return 'Cloud 触发限速，请稍后再试。';
      case 'chat.cloudGateway.errors.generic':
        return 'Cloud 请求失败。';
      case 'chat.askAiConsent.title':
        return '发送前确认';
      case 'chat.askAiConsent.body':
        return 'SecondLoop 会将你的问题与少量相关片段发送到你配置的 LLM 服务商以生成回答。\n\n不会上传：Vault 密钥、同步密钥、完整历史。';
      case 'chat.askAiConsent.dontShowAgain':
        return '不再提示';
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
        return 'Vault 同步';
      case 'sync.sections.automation':
        return '自动化';
      case 'sync.sections.backend':
        return '后端';
      case 'sync.sections.securityActions':
        return '安全与操作';
      case 'sync.autoSync.title':
        return '自动同步';
      case 'sync.autoSync.subtitle':
        return '前台防抖推送 + 后台周期同步（移动端）';
      case 'sync.backendLabel':
        return 'Vault 后端';
      case 'sync.backendWebdav':
        return 'WebDAV';
      case 'sync.backendLocalDir':
        return '本地目录（桌面端）';
      case 'sync.backendManagedVault':
        return '云托管 Vault';
      case 'sync.cloudManagedVault.signInRequired':
        return '请先登录 Cloud 账号后再使用云托管 Vault。';
      case 'sync.cloudManagedVault.paymentRequired':
        return 'Cloud 同步不可用。请续费订阅以继续同步。';
      case 'sync.cloudManagedVault.graceReadonlyUntil':
        return ({required Object until}) => 'Cloud 同步处于只读状态（宽限期至 ${until}）。';
      case 'sync.remoteRootRequired':
        return '必须填写远端根目录';
      case 'sync.baseUrlRequired':
        return '必须填写 Base URL';
      case 'sync.localDirRequired':
        return '必须填写本地目录';
      case 'sync.connectionOk':
        return '连接正常';
      case 'sync.connectionFailed':
        return ({required Object error}) => '连接失败：${error}';
      case 'sync.saveFailed':
        return ({required Object error}) => '保存失败：${error}';
      case 'sync.missingSyncKey':
        return '缺少同步密钥。请先输入 passphrase 并点击保存。';
      case 'sync.pushedOps':
        return ({required Object count}) => '已推送 ${count} 条操作';
      case 'sync.pulledOps':
        return ({required Object count}) => '已拉取 ${count} 条操作';
      case 'sync.pushFailed':
        return ({required Object error}) => '推送失败：${error}';
      case 'sync.pullFailed':
        return ({required Object error}) => '拉取失败：${error}';
      case 'sync.fields.baseUrl.label':
        return 'Base URL';
      case 'sync.fields.baseUrl.hint':
        return 'https://example.com/dav';
      case 'sync.fields.username.label':
        return '用户名（可选）';
      case 'sync.fields.password.label':
        return '密码（可选）';
      case 'sync.fields.localDir.label':
        return '本地目录路径';
      case 'sync.fields.localDir.hint':
        return '/Users/me/SecondLoopVault';
      case 'sync.fields.localDir.helper':
        return '更适合桌面端；移动端可能不支持该路径。';
      case 'sync.fields.managedVaultBaseUrl.label':
        return '托管 Vault Base URL';
      case 'sync.fields.managedVaultBaseUrl.hint':
        return 'https://vault.example.com';
      case 'sync.fields.vaultId.label':
        return 'Vault ID';
      case 'sync.fields.vaultId.hint':
        return 'Cloud UID';
      case 'sync.fields.remoteRoot.label':
        return '远端根目录';
      case 'sync.fields.remoteRoot.hint':
        return 'SecondLoop';
      case 'sync.fields.passphrase.label':
        return '同步口令（不会存储；用于派生密钥）';
      case 'sync.fields.passphrase.helper':
        return '所有设备请使用同一口令。';
      case 'llmProfiles.title':
        return 'LLM Profiles';
      case 'llmProfiles.refreshTooltip':
        return '刷新';
      case 'llmProfiles.activeProfileHelp':
        return '当前激活的 profile 用于 Ask AI。';
      case 'llmProfiles.noProfilesYet':
        return '暂无 profile。';
      case 'llmProfiles.addProfile':
        return '添加 profile';
      case 'llmProfiles.deleted':
        return 'LLM profile 已删除';
      case 'llmProfiles.validationError':
        return 'Name、API key、Model name 为必填项。';
      case 'llmProfiles.deleteDialog.title':
        return '删除 profile？';
      case 'llmProfiles.deleteDialog.message':
        return ({required Object name}) => '确定删除「${name}」？该操作会从本设备移除该 profile。';
      case 'llmProfiles.fields.name':
        return '名称';
      case 'llmProfiles.fields.provider':
        return '提供商';
      case 'llmProfiles.fields.baseUrlOptional':
        return 'Base URL（可选）';
      case 'llmProfiles.fields.modelName':
        return 'Model name';
      case 'llmProfiles.fields.apiKey':
        return 'API key';
      case 'llmProfiles.providers.openaiCompatible':
        return 'OpenAI 兼容';
      case 'llmProfiles.providers.geminiCompatible':
        return 'Gemini';
      case 'llmProfiles.providers.anthropicCompatible':
        return 'Anthropic';
      case 'llmProfiles.savedActivated':
        return 'LLM profile 已保存并激活';
      case 'llmProfiles.actions.saveActivate':
        return '保存并激活';
      case 'llmProfiles.actions.cancel':
        return '取消';
      case 'llmProfiles.actions.delete':
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
