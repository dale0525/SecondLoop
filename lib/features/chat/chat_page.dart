import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/ai/semantic_parse.dart';
import '../../core/ai/semantic_parse_data_consent_prefs.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/platform/platform_location.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_focus_ring.dart';
import '../../ui/sl_icon_button_frame.dart';
import '../../ui/sl_icon_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../../ui/sl_typing_indicator.dart';
import '../actions/assistant_message_actions.dart';
import '../actions/agenda/todo_agenda_banner.dart';
import '../actions/agenda/todo_agenda_page.dart';
import '../actions/calendar/calendar_action.dart';
import '../actions/review/review_backoff.dart';
import '../actions/review/review_queue_banner.dart';
import '../actions/review/review_queue_page.dart';
import '../actions/settings/actions_settings_store.dart';
import '../actions/suggestions_card.dart';
import '../actions/suggestions_parser.dart';
import '../actions/todo/todo_detail_page.dart';
import '../actions/todo/todo_linking.dart';
import '../actions/todo/message_action_resolver.dart';
import '../actions/todo/message_auto_actions_queue.dart';
import '../actions/todo/todo_thread_match.dart';
import '../actions/time/date_time_picker_dialog.dart';
import '../actions/time/time_resolver.dart';
import '../attachments/attachment_card.dart';
import '../attachments/attachment_viewer_page.dart';
import '../attachments/image_exif_metadata.dart';
import '../attachments/platform_exif_metadata.dart';
import '../media_backup/audio_transcode_policy.dart';
import '../media_backup/audio_transcode_worker.dart';
import '../media_backup/image_compression.dart';
import '../settings/cloud_account_page.dart';
import '../settings/llm_profiles_page.dart';
import '../settings/settings_page.dart';
import 'chat_image_attachment_thumbnail.dart';
import 'deferred_attachment_location_upsert.dart';
import 'chat_markdown_sanitizer.dart';
import 'message_viewer_page.dart';
import 'ask_ai_intent_resolver.dart';
import 'semantic_parse_job_status_row.dart';
import 'attachment_annotation_job_status_row.dart';

part 'chat_page_methods_a.dart';
part 'chat_page_methods_b.dart';
part 'chat_page_methods_b_attachments.dart';
part 'chat_page_methods_c.dart';
part 'chat_page_methods_d.dart';
part 'chat_page_methods_e.dart';
part 'chat_page_message_item_builder.dart';
part 'chat_page_build_helpers.dart';
part 'chat_page_build.dart';
part 'chat_page_build_desktop_drop.dart';

const _kAskAiDataConsentPrefsKey = 'ask_ai_data_consent_v1';
const _kEmbeddingsDataConsentPrefsKey = 'embeddings_data_consent_v1';
const _kCloudEmbeddingsModelName = 'baai/bge-m3';
const _kAskAiCloudFallbackSnackKey = ValueKey(
  'ask_ai_cloud_fallback_snack',
);
const _kAskAiEmailNotVerifiedSnackKey = ValueKey(
  'ask_ai_email_not_verified_snack',
);

const _kAskAiErrorPrefix = '\u001eSL_ERROR\u001e';
const _kFailedAskMessageId = 'pending_failed_user';
const _kCollapsedMessageHeight = 280.0;
const _kLongMessageRuneThreshold = 600;
const _kLongMessageLineThreshold = 12;
const _kMessagePageSize = 60;
const _kLoadMoreThresholdPx = 200.0;
const _kBottomThresholdPx = 60.0;
const _kTodoAutoSemanticTimeout = Duration(milliseconds: 280);
const _kTodoLinkSheetRerankTimeout = Duration(milliseconds: 5000);
const _kAiSemanticParseTimeout = Duration(milliseconds: 2500);
const _kAiTimeWindowParseMinConfidence = 0.75;

final RegExp _kBareTodoStatusUpdateRegex = RegExp(
  r'^[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]*'
  r'(done|finished|finish|complete|completed|cancel|cancelled|dismiss|delete|deleted|'
  r'完成|完成了|已完成|做完|做完了|搞定|搞定了|取消|不用了|算了|删掉|删除|刪除|'
  r'完了|完了した|終わった|完了|中止|キャンセル|削除|'
  r'취소|삭제)'
  r'[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]*$',
  caseSensitive: false,
);

