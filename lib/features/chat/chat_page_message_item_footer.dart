part of 'chat_page.dart';

class _MessageDividerState {
  const _MessageDividerState({
    required this.dayLocal,
    required this.showDateDivider,
    required this.showTimeDivider,
  });

  final DateTime? dayLocal;
  final bool showDateDivider;
  final bool showTimeDivider;
}

extension _ChatPageStateMessageItemFooter on _ChatPageState {
  bool _isTransientPendingMessageId(String id) =>
      id.startsWith('pending_') && id != _kFailedAskMessageId;

  _MessageDividerState _resolveMessageDividerState({
    required int index,
    required Message stableMsg,
    required int itemCount,
    required Message? Function(int targetIndex) messageAt,
  }) {
    final dayLocal = _messageLocalDay(stableMsg.createdAtMs);
    if (_isTransientPendingMessageId(stableMsg.id)) {
      return const _MessageDividerState(
        dayLocal: null,
        showDateDivider: false,
        showTimeDivider: false,
      );
    }

    final step = _usePagination ? 1 : -1;
    var neighborIndex = index + step;
    Message? neighborStableMessage;
    while (neighborIndex >= 0 && neighborIndex < itemCount) {
      final neighborMsg = messageAt(neighborIndex);
      if (neighborMsg == null) break;
      if (!_isTransientPendingMessageId(neighborMsg.id) &&
          neighborMsg.createdAtMs > 0) {
        neighborStableMessage = neighborMsg;
        break;
      }
      neighborIndex += step;
    }

    final neighborDay = neighborStableMessage == null
        ? null
        : _messageLocalDay(neighborStableMessage.createdAtMs);
    final showDateDivider =
        dayLocal != null && (neighborDay == null || neighborDay != dayLocal);

    final showTimeDivider = !showDateDivider &&
        stableMsg.createdAtMs > 0 &&
        neighborStableMessage != null &&
        Duration(
              milliseconds:
                  (stableMsg.createdAtMs - neighborStableMessage.createdAtMs)
                      .abs(),
            ) >=
            _kMessageTimeDividerGap;

    return _MessageDividerState(
      dayLocal: dayLocal,
      showDateDivider: showDateDivider,
      showTimeDivider: showTimeDivider,
    );
  }

  Widget? _buildInterleavedMessageDivider({
    required BuildContext context,
    required Message stableMsg,
    required DateTime? dayLocal,
    required bool showDateDivider,
    required bool showTimeDivider,
  }) {
    if (showDateDivider && dayLocal != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _buildMessageDateDividerChip(
          context,
          dayLocal,
          key: ValueKey('message_date_divider_${stableMsg.id}'),
          overrideLabel: stableMsg.createdAtMs > 0
              ? _formatMessageDateTimeDividerLabel(
                  context,
                  stableMsg.createdAtMs,
                )
              : null,
        ),
      );
    }

    if (showTimeDivider && stableMsg.createdAtMs > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _buildMessageTimeDividerChip(
          context,
          stableMsg.createdAtMs,
          key: ValueKey('message_time_divider_${stableMsg.id}'),
        ),
      );
    }

    return null;
  }
}
