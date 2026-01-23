import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_usage_client.dart';
import '../../i18n/strings.g.dart';

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
    final percent = summary.usagePercent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usageRow(
          context.t.settings.cloudUsage.labels.usage,
          '$percent%',
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: percent / 100),
        const SizedBox(height: 8),
        _usageRow(
          context.t.settings.cloudUsage.labels.resetAt,
          _formatResetAt(context, summary.resetAtMs),
        ),
      ],
    );
  }
}

class CloudUsageCard extends StatefulWidget {
  const CloudUsageCard({super.key});

  @override
  State<CloudUsageCard> createState() => _CloudUsageCardState();
}

class _CloudUsageCardState extends State<CloudUsageCard> {
  final CloudUsageClient _client = CloudUsageClient();

  bool _busy = false;
  CloudUsageSummary? _summary;
  Object? _error;

  String? _uid;

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final scope = CloudAuthScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller == null) return;

    final baseUrl = scope?.gatewayConfig.baseUrl ?? '';
    if (baseUrl.trim().isEmpty) return;

    String? idToken;
    try {
      idToken = await controller.getIdToken();
    } catch (_) {
      idToken = null;
    }
    if (idToken == null || idToken.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final summary = await _client.fetchUsageSummary(
        cloudGatewayBaseUrl: baseUrl,
        idToken: idToken,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
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
      _summary = null;
      _error = null;
      if (uid != null) {
        unawaited(_refresh());
      }
    }

    final body = switch ((baseUrl.trim().isEmpty, uid == null)) {
      (true, _) =>
        Text(context.t.settings.cloudUsage.labels.gatewayNotConfigured),
      (false, true) =>
        Text(context.t.settings.cloudUsage.labels.signInRequired),
      (false, false) when _busy =>
        const Center(child: CircularProgressIndicator()),
      (false, false) when _error != null => Text(
          context.t.settings.cloudUsage.labels.loadFailed(error: '$_error'),
        ),
      (false, false) when _summary != null =>
        CloudUsageSummaryView(summary: _summary!),
      _ => const SizedBox.shrink(),
    };

    return Card(
      child: Padding(
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
      ),
    );
  }
}
