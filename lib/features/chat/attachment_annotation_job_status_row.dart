import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio_transcribe/audio_transcribe_runner.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';

class AttachmentAnnotationJobStatusRow extends StatefulWidget {
  const AttachmentAnnotationJobStatusRow({
    required this.job,
    required this.annotateEnabled,
    required this.canAnnotateNow,
    this.onOpenSetup,
    this.onOpenLocalCapabilityDownload,
    this.onRetry,
    this.onInstallSpeechPack,
    this.windowsSpeechRecognizerProbe,
    super.key,
  });

  final AttachmentAnnotationJob job;
  final bool annotateEnabled;
  final bool canAnnotateNow;
  final Future<void> Function()? onOpenSetup;
  final Future<void> Function()? onOpenLocalCapabilityDownload;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onInstallSpeechPack;
  final Future<bool> Function()? windowsSpeechRecognizerProbe;

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
  bool _checkingWindowsSpeechRecognizer = false;
  bool? _windowsSpeechRecognizerInstalled;

  @override
  void initState() {
    super.initState();
    _scheduleTickers();
    _refreshWindowsSpeechRecognizerState();
  }

  @override
  void didUpdateWidget(covariant AttachmentAnnotationJobStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.annotateEnabled != widget.annotateEnabled ||
        oldWidget.job.status != widget.job.status ||
        oldWidget.job.modelName != widget.job.modelName ||
        oldWidget.job.lastError != widget.job.lastError ||
        oldWidget.onInstallSpeechPack != widget.onInstallSpeechPack ||
        oldWidget.onOpenLocalCapabilityDownload !=
            widget.onOpenLocalCapabilityDownload ||
        oldWidget.job.createdAtMs != widget.job.createdAtMs ||
        oldWidget.job.updatedAtMs != widget.job.updatedAtMs) {
      _scheduleTickers();
      _refreshWindowsSpeechRecognizerState();
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

  bool _isLikelyWindowsNativeSttFailure(AttachmentAnnotationJob job) {
    final model = (job.modelName ?? '').trim().toLowerCase();
    if (model.contains('native_stt')) return true;
    final error = (job.lastError ?? '').trim().toLowerCase();
    if (error.contains('native_stt')) return true;
    if (isWindowsNativeSttSpeechPackMissingError(error)) return true;
    return false;
  }

  bool _isAudioLocalRuntimeMissing(AttachmentAnnotationJob job) {
    final error = (job.lastError ?? '').trim().toLowerCase();
    if (error.isEmpty) return false;
    if (!error.contains('audio_transcribe')) return false;
    return error.contains('audio_transcribe_local_runtime_model_missing') ||
        error.contains('audio_transcribe_local_runtime_unavailable') ||
        error.contains('runtime_missing');
  }

  bool _shouldCheckWindowsSpeechRecognizer() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
    if (!widget.annotateEnabled) return false;
    if (widget.job.status != 'failed') return false;
    if (widget.onInstallSpeechPack == null) return false;
    if (isWindowsNativeSttSpeechPackMissingError(widget.job.lastError)) {
      return false;
    }
    return _isLikelyWindowsNativeSttFailure(widget.job);
  }

  Future<void> _refreshWindowsSpeechRecognizerState() async {
    if (!_shouldCheckWindowsSpeechRecognizer()) {
      if (_windowsSpeechRecognizerInstalled != null &&
          mounted &&
          !_checkingWindowsSpeechRecognizer) {
        setState(() {
          _windowsSpeechRecognizerInstalled = null;
        });
      } else {
        _windowsSpeechRecognizerInstalled = null;
      }
      return;
    }
    if (_checkingWindowsSpeechRecognizer) return;
    _checkingWindowsSpeechRecognizer = true;
    try {
      final probe = widget.windowsSpeechRecognizerProbe ??
          () => hasWindowsSpeechRecognizerForLang(widget.job.lang);
      final installed = await probe();
      if (!mounted) return;
      setState(() {
        _windowsSpeechRecognizerInstalled = installed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _windowsSpeechRecognizerInstalled = null;
      });
    } finally {
      _checkingWindowsSpeechRecognizer = false;
    }
  }

  Future<void> _showLastErrorDialog(String errorText) async {
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(zh ? '转写错误详情' : 'Transcribe error details'),
          content: SingleChildScrollView(
            child: SelectableText(errorText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(() async {
                  await Clipboard.setData(ClipboardData(text: errorText));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(zh ? '错误详情已复制' : 'Error details copied'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }());
              },
              child: Text(zh ? '复制' : 'Copy'),
            ),
          ],
        );
      },
    );
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
    final zh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');

    final showMissingLocalRuntimeHint =
        isFailed && _isAudioLocalRuntimeMissing(job);

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

    final showSpeechPackInstallAction = isFailed &&
        widget.onInstallSpeechPack != null &&
        defaultTargetPlatform == TargetPlatform.windows &&
        (isWindowsNativeSttSpeechPackMissingError(job.lastError) ||
            (_isLikelyWindowsNativeSttFailure(job) &&
                _windowsSpeechRecognizerInstalled == false));

    final label = showMissingLocalRuntimeHint
        ? (zh
            ? '本地能力运行时缺失，需先下载后再转写。'
            : 'Local capability runtime is missing. Download it to transcribe.')
        : isPending
            ? (isSlow
                ? t.chat.semanticParseStatusSlow
                : t.chat.semanticParseStatusRunning)
            : (showSpeechPackInstallAction
                ? (zh
                    ? '缺少语音识别语言包，请先安装后再重试。'
                    : 'Speech recognition language pack is missing.')
                : t.chat.semanticParseStatusFailed);

    final leading = showMissingLocalRuntimeHint
        ? Icon(
            Icons.download_for_offline_outlined,
            size: 14,
            color: colorScheme.error,
          )
        : isPending
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
    final lastError = (job.lastError ?? '').trim();
    if (isFailed && lastError.isNotEmpty) {
      actions.add(
        TextButton(
          onPressed: () => unawaited(_showLastErrorDialog(lastError)),
          child: Text(zh ? '查看错误' : 'Details'),
        ),
      );
    }
    if (showSpeechPackInstallAction) {
      actions.add(
        TextButton(
          onPressed: () => unawaited(widget.onInstallSpeechPack!()),
          child: Text(zh ? '安装语音包' : 'Install speech pack'),
        ),
      );
    }
    if (showMissingLocalRuntimeHint &&
        widget.onOpenLocalCapabilityDownload != null) {
      actions.add(
        TextButton(
          onPressed: () => unawaited(widget.onOpenLocalCapabilityDownload!()),
          child: Text(zh ? '下载本地能力' : 'Download runtime'),
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
