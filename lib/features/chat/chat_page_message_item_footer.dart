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
    final stableCreatedAtMs = platformIntToInt(stableMsg.createdAtMs);
    final dayLocal = _messageLocalDay(stableCreatedAtMs);
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
      final neighborCreatedAtMs = platformIntToInt(neighborMsg.createdAtMs);
      if (!_isTransientPendingMessageId(neighborMsg.id) &&
          neighborCreatedAtMs > 0) {
        neighborStableMessage = neighborMsg;
        break;
      }
      neighborIndex += step;
    }

    final neighborDay = neighborStableMessage == null
        ? null
        : _messageLocalDay(
            platformIntToInt(neighborStableMessage.createdAtMs),
          );
    final showDateDivider =
        dayLocal != null && (neighborDay == null || neighborDay != dayLocal);

    final showTimeDivider = !showDateDivider &&
        stableCreatedAtMs > 0 &&
        neighborStableMessage != null &&
        Duration(
              milliseconds: (stableCreatedAtMs -
                      platformIntToInt(neighborStableMessage.createdAtMs))
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
    final stableCreatedAtMs = platformIntToInt(stableMsg.createdAtMs);
    if (showDateDivider && dayLocal != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _buildMessageDateDividerChip(
          context,
          dayLocal,
          key: ValueKey('message_date_divider_${stableMsg.id}'),
          overrideLabel: stableCreatedAtMs > 0
              ? _formatMessageDateTimeDividerLabel(
                  context,
                  stableCreatedAtMs,
                )
              : null,
        ),
      );
    }

    if (showTimeDivider && stableCreatedAtMs > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _buildMessageTimeDividerChip(
          context,
          stableCreatedAtMs,
          key: ValueKey('message_time_divider_${stableMsg.id}'),
        ),
      );
    }

    return null;
  }
}
