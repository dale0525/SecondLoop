import 'package:flutter/material.dart';

import '../../ui/sl_button.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'settings_ui.dart';

class CloudAccountIdentitySection extends StatelessWidget {
  const CloudAccountIdentitySection({
    required this.signedInLabel,
    required this.signOutLabel,
    required this.busy,
    required this.onSignOut,
    super.key,
  });

  final String signedInLabel;
  final String signOutLabel;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                signedInLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AgentDesignTokens.gapMd),
              SlButton(
                onPressed: busy ? null : onSignOut,
                variant: SlButtonVariant.outline,
                child: Text(signOutLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
