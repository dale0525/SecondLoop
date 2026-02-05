import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';

class AttachmentAnnotationJobStatusRow extends StatefulWidget {
  const AttachmentAnnotationJobStatusRow({
    required this.job,
    required this.annotateEnabled,
    required this.canAnnotateNow,
    this.onOpenSetup,
    this.onRetry,
    super.key,
  });

  final AttachmentAnnotationJob job;
  final bool annotateEnabled;
  final bool canAnnotateNow;
  final Future<void> Function()? onOpenSetup;
  final Future<void> Function()? onRetry;

  static const _kSoftDelay = Duration(milliseconds: 700);
  static const _kSlowThreshold = Duration(seconds: 3);

  @override
  State<AttachmentAnnotationJobStatusRow> createState() =>
      _AttachmentAnnotationJobStatusRowState();
}

class _AttachmentAnnotationJobStatusRowState
    extends State<AttachmentAnnotationJobStatusRow> {
  Timer? _softTimer;
  Timer? _slowTimer;
  bool _passedSoftDelay = false;
  bool _passedSlowThreshold = false;

  @override
  void initState() {
    super.initState();
    _scheduleTickers();
  }

  @override
  void didUpdateWidget(covariant AttachmentAnnotationJobStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.annotateEnabled != widget.annotateEnabled ||
        oldWidget.job.status != widget.job.status ||
        oldWidget.job.createdAtMs != widget.job.createdAtMs ||
        oldWidget.job.updatedAtMs != widget.job.updatedAtMs) {
      _scheduleTickers();
    }
  }

  @override
  void dispose() {
    _softTimer?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  void _scheduleTickers() {
    _softTimer?.cancel();
    _slowTimer?.cancel();
    _softTimer = null;
    _slowTimer = null;

    if (!widget.annotateEnabled) {
      _passedSoftDelay = false;
      _passedSlowThreshold = false;
      return;
    }

    final status = widget.job.status;
    if (status != 'pending') {
      _passedSoftDelay = true;
      _passedSlowThreshold = true;
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final createdAtMs = widget.job.createdAtMs.toInt();
    final ageMs = nowMs - createdAtMs;

    final softDelayMs =
        AttachmentAnnotationJobStatusRow._kSoftDelay.inMilliseconds - ageMs;
    if (softDelayMs <= 0) {
      _passedSoftDelay = true;
    } else {
      _passedSoftDelay = false;
      _softTimer = Timer(Duration(milliseconds: softDelayMs), () {
        if (!mounted) return;
        setState(() => _passedSoftDelay = true);
      });
    }

    final slowDelayMs =
        AttachmentAnnotationJobStatusRow._kSlowThreshold.inMilliseconds - ageMs;
    if (slowDelayMs <= 0) {
      _passedSlowThreshold = true;
    } else {
      _passedSlowThreshold = false;
      _slowTimer = Timer(Duration(milliseconds: slowDelayMs), () {
        if (!mounted) return;
        setState(() => _passedSlowThreshold = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.annotateEnabled) {
      return const SizedBox.shrink();
    }

    final job = widget.job;
    final status = job.status;
    final isPending = status == 'pending';
    final isFailed = status == 'failed';
    if (!isPending && !isFailed) {
      return const SizedBox.shrink();
    }

    if (isPending && !_passedSoftDelay) {
      return const SizedBox.shrink();
    }

    final t = context.t;
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.canAnnotateNow) {
      final actions = <Widget>[];
      final onOpen = widget.onOpenSetup;
      if (onOpen != null) {
        actions.add(
          TextButton(
            onPressed: () => unawaited(onOpen()),
            child: Text(t.common.actions.open),
          ),
        );
      }

      final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withOpacity(0.78),
          );
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_outlined,
              size: 14,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                t.chat.attachmentAnnotationNeedsSetup,
                style: textStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 6),
              ...actions.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: a,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final isSlow = isPending && _passedSlowThreshold;

    final label = isPending
        ? (isSlow
            ? t.chat.semanticParseStatusSlow
            : t.chat.semanticParseStatusRunning)
        : t.chat.semanticParseStatusFailed;

    final leading = isPending
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.outline,
            ),
          )
        : Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: colorScheme.error,
          );

    final actions = <Widget>[];
    if (isFailed && widget.onRetry != null) {
      actions.add(
        TextButton(
          onPressed: () => unawaited(widget.onRetry!()),
          child: Text(t.common.actions.retry),
        ),
      );
    }

    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withOpacity(0.78),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 6),
            ...actions.map(
              (a) => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: a,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
