import 'package:flutter/material.dart';

import 'settings_ui.dart';

@immutable
final class CloudAccountBenefit {
  const CloudAccountBenefit({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class CloudAccountBenefitsSection extends StatelessWidget {
  const CloudAccountBenefitsSection({
    required this.title,
    required this.benefits,
    super.key,
    this.surfaceKey,
  });

  final String title;
  final List<CloudAccountBenefit> benefits;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: title,
      surfaceKey: surfaceKey,
      children: [
        for (final benefit in benefits)
          SettingsRow(
            leading: Icon(benefit.icon),
            title: benefit.title,
            body: benefit.body,
          ),
      ],
    );
  }
}

class CloudAccountBenefitsList extends StatelessWidget {
  const CloudAccountBenefitsList({
    required this.title,
    required this.benefits,
    super.key,
  });

  final String title;
  final List<CloudAccountBenefit> benefits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final benefit in benefits)
          SettingsRow(
            leading: Icon(benefit.icon),
            title: benefit.title,
            body: benefit.body,
          ),
      ],
    );
  }
}
