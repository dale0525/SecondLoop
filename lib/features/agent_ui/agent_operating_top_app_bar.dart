part of 'agent_conversation_page.dart';

final class _OperatingTopAppBar extends StatelessWidget {
  const _OperatingTopAppBar({
    required this.pendingApprovals,
    required this.webResearchActive,
    required this.vaultUploadActive,
    required this.emailUnavailableActive,
    required this.purchasePaymentSafetyActive,
    required this.localComputerSafetyActive,
  });

  final int pendingApprovals;
  final bool webResearchActive;
  final bool vaultUploadActive;
  final bool emailUnavailableActive;
  final bool purchasePaymentSafetyActive;
  final bool localComputerSafetyActive;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AgentOperatingSystemTokens.background,
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showVaultUploadChip =
                    vaultUploadActive && constraints.maxWidth >= 430;
                final showEmailUnavailableChip =
                    emailUnavailableActive && constraints.maxWidth >= 560;
                final showPurchasePaymentSafetyChip =
                    purchasePaymentSafetyActive && constraints.maxWidth >= 560;
                final showLocalComputerSafetyChip =
                    localComputerSafetyActive && constraints.maxWidth >= 560;
                return Row(
                  children: [
                    if (!webResearchActive) ...[
                      ClipOval(
                        child: Image.asset(
                          'assets/icon/tray_icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        webResearchActive ? 'SecondLoop' : 'SecondLoop Agent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.headlineMd,
                      ),
                    ),
                    if (webResearchActive) ...[
                      const _OperatingPrimaryModeChip(),
                      const SizedBox(width: 6),
                      const _OperatingWebResearchModeChip(),
                    ] else ...[
                      const _OperatingModeChip(),
                      if (showVaultUploadChip) ...[
                        const SizedBox(width: 6),
                        const _OperatingVaultUploadModeChip(),
                      ],
                      if (showEmailUnavailableChip) ...[
                        const SizedBox(width: 6),
                        const _OperatingEmailUnavailableModeChip(),
                      ],
                      if (showPurchasePaymentSafetyChip) ...[
                        const SizedBox(width: 6),
                        const Flexible(
                          child: _OperatingPurchasePaymentSafetyModeChip(),
                        ),
                      ],
                      if (showLocalComputerSafetyChip) ...[
                        const SizedBox(width: 6),
                        const Flexible(
                          child: _OperatingLocalComputerSafetyModeChip(),
                        ),
                      ],
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Notifications',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final message = pendingApprovals == 0
                            ? 'No pending approvals'
                            : '$pendingApprovals pending approval(s)';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      },
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: AgentOperatingSystemTokens.onSurfaceVariant,
                      ),
                    ),
                    if (webResearchActive) ...[
                      const SizedBox(width: 4),
                      ClipOval(
                        child: Image.asset(
                          'assets/icon/tray_icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

final class _OperatingVaultUploadModeChip extends StatelessWidget {
  const _OperatingVaultUploadModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerHigh,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 13,
              color: AgentOperatingSystemTokens.secondary,
            ),
            SizedBox(width: 4),
            Text(
              'Vault Upload',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingPrimaryModeChip extends StatelessWidget {
  const _OperatingPrimaryModeChip();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudRuntimeConnection?>(
      future: _loadRuntimeModeChipConnection(),
      initialData: RuntimeConnectionStore.cachedConnection,
      builder: (context, snapshot) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              _operatingRuntimeModeLabel(snapshot.data),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _OperatingWebResearchModeChip extends StatelessWidget {
  const _OperatingWebResearchModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerHigh,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public_rounded,
              size: 13,
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
            SizedBox(width: 4),
            Text(
              'web-research',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingModeChip extends StatelessWidget {
  const _OperatingModeChip();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudRuntimeConnection?>(
      future: _loadRuntimeModeChipConnection(),
      initialData: RuntimeConnectionStore.cachedConnection,
      builder: (context, snapshot) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surfaceContainer,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _OperatingStatusDot(),
                const SizedBox(width: 6),
                Text(
                  _operatingRuntimeModeLabel(snapshot.data),
                  style: const TextStyle(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<CloudRuntimeConnection?> _loadRuntimeModeChipConnection() async {
  try {
    return await RuntimeConnectionStore().loadConnection();
  } catch (_) {
    return RuntimeConnectionStore.cachedConnection;
  }
}

String _operatingRuntimeModeLabel(CloudRuntimeConnection? connection) {
  return connection?.profile.runtimeMode == CloudRuntimeMode.selfManaged
      ? 'Self-managed'
      : 'Managed Pro';
}

final class _OperatingStatusDot extends StatelessWidget {
  const _OperatingStatusDot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 8,
      height: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.secondary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