bool _looksLikeBareTodoStatusUpdate(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '✅' || trimmed == '✔' || trimmed == '✓') return true;
  return _kBareTodoStatusUpdateRegex.hasMatch(trimmed);
}

final RegExp _kTrimPunctuationEnds = RegExp(
  r'^[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]+|[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]+$',
);

bool _looksLikeTodoRelevantForAi(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('\n')) return false;
  if (trimmed.runes.length >= 200) return false;
  if (trimmed.contains('?') || trimmed.contains('？')) return false;
  if (_looksLikeBareTodoStatusUpdate(trimmed)) return false;

  final normalized =
      trimmed.toLowerCase().replaceAll(_kTrimPunctuationEnds, '').trim();
  const ignored = <String>{
    'hi',
    'hello',
    'hey',
    'ok',
    'okay',
    'k',
    'kk',
    'thanks',
    'thank you',
    'thx',
    'lol',
    'haha',
    'yep',
    'nope',
    'yes',
    'no',
    'sure',
    'nice',
    'good',
    'great',
    'cool',
    '👍',
    '👌',
    '🙏',
    '你好',
    '嗨',
    '在吗',
    '好的',
    '好',
    '行',
    '可以',
    'ok了',
    '谢谢',
    '谢了',
    '哈哈',
    '嗯',
  };
  if (normalized.isEmpty) return false;
  if (ignored.contains(normalized)) return false;
  return true;
}

bool _isSameLocalDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _dueBoost(DateTime? dueLocal, DateTime nowLocal) {
  if (dueLocal == null) return 0;
  final diffMinutes = dueLocal.difference(nowLocal).inMinutes.abs();
  if (diffMinutes <= 120) return 1500;
  if (diffMinutes <= 360) return 800;
  if (diffMinutes <= 1440) return 200;
  return 0;
}

int _semanticBoost(int rank, double distance) {
  if (!distance.isFinite) return 0;
  final base = distance <= 0.35
      ? 2200
      : distance <= 0.50
          ? 1400
          : distance <= 0.70
              ? 800
              : 0;
  if (base == 0) return 0;

  final factor = switch (rank) {
    0 => 1.0,
    1 => 0.7,
    2 => 0.5,
    3 => 0.4,
    _ => 0.3,
  };
  return (base * factor).round();
}

List<TodoLinkCandidate> _mergeTodoCandidatesWithSemanticMatches({
  required String query,
  required List<TodoLinkTarget> targets,
  required DateTime nowLocal,
  required List<TodoThreadMatch> semanticMatches,
  required int limit,
}) {
  final ranked =
      rankTodoCandidates(query, targets, nowLocal: nowLocal, limit: limit);
  if (semanticMatches.isEmpty) return ranked;

  final targetsById = <String, TodoLinkTarget>{};
  for (final t in targets) {
    targetsById[t.id] = t;
  }

  final scoreByTodoId = <String, int>{};
  for (final c in ranked) {
    scoreByTodoId[c.target.id] = c.score;
  }

  for (var i = 0; i < semanticMatches.length && i < limit; i++) {
    final match = semanticMatches[i];
    final target = targetsById[match.todoId];
    if (target == null) continue;

    final boost = _semanticBoost(i, match.distance);
    if (boost <= 0) continue;

    final existing = scoreByTodoId[target.id];
    final base = existing ?? _dueBoost(target.dueLocal, nowLocal);
    scoreByTodoId[target.id] = base + boost;
  }

  final merged = <TodoLinkCandidate>[];
  scoreByTodoId.forEach((id, score) {
    final target = targetsById[id];
    if (target == null) return;
    merged.add(TodoLinkCandidate(target: target, score: score));
  });
  merged.sort((a, b) => b.score.compareTo(a.score));
  if (merged.length <= limit) return merged;
  return merged.sublist(0, limit);
}

