import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_access.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_usage_client.dart';
import '../../core/ai/ai_routing.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';

String _formatResetAt(BuildContext context, int? resetAtMs) {
  if (resetAtMs == null) return '—';
  final dt =
      DateTime.fromMillisecondsSinceEpoch(resetAtMs, isUtc: true).toLocal();
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatShortDate(dt);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dt));
  return '$date $time';
}

Widget _usageRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class CloudUsageSummaryView extends StatelessWidget {
  const CloudUsageSummaryView({super.key, required this.summary});

  final CloudUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final askAiPercent = summary.askAiUsagePercent.clamp(0, 100);
    final embeddingsPercent = summary.embeddingsUsagePercent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usageRow(
          context.t.settings.cloudUsage.labels.askAiUsage,
          '$askAiPercent%',
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: askAiPercent / 100),
        const SizedBox(height: 12),
        _usageRow(
          context.t.settings.cloudUsage.labels.embeddingsUsage,
          '$embeddingsPercent%',
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: embeddingsPercent / 100),
        const SizedBox(height: 12),
        _usageRow(
          context.t.settings.cloudUsage.labels.resetAt,
          _formatResetAt(context, summary.resetAtMs),
        ),
      ],
    );
  }
}

class CloudUsageCard extends StatefulWidget {
  const CloudUsageCard({super.key, this.client});

  final CloudUsageClient? client;

  @override
  State<CloudUsageCard> createState() => _CloudUsageCardState();
}

class _CloudUsageCardState extends State<CloudUsageCard> {
  late CloudUsageClient _client;
  var _ownsClient = false;
  int _activeRefreshes = 0;
  int _refreshEpoch = 0;

  bool get _busy => _activeRefreshes > 0;
  CloudUsageSummary? _summary;
  Object? _error;

  String? _uid;

  @override
  void initState() {
    super.initState();
    _replaceClient(widget.client);
  }

  @override
  void didUpdateWidget(covariant CloudUsageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _disposeOwnedClient();
      _replaceClient(widget.client);
      _resetLoadedState(invalidateRefreshes: true);
      if (_uid != null) {
        unawaited(_refresh());
      }
    }
  }

  void _replaceClient(CloudUsageClient? client) {
    _client = client ?? CloudUsageClient();
    _ownsClient = client == null;
  }

  void _disposeOwnedClient() {
    if (_ownsClient) {
      _client.dispose();
    }
  }

  void _resetLoadedState({bool invalidateRefreshes = false}) {
    if (invalidateRefreshes) {
      _refreshEpoch += 1;
    }
    _summary = null;
    _error = null;
  }

  void _markRefreshStarted() {
    if (!mounted) {
      _activeRefreshes += 1;
      return;
    }
    setState(() => _activeRefreshes += 1);
  }

  void _markRefreshFinished() {
    if (_activeRefreshes <= 0) return;
    if (!mounted) {
      _activeRefreshes -= 1;
      return;
    }
    setState(() => _activeRefreshes -= 1);
  }

  @override
  void dispose() {
    _disposeOwnedClient();
    super.dispose();
  }

  String _formatUsageError(BuildContext context, Object error) {
    final status = parseHttpStatusFromError(error);
    final code = parseCloudErrorCodeFromError(error);
    if (status == 402 || code == 'payment_required') {
      return context.t.settings.cloudUsage.labels.paymentRequired;
    }
    if (status == 403 && code == 'email_not_verified') {
      return context.t.chat.cloudGateway.emailNotVerified;
    }
    return '$error';
  }

  Future<void> _refresh() async {
    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller == null) return;

    final baseUrl = scope?.gatewayConfig.baseUrl ?? '';
    if (baseUrl.trim().isEmpty) return;

    String? idToken;
    try {
      idToken = await readCloudAuthIdToken(
        controller,
        mode: CloudAuthAccessMode.interactive,
      );
    } catch (_) {
      idToken = null;
    }
    if (idToken == null || idToken.trim().isEmpty) return;

    final refreshEpoch = ++_refreshEpoch;
    final requestClient = _client;
    _markRefreshStarted();
    try {
      final summary = await requestClient.fetchUsageSummary(
        cloudGatewayBaseUrl: baseUrl,
        idToken: idToken,
      );
      final shouldApply = mounted &&
          refreshEpoch == _refreshEpoch &&
          identical(requestClient, _client);
      if (shouldApply) {
        setState(() {
          _summary = summary;
          _error = null;
        });
      }
    } catch (e) {
      final shouldApply = mounted &&
          refreshEpoch == _refreshEpoch &&
          identical(requestClient, _client);
      if (shouldApply) {
        setState(() => _error = e);
      }
    } finally {
      _markRefreshFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = CloudAuthScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final baseUrl = scope.gatewayConfig.baseUrl;
    final uid = scope.controller.uid;

    if (uid != _uid) {
      _uid = uid;
      _resetLoadedState(invalidateRefreshes: true);
      if (uid != null) {
        unawaited(_refresh());
      }
    }

    final body = switch ((baseUrl.trim().isEmpty, uid == null)) {
      (true, _) =>
        Text(context.t.settings.cloudUsage.labels.gatewayNotConfigured),
      (false, true) =>
        Text(context.t.settings.cloudUsage.labels.signInRequired),
      (false, false) when _error != null => Text(
          context.t.settings.cloudUsage.labels
              .loadFailed(error: _formatUsageError(context, _error!)),
        ),
      (false, false) when _summary != null =>
        CloudUsageSummaryView(summary: _summary!),
      (false, false) when _busy =>
        const Center(child: CircularProgressIndicator()),
      _ => const SizedBox.shrink(),
    };

    return SlSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.settings.cloudUsage.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t.settings.cloudUsage.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('cloud_usage_refresh'),
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: context.t.settings.cloudUsage.actions.refresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}
