import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'review_models.dart';
import 'review_widgets.dart';

final class ReviewPage extends StatefulWidget {
  const ReviewPage({
    this.items,
    super.key,
  });

  final List<ReviewItem>? items;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

final class _ReviewPageState extends State<ReviewPage> {
  late final List<ReviewItem> _items =
      List<ReviewItem>.of(widget.items ?? demoReviewItems());
  late ReviewItem? _selectedItem = _items.isEmpty ? null : _items.first;

  void _selectDesktop(ReviewItem item) {
    setState(() => _selectedItem = item);
  }

  void _resolveItem(ReviewItem item) {
    setState(() {
      final index = _items.indexWhere((candidate) => candidate.id == item.id);
      if (index < 0) return;
      _items.removeAt(index);
      if (_items.isEmpty) {
        _selectedItem = null;
        return;
      }
      _selectedItem = _items[index.clamp(0, _items.length - 1)];
    });
  }

  void _openMobileDetail(BuildContext context, ReviewItem item) {
    setState(() => _selectedItem = item);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          key: const ValueKey('review_detail_sheet'),
          heightFactor: 0.86,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
            child: ReviewDetail(
              item: item,
              onApprove: () {
                _resolveItem(item);
                Navigator.of(context).maybePop();
              },
              onReject: () {
                _resolveItem(item);
                Navigator.of(context).maybePop();
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final useWideLayout = constraints.maxWidth >= 760;
          if (!useWideLayout) {
            return Padding(
              padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
              child: ReviewQueueList(
                items: _items,
                selectedItem: _selectedItem,
                onSelect: (item) => _openMobileDetail(context, item),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 360,
                  child: ReviewQueueList(
                    items: _items,
                    selectedItem: _selectedItem,
                    onSelect: _selectDesktop,
                  ),
                ),
                const SizedBox(width: AgentDesignTokens.gapLg),
                Expanded(
                  child: SingleChildScrollView(
                    child: _selectedItem == null
                        ? const _EmptyReviewDetail()
                        : ReviewDetail(
                            item: _selectedItem!,
                            onApprove: () => _resolveItem(_selectedItem!),
                            onReject: () => _resolveItem(_selectedItem!),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class _EmptyReviewDetail extends StatelessWidget {
  const _EmptyReviewDetail();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(context.t.actions.reviewQueue.empty));
  }
}
