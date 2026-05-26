import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_helpers.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import 'agent_desktop_runtime_helpers.dart';
import 'agent_desktop_workbench_widgets.dart';
import 'agent_operating_system_tokens.dart';

part 'desktop_memory_workbench_models.dart';
part 'desktop_memory_workbench_candidate_tile.dart';

final class DesktopMemoryWorkbenchPage extends StatefulWidget {
  const DesktopMemoryWorkbenchPage({
    this.runtimeAgentStateRepository,
    this.approvalSender,
    this.vaultId,
    this.conversationId = 'loop_home',
    super.key,
  });

  final RuntimeAgentStateRepository? runtimeAgentStateRepository;
  final ChatRuntimeApprovalSender? approvalSender;
  final String? vaultId;
  final String conversationId;

  @override
  State<DesktopMemoryWorkbenchPage> createState() =>
      _DesktopMemoryWorkbenchPageState();
}

final class _DesktopMemoryWorkbenchPageState
    extends State<DesktopMemoryWorkbenchPage> {
  final TextEditingController _searchController = TextEditingController();
  RuntimeAgentState? _state;
  String? _selectedRecordId;
  String _filter = 'all';
  String? _error;
  bool _loading = false;
  bool _didLoad = false;
  String? _busyApprovalId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant DesktopMemoryWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtimeAgentStateRepository !=
            widget.runtimeAgentStateRepository ||
        oldWidget.vaultId != widget.vaultId ||
        oldWidget.conversationId != widget.conversationId) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  RuntimeAgentStateRepository? _repository() {
    if (widget.runtimeAgentStateRepository != null) {
      return widget.runtimeAgentStateRepository;
    }
    if (cachedSelfManagedRuntimeConnection() != null) {
      return SecretaryRuntimeAgentStateRepository();
    }
    final scope = CloudAuthScope.maybeOf(context);
    final vaultId = scope?.controller.uid?.trim() ?? '';
    if (scope == null || vaultId.isEmpty) return null;
    return SecretaryRuntimeAgentStateRepository.hostedManagedPro(
      apiBaseUrl: scope.gatewayConfig.baseUrl,
      hostedSessionTokenGetter: scope.controller.getIdToken,
    );
  }

  ChatRuntimeApprovalSender? _approvalSender() {
    if (widget.approvalSender != null) return widget.approvalSender;
    if (cachedSelfManagedRuntimeConnection() != null) {
      return SecretaryRuntimeConversationSender();
    }
    final scope = CloudAuthScope.maybeOf(context);
    final vaultId = scope?.controller.uid?.trim() ?? '';
    if (scope == null || vaultId.isEmpty) return null;
    return SecretaryRuntimeConversationSender.hostedManagedPro(
      apiBaseUrl: scope.gatewayConfig.baseUrl,
      hostedSessionTokenGetter: scope.controller.getIdToken,
    );
  }

  String _vaultId() {
    final explicit = widget.vaultId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final selfManagedVaultId =
        cachedSelfManagedRuntimeConnection()?.profile.vaultId.trim() ?? '';
    if (selfManagedVaultId.isNotEmpty) return selfManagedVaultId;
    return CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ?? '';
  }

  Future<void> _refresh() async {
    if (widget.runtimeAgentStateRepository == null &&
        (widget.vaultId?.trim().isEmpty ?? true)) {
      await loadRuntimeConnectionSafely();
      if (!mounted) return;
    }
    final repository = _repository();
    final vaultId = _vaultId();
    if (repository == null || vaultId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'tool_unavailable: runtime state is not configured';
        _state = RuntimeAgentState.empty(
          vaultId: vaultId,
          conversationId: widget.conversationId,
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await repository.fetchAgentState(
        vaultId: vaultId,
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      final records = _recordsFromState(state);
      setState(() {
        _state = state;
        _loading = false;
        _selectedRecordId = records.any((item) => item.id == _selectedRecordId)
            ? _selectedRecordId
            : records.firstOrNull?.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'tool_unavailable: $error';
        _state ??= RuntimeAgentState.empty(
          vaultId: vaultId,
          conversationId: widget.conversationId,
        );
      });
    }
  }

  Future<void> _decideCandidate(
    _MemoryCandidate candidate,
    String decision,
  ) async {
    final sender = _approvalSender();
    final vaultId = _vaultId();
    if (sender == null || vaultId.isEmpty) {
      showDesktopWorkbenchMessage(
        context,
        'tool_unavailable: runtime approval sender is not configured',
      );
      return;
    }
    setState(() => _busyApprovalId = candidate.id);
    try {
      await sender.submitApprovalDecision(
        vaultId: vaultId,
        approvalId: candidate.id,
        decision: decision,
      );
      if (!mounted) return;
      showDesktopWorkbenchMessage(
        context,
        decision == 'approve'
            ? 'approval submitted: memory candidate'
            : 'rejection submitted: memory candidate',
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showDesktopWorkbenchMessage(context, 'tool_unavailable: $error');
    } finally {
      if (mounted) setState(() => _busyApprovalId = null);
    }
  }

  void _showUnavailable(String action) {
    showDesktopWorkbenchMessage(
      context,
      '$action requires a runtime memory mutation endpoint. (approval_required)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final allRecords =
        state == null ? const <_MemoryRecord>[] : _recordsFromState(state);
    final candidates = state == null
        ? const <_MemoryCandidate>[]
        : _candidatesFromState(state);
    final records = _filterRecords(allRecords);
    final selected = _selectedRecordId == null
        ? records.firstOrNull
        : allRecords
            .where((record) => record.id == _selectedRecordId)
            .firstOrNull;

    return DesktopWorkbenchPageShell(
      key: const ValueKey('desktop_memory_workbench_page'),
      maxWidth: 1280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopWorkbenchHeader(
            title: 'Memory',
            subtitle: 'Manage personal context and agent instructions',
            actions: [
              OutlinedButton.icon(
                key: const ValueKey('desktop_memory_review_pending'),
                onPressed: candidates.isEmpty
                    ? null
                    : () => showDesktopWorkbenchMessage(
                          context,
                          '${candidates.length} pending memory candidates',
                        ),
                icon: const Icon(Icons.pending_actions_rounded, size: 18),
                label: Text('Review pending (${candidates.length})'),
              ),
              FilledButton(
                key: const ValueKey('desktop_memory_add_entry'),
                onPressed: () => _showUnavailable('Add Entry'),
                child: const Text('Add Entry'),
              ),
            ],
            bottom: _MemoryFilterBar(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
              controller: _searchController,
              onRefresh: _loading ? null : () => unawaited(_refresh()),
            ),
          ),
          const SizedBox(height: 24),
          if (_loading && state == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 900) {
                    return ListView(
                      children: [
                        SizedBox(
                          height: 420,
                          child: _MemoryRecordsPanel(
                            records: records,
                            selectedId: selected?.id,
                            onSelect: (record) =>
                                setState(() => _selectedRecordId = record.id),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 420,
                          child: _MemoryDetailsPanel(
                            record: selected,
                            contextSnapshotId:
                                state?.latestContextSnapshot?.id ?? '',
                            onArchive: () => _showUnavailable('Archive'),
                            onEdit: () => _showUnavailable('Edit Proposal'),
                            onRemove: () => _showUnavailable('Request Removal'),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _MemoryRecordsPanel(
                          records: records,
                          selectedId: selected?.id,
                          onSelect: (record) =>
                              setState(() => _selectedRecordId = record.id),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 5,
                        child: _MemoryDetailsPanel(
                          record: selected,
                          contextSnapshotId:
                              state?.latestContextSnapshot?.id ?? '',
                          onArchive: () => _showUnavailable('Archive'),
                          onEdit: () => _showUnavailable('Edit Proposal'),
                          onRemove: () => _showUnavailable('Request Removal'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            height: 210,
            child: _MemoryBottomArea(
              candidates: candidates,
              busyApprovalId: _busyApprovalId,
              error: _error,
              loading: _loading,
              onApprove: (candidate) =>
                  unawaited(_decideCandidate(candidate, 'approve')),
              onDismiss: (candidate) =>
                  unawaited(_decideCandidate(candidate, 'reject')),
            ),
          ),
        ],
      ),
    );
  }

  List<_MemoryRecord> _filterRecords(List<_MemoryRecord> records) {
    final query = _searchController.text.trim().toLowerCase();
    return records.where((record) {
      if (_filter != 'all' && record.status.toLowerCase() != _filter) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${record.title} ${record.detail} ${record.source}'
          .toLowerCase()
          .contains(query);
    }).toList(growable: false);
  }
}

final class _MemoryFilterBar extends StatelessWidget {
  const _MemoryFilterBar({
    required this.selected,
    required this.onSelected,
    required this.controller,
    required this.onRefresh,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final TextEditingController controller;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            for (final filter in const [
              'all',
              'active',
              'pending',
              'archived',
              'dismissed',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: InkWell(
                  onTap: () => onSelected(filter),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      desktopRuntimeTitleCase(filter),
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: selected == filter
                            ? AgentOperatingSystemTokens.onSurface
                            : AgentOperatingSystemTokens.onSurfaceVariant,
                        fontWeight: selected == filter
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            SizedBox(
              width: 240,
              height: 34,
              child: TextField(
                key: const ValueKey('desktop_memory_search'),
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Search Memory...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: IconButton(
                    tooltip: 'Refresh memory state',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AgentOperatingSystemTokens.surfaceContainerLow,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(
                      color: AgentOperatingSystemTokens.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MemoryRecordsPanel extends StatelessWidget {
  const _MemoryRecordsPanel({
    required this.records,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_MemoryRecord> records;
  final String? selectedId;
  final ValueChanged<_MemoryRecord> onSelect;

  @override
  Widget build(BuildContext context) {
    return DesktopWorkbenchPanel(
      title: 'Memory Records',
      trailing: const Icon(Icons.filter_list_rounded, size: 18),
      padding: EdgeInsets.zero,
      child: records.isEmpty
          ? const DesktopWorkbenchEmptyState(
              title: 'No memory records',
              message:
                  'Approved runtime memory will appear here after the agent creates auditable records.',
              icon: Icons.psychology_alt_outlined,
            )
          : Column(
              children: [
                const _MemoryTableHeader(),
                Expanded(
                  child: ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return _MemoryRecordRow(
                        key: ValueKey('desktop_memory_record_${record.id}'),
                        record: record,
                        selected: record.id == selectedId,
                        onTap: () => onSelect(record),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

final class _MemoryTableHeader extends StatelessWidget {
  const _MemoryTableHeader();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(flex: 4, child: _HeaderText('Record')),
            Expanded(flex: 2, child: _HeaderText('Status')),
            Expanded(flex: 2, child: _HeaderText('Source')),
            SizedBox(
                width: 72,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _HeaderText('Age'),
                )),
          ],
        ),
      ),
    );
  }
}

final class _HeaderText extends StatelessWidget {
  const _HeaderText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AgentOperatingSystemTokens.labelMd.copyWith(
        color: AgentOperatingSystemTokens.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

final class _MemoryRecordRow extends StatelessWidget {
  const _MemoryRecordRow({
    required this.record,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _MemoryRecord record;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = desktopStatusColor(record.status);
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x33DAE2FD)
              : AgentOperatingSystemTokens.surface,
          border: Border(
            left: BorderSide(
              color: selected
                  ? AgentOperatingSystemTokens.secondary
                  : Colors.transparent,
              width: 2,
            ),
            bottom: const BorderSide(
              color: AgentOperatingSystemTokens.outlineVariant,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: record.status == 'archived'
                        ? AgentOperatingSystemTokens.onSurfaceVariant
                        : AgentOperatingSystemTokens.onSurface,
                    decoration: record.status == 'archived'
                        ? TextDecoration.lineThrough
                        : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopWorkbenchBadge(
                    label: desktopRuntimeTitleCase(record.status),
                    background: AgentOperatingSystemTokens.surfaceContainerHigh,
                    foreground: statusColor,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  record.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  record.age,
                  textAlign: TextAlign.right,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _MemoryDetailsPanel extends StatelessWidget {
  const _MemoryDetailsPanel({
    required this.record,
    required this.contextSnapshotId,
    required this.onArchive,
    required this.onEdit,
    required this.onRemove,
  });

  final _MemoryRecord? record;
  final String contextSnapshotId;
  final VoidCallback onArchive;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final record = this.record;
    if (record == null) {
      return const DesktopWorkbenchPanel(
        title: 'Record Details',
        child: DesktopWorkbenchEmptyState(
          title: 'Select a memory',
          message:
              'Choose a runtime memory record to inspect its source and injection state.',
          icon: Icons.article_outlined,
        ),
      );
    }
    final contextId = record.contextId.isNotEmpty
        ? record.contextId
        : contextSnapshotId.isNotEmpty
            ? contextSnapshotId
            : 'not recorded';
    return DesktopWorkbenchPanel(
      title: 'Record Details',
      trailing: DesktopWorkbenchBadge(
        label: 'Confidence: ${record.confidenceLabel}',
        background: const Color(0xFFD3E4FE),
        foreground: const Color(0xFF38485D),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            record.id,
            style: AgentOperatingSystemTokens.bodySm.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Extracted Instruction'.toUpperCase(),
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AgentOperatingSystemTokens.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: const Border(
                left: BorderSide(
                  color: AgentOperatingSystemTokens.secondary,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                record.detail,
                style: AgentOperatingSystemTokens.bodyMd.copyWith(
                  color: AgentOperatingSystemTokens.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _MemoryMetaBlock(
                  label: 'Status',
                  value: 'Injected ($contextId)',
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MemoryMetaBlock(
                  label: 'Source Reference',
                  value: record.sourceRef,
                  icon: Icons.open_in_new_rounded,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Divider(color: AgentOperatingSystemTokens.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('desktop_memory_archive'),
                  onPressed: onArchive,
                  child: const Text('Archive'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('desktop_memory_edit_proposal'),
                  onPressed: onEdit,
                  child: const Text('Edit Proposal'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('desktop_memory_request_removal'),
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Request Removal'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF93000A),
              side: const BorderSide(color: Color(0x33BA1A1A)),
              backgroundColor: const Color(0xFFFFDAD6),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MemoryMetaBlock extends StatelessWidget {
  const _MemoryMetaBlock({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(icon, size: 16, color: AgentOperatingSystemTokens.secondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.bodySm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _MemoryBottomArea extends StatelessWidget {
  const _MemoryBottomArea({
    required this.candidates,
    required this.busyApprovalId,
    required this.error,
    required this.loading,
    required this.onApprove,
    required this.onDismiss,
  });

  final List<_MemoryCandidate> candidates;
  final String? busyApprovalId;
  final String? error;
  final bool loading;
  final ValueChanged<_MemoryCandidate> onApprove;
  final ValueChanged<_MemoryCandidate> onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AgentOperatingSystemTokens.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AgentOperatingSystemTokens.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pending Candidates (${candidates.length})',
                    style: AgentOperatingSystemTokens.labelMd.copyWith(
                      color: AgentOperatingSystemTokens.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: candidates.isEmpty
                        ? Text(
                            'No memory candidates waiting for approval.',
                            style: AgentOperatingSystemTokens.bodySm.copyWith(
                              color:
                                  AgentOperatingSystemTokens.onSurfaceVariant,
                            ),
                          )
                        : ListView.separated(
                            itemCount: candidates.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final candidate = candidates[index];
                              final busy = busyApprovalId == candidate.id;
                              return _MemoryCandidateTile(
                                candidate: candidate,
                                busy: busy,
                                onApprove: () => onApprove(candidate),
                                onDismiss: () => onDismiss(candidate),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  error == null
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  size: 16,
                  color: error == null
                      ? const Color(0xFF10B981)
                      : const Color(0xFFBA1A1A),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error ?? 'Runtime Connection Stable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgentOperatingSystemTokens.labelMd.copyWith(
                      color: AgentOperatingSystemTokens.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  loading ? 'Syncing...' : 'Last synced: Just now',
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