String _formatTzOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes >= 0 ? '+' : '-';
  final abs = minutes.abs();
  final hh = (abs ~/ 60).toString().padLeft(2, '0');
  final mm = (abs % 60).toString().padLeft(2, '0');
  return '$sign$hh:$mm';
}

String _formatMessageTimestamp(BuildContext context, int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final localizations = MaterialLocalizations.of(context);
  final alwaysUse24HourFormat = MediaQuery.of(context).alwaysUse24HourFormat;
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(dt),
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  return time;
}

DateTime? _messageLocalDay(int ms) {
  if (ms <= 0) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return DateTime(dt.year, dt.month, dt.day);
}

String _formatMessageDateDividerLabel(
  BuildContext context,
  DateTime dayLocal,
) {
  final localizations = MaterialLocalizations.of(context);
  final nowLocal = DateTime.now();
  if (dayLocal.year != nowLocal.year) {
    return localizations.formatMediumDate(dayLocal);
  }
  return localizations.formatShortMonthDay(dayLocal);
}

Widget _buildMessageDateDividerChip(
  BuildContext context,
  DateTime dayLocal, {
  required Key key,
}) {
  final tokens = SlTokens.of(context);
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final label = _formatMessageDateDividerLabel(context, dayLocal);

  return Center(
    child: Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface.withOpacity(isDark ? 0.72 : 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tokens.borderSubtle.withOpacity(isDark ? 0.78 : 1),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(
                isDark ? 0.9 : 0.82,
              ),
              fontWeight: FontWeight.w600,
            ),
      ),
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.conversation,
    this.isTabActive = true,
    super.key,
  });

  final Conversation conversation;
  final bool isTabActive;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Future<List<Message>>? _messagesFuture;
  Future<int>? _reviewCountFuture;
  Future<_TodoAgendaSummary>? _agendaFuture;
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByMessageId =
      <String, Future<List<Attachment>>>{};
  final Map<String, List<Attachment>> _attachmentsCacheByMessageId =
      <String, List<Attachment>>{};
  final Map<String, Future<_AttachmentEnrichment>>
      _attachmentEnrichmentFuturesBySha256 =
      <String, Future<_AttachmentEnrichment>>{};
  final Map<String, _AttachmentEnrichment> _attachmentEnrichmentCacheBySha256 =
      <String, _AttachmentEnrichment>{};
  List<Message> _paginatedMessages = <Message>[];
  List<Message> _latestLoadedMessages = const <Message>[];
  bool _loadingMoreMessages = false;
  bool _hasMoreMessages = true;
  bool _isAtBottom = true;
  bool _hasUnseenNewMessages = false;
  bool _sending = false;
  bool _asking = false;
  bool _stopRequested = false;
  bool _desktopDropActive = false;
  bool _thisThreadOnly = false;
  bool _hoverActionsEnabled = false;
  bool _cloudEmbeddingsConsented = false;
  String? _hoveredMessageId;
  String? _pendingQuestion;
  String _streamingAnswer = '';
  String? _askError;
  String? _askFailureMessage;
  String? _askFailureQuestion;
  int? _askAttemptCreatedAtMs;
  int? _askFailureCreatedAtMs;
  String? _askAttemptAnchorMessageId;
  String? _askFailureAnchorMessageId;
  StreamSubscription<String>? _askSub;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  MessageAutoActionsQueue? _messageAutoActionsQueue;
  int _todoAgendaBannerCollapseSignal = 0;

  void _setState(VoidCallback fn) => setState(fn);

  void _collapseTodoAgendaBanner() {
    setState(() => _todoAgendaBannerCollapseSignal++);
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTabActive && !oldWidget.isTabActive) {
      _collapseTodoAgendaBanner();
    }
  }

  bool get _usePagination => widget.conversation.id == 'main_stream';
  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
  bool get _supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _supportsImageUpload => _supportsCamera || _isDesktopPlatform;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadEmbeddingsDataConsentPreference());
  }

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
    _messageAutoActionsQueue?.dispose();
    _askSub?.cancel();
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagesFuture ??= _loadMessages();
    _reviewCountFuture ??= _loadReviewQueueCount();
    _agendaFuture ??= _loadTodoAgendaSummary();
    _attachSyncEngine();
  }

  @override
  Widget build(BuildContext context) => _build(context);
}

