import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_helpers.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import '../../i18n/strings.g.dart';
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
    final text = context.t.chat.operating.desktopWorkbench.memory;
    if (repository == null || vaultId.isEmpty) {
      setState(() {
        _loading = false;
        _error = text.messages.stateUnavailable;
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
      final records = _recordsFromState(state, _memoryWorkbenchCopy(context));
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
        _error = text.messages.runtimeUnavailable(error: '$error');
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
    final text = context.t.chat.operating.desktopWorkbench.memory;
    if (sender == null || vaultId.isEmpty) {
      showDesktopWorkbenchMessage(
        context,
        text.messages.approvalSenderUnavailable,
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
            ? text.messages.approvalSubmitted
            : text.messages.rejectionSubmitted,
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showDesktopWorkbenchMessage(
        context,
        text.messages.runtimeUnavailable(error: '$error'),
      );
    } finally {
      if (mounted) setState(() => _busyApprovalId = null);
    }
  }

  void _showUnavailable(String action) {
    final text = context.t.chat.operating.desktopWorkbench.memory;
    showDesktopWorkbenchMessage(
      context,
      text.messages.mutationUnavailable(action: action),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.t.chat.operating.desktopWorkbench.memory;
    final copy = _memoryWorkbenchCopy(context);
    final state = _state;
    final allRecords = state == null
        ? const <_MemoryRecord>[]
        : _recordsFromState(state, copy);
    final candidates = state == null
        ? const <_MemoryCandidate>[]
        : _candidatesFromState(state, copy);
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
            title: text.title,
            subtitle: text.subtitle,
            actions: [
              OutlinedButton.icon(
                key: const ValueKey('desktop_memory_review_pending'),
                onPressed: candidates.isEmpty
                    ? null
                    : () => showDesktopWorkbenchMessage(
                          context,
                          text.pendingCandidatesMessage(
                            count: candidates.length,
                          ),
                        ),
                icon: const Icon(Icons.pending_actions_rounded, size: 18),
                label: Text(text.reviewPending(count: candidates.length)),
              ),
              FilledButton(
                key: const ValueKey('desktop_memory_add_entry'),
                onPressed: () => _showUnavailable(text.addEntry),
                child: Text(text.addEntry),
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
                            onArchive: () => _showUnavailable(
                                context.t.common.actions.archive),
                            onEdit: () => _showUnavailable(text.editProposal),
                            onRemove: () =>
                                _showUnavailable(text.requestRemoval),
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
                          onArchive: () => _showUnavailable(
                              context.t.common.actions.archive),
                          onEdit: () => _showUnavailable(text.editProposal),
                          onRemove: () => _showUnavailable(text.requestRemoval),
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

_MemoryWorkbenchCopy _memoryWorkbenchCopy(BuildContext context) {
  final text = context.t.chat.operating.desktopWorkbench.memory;
  return _MemoryWorkbenchCopy(
    untitledMemory: text.untitledMemory,
    defaultSource: text.defaultSource,
    notReported: text.notReported,
    candidateFallback: text.candidateFallback,
  );
}

String _memoryFilterLabel(BuildContext context, String filter) {
  final filters = context.t.chat.operating.desktopWorkbench.memory.filters;
  return switch (filter) {
    'all' => filters.all,
    'active' => filters.active,
    'pending' => filters.pending,
    'archived' => filters.archived,
    'dismissed' => filters.dismissed,
    _ => desktopRuntimeTitleCase(filter),
  };
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
    final colors = AgentOperatingSystemTokens.of(context);
    final text = context.t.chat.operating.desktopWorkbench.memory;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
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
                      _memoryFilterLabel(context, filter),
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: selected == filter
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
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
                  hintText: text.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: IconButton(
                    tooltip: text.refreshTooltip,
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.outlineVariant),
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
    final text = context.t.chat.operating.desktopWorkbench.memory;
    return DesktopWorkbenchPanel(
      title: text.recordsTitle,
      trailing: const Icon(Icons.filter_list_rounded, size: 18),
      padding: EdgeInsets.zero,
      child: records.isEmpty
          ? DesktopWorkbenchEmptyState(
              title: text.emptyRecordsTitle,
              message: text.emptyRecordsMessage,
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
    final colors = AgentOperatingSystemTokens.of(context);
    final t = context.t.chat.operating.desktopWorkbench.memory;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(flex: 4, child: _HeaderText(t.record)),
            Expanded(flex: 2, child: _HeaderText(t.status)),
            Expanded(flex: 2, child: _HeaderText(t.source)),
            SizedBox(
                width: 72,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _HeaderText(t.age),
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
    final colors = AgentOperatingSystemTokens.of(context);
    return Text(
      label.toUpperCase(),
      style: AgentOperatingSystemTokens.labelMd.copyWith(
        color: colors.onSurfaceVariant,
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
    final colors = AgentOperatingSystemTokens.of(context);
    final statusColor = desktopStatusColor(record.status);
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colors.secondaryContainer.withOpacity(0.28)
              : colors.surface,
          border: Border(
            left: BorderSide(
              color: selected ? colors.secondary : Colors.transparent,
              width: 2,
            ),
            bottom: BorderSide(color: colors.outlineVariant),
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
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
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
                    background: colors.surfaceContainerHigh,
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
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  record.age,
                  textAlign: TextAlign.right,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: colors.onSurfaceVariant,
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
    final colors = AgentOperatingSystemTokens.of(context);
    final text = context.t.chat.operating.desktopWorkbench.memory;
    final record = this.record;
    if (record == null) {
      return DesktopWorkbenchPanel(
        title: text.detailsTitle,
        child: DesktopWorkbenchEmptyState(
          title: text.selectTitle,
          message: text.selectMessage,
          icon: Icons.article_outlined,
        ),
      );
    }
    final contextId = record.contextId.isNotEmpty
        ? record.contextId
        : contextSnapshotId.isNotEmpty
            ? contextSnapshotId
            : text.notRecorded;
    return DesktopWorkbenchPanel(
      title: text.detailsTitle,
      trailing: DesktopWorkbenchBadge(
        label: text.confidence(value: record.confidenceLabel),
        background: const Color(0xFFD3E4FE),
        foreground: const Color(0xFF38485D),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            record.id,
            style: AgentOperatingSystemTokens.bodySm.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context
                .t.chat.operating.desktopWorkbench.memory.extractedInstruction
                .toUpperCase(),
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(
                  color: colors.secondary,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                record.detail,
                style: AgentOperatingSystemTokens.bodyMd.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _MemoryMetaBlock(
                  label: text.statusMeta,
                  value: text.injected(contextId: contextId),
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MemoryMetaBlock(
                  label: text.sourceReference,
                  value: record.sourceRef,
                  icon: Icons.open_in_new_rounded,
                ),
              ),
            ],
          ),
          const Spacer(),
          Divider(color: colors.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('desktop_memory_archive'),
                  onPressed: onArchive,
                  child: Text(context.t.common.actions.archive),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('desktop_memory_edit_proposal'),
                  onPressed: onEdit,
                  child: Text(text.editProposal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('desktop_memory_request_removal'),
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(text.requestRemoval),
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
    final colors = AgentOperatingSystemTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(icon, size: 16, color: colors.secondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: colors.onSurface,
                ),
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
    final colors = AgentOperatingSystemTokens.of(context);
    final text = context.t.chat.operating.desktopWorkbench.memory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text.pendingCandidates(count: candidates.length),
                    style: AgentOperatingSystemTokens.labelMd.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: candidates.isEmpty
                        ? Text(
                            text.emptyCandidates,
                            style: AgentOperatingSystemTokens.bodySm.copyWith(
                              color: colors.onSurfaceVariant,
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
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
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
                    error ?? text.runtimeConnectionStable,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgentOperatingSystemTokens.labelMd.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  loading ? text.syncing : text.lastSyncedJustNow,
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: colors.onSurfaceVariant,
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
