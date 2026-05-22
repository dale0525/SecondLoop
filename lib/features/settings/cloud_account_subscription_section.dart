import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../ui/sl_button.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'cloud_account_benefits_section.dart';
import 'settings_ui.dart';

class CloudAccountSubscriptionSection extends StatelessWidget {
  const CloudAccountSubscriptionSection({
    required this.status,
    required this.canManageSubscription,
    required this.subBusy,
    required this.billingBusy,
    required this.statusLabel,
    required this.statusValue,
    required this.title,
    required this.refreshTooltip,
    required this.purchaseLabel,
    required this.manageLabel,
    required this.benefitsTitle,
    required this.benefits,
    required this.subscriptionRequiredBody,
    required this.onRefresh,
    required this.onSubscribe,
    required this.onManage,
    super.key,
    this.subscriptionErrorText,
    this.billingErrorText,
    this.onboarding = false,
  });

  final SubscriptionStatus status;
  final bool canManageSubscription;
  final bool subBusy;
  final bool billingBusy;
  final String statusLabel;
  final String statusValue;
  final String title;
  final String refreshTooltip;
  final String purchaseLabel;
  final String manageLabel;
  final String benefitsTitle;
  final List<CloudAccountBenefit> benefits;
  final String subscriptionRequiredBody;
  final VoidCallback onRefresh;
  final VoidCallback onSubscribe;
  final VoidCallback onManage;
  final String? subscriptionErrorText;
  final String? billingErrorText;
  final bool onboarding;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: title,
      surfaceKey: onboarding && status != SubscriptionStatus.entitled
          ? const ValueKey('cloud_subscription_required')
          : null,
      trailing: IconButton(
        key: const ValueKey('cloud_subscription_refresh'),
        onPressed: subBusy ? null : onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        tooltip: refreshTooltip,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(statusLabel),
                  const SizedBox(width: AgentDesignTokens.gapSm),
                  Text(
                    statusValue,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (subscriptionErrorText != null) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                SettingsInlineMessage(
                  message: subscriptionErrorText!,
                  tone: SettingsInlineMessageTone.error,
                ),
              ],
              if (billingErrorText != null) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                SettingsInlineMessage(
                  message: billingErrorText!,
                  tone: SettingsInlineMessageTone.error,
                ),
              ],
              if (status != SubscriptionStatus.entitled) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                if (onboarding)
                  Text(
                    subscriptionRequiredBody,
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  CloudAccountBenefitsList(
                    key: const ValueKey('cloud_subscription_value_props'),
                    title: benefitsTitle,
                    benefits: benefits,
                  ),
                const SizedBox(height: AgentDesignTokens.gapMd),
                SlButton(
                  buttonKey: const ValueKey('cloud_subscribe'),
                  onPressed: billingBusy ? null : onSubscribe,
                  child: Text(purchaseLabel),
                ),
              ] else if (canManageSubscription) ...[
                const SizedBox(height: AgentDesignTokens.gapMd),
                SlButton(
                  buttonKey: const ValueKey('cloud_manage_subscription'),
                  onPressed: billingBusy ? null : onManage,
                  variant: SlButtonVariant.outline,
                  child: Text(manageLabel),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