final class _TodoLinkSheet extends StatefulWidget {
  const _TodoLinkSheet({
    required this.initialRanked,
    required this.statusLabel,
    required this.todoStatusLabel,
    required this.showEnableCloudButton,
    this.requestImprovedRanked,
    this.ensureCloudEmbeddingsConsented,
    this.requestCloudRanked,
  });

  final List<TodoLinkCandidate> initialRanked;
  final String statusLabel;
  final String Function(String status) todoStatusLabel;
  final bool showEnableCloudButton;
  final Future<List<TodoLinkCandidate>>? requestImprovedRanked;
  final Future<bool> Function()? ensureCloudEmbeddingsConsented;
  final Future<List<TodoLinkCandidate>?> Function()? requestCloudRanked;

  @override
  State<_TodoLinkSheet> createState() => _TodoLinkSheetState();
}

final class _TodoLinkSheetState extends State<_TodoLinkSheet> {
  late List<TodoLinkCandidate> _ranked;
  bool _improving = false;
  late bool _showEnableCloudButton;

  @override
  void didUpdateWidget(covariant _TodoLinkSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showEnableCloudButton != widget.showEnableCloudButton) {
      _showEnableCloudButton = widget.showEnableCloudButton;
    }
  }

  @override
  void initState() {
    super.initState();
    _ranked = widget.initialRanked;
    _showEnableCloudButton = widget.showEnableCloudButton;

    final future = widget.requestImprovedRanked;
    if (future != null) {
      _improving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        List<TodoLinkCandidate> improved = _ranked;
        try {
          improved = await future;
        } catch (_) {
          improved = _ranked;
        }
        if (!mounted) return;
        setState(() {
          _ranked = improved;
          _improving = false;
        });
      });
    }
  }

  Future<void> _enableCloudEmbeddings() async {
    final ensureConsent = widget.ensureCloudEmbeddingsConsented;
    final requestCloudRanked = widget.requestCloudRanked;
    if (ensureConsent == null || requestCloudRanked == null) return;

    final consented = await ensureConsent();
    if (!consented || !mounted) return;

    setState(() {
      _showEnableCloudButton = false;
      _improving = true;
    });

    List<TodoLinkCandidate>? improved;
    try {
      improved = await requestCloudRanked();
    } catch (_) {
      improved = null;
    }
    if (!mounted) return;

    setState(() {
      if (improved != null) {
        _ranked = improved;
      }
      _improving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.actions.todoLink.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(context.t.actions.todoLink.subtitle(status: widget.statusLabel)),
          if (_showEnableCloudButton) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('todo_link_sheet_enable_cloud'),
              onPressed: _improving ? null : _enableCloudEmbeddings,
              child: Text(context.t.chat.embeddingsConsent.actions.enableCloud),
            ),
          ],
          if (_improving) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  context.t.settings.byokUsage.loading,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _ranked.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final c = _ranked[index];
                return ListTile(
                  title: Text(c.target.title),
                  subtitle: Text(widget.todoStatusLabel(c.target.status)),
                  onTap: () => Navigator.of(context).pop(c.target.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _AttachmentEnrichment {
  const _AttachmentEnrichment({
    required this.placeDisplayName,
    required this.captionLong,
  });

  final String? placeDisplayName;
  final String? captionLong;
}

final class _TodoAgendaSummary {
  const _TodoAgendaSummary({
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.previewTodos,
  });

  const _TodoAgendaSummary.empty()
      : dueCount = 0,
        overdueCount = 0,
        upcomingCount = 0,
        previewTodos = const <Todo>[];

  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final List<Todo> previewTodos;
}

enum _MessageAction {
  copy,
  convertTodo,
  convertTodoToInfo,
  openTodo,
  edit,
  linkTodo,
  delete,
}

enum _AskAiSetupAction {
  subscribe,
  configureByok,
}
