import 'package:flutter/material.dart';

import '../../ui/sl_background.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';

enum SettingsStatusTone {
  neutral,
  positive,
  warning,
  danger,
}

enum SettingsInlineMessageTone {
  info,
  success,
  warning,
  error,
}

@immutable
final class SettingsAction {
  const SettingsAction({
    required this.label,
    required this.onPressed,
    this.key,
    this.icon,
    this.variant = SlButtonVariant.primary,
  });

  final Key? key;
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final SlButtonVariant variant;
}

class SettingsPageShell extends StatelessWidget {
  const SettingsPageShell({
    required this.children,
    super.key,
    this.title,
    this.appBar,
    this.scrollController,
    this.padding = const EdgeInsets.all(AgentDesignTokens.gapLg),
    this.maxWidth = AgentDesignTokens.maxContentWidth,
    this.bottomBar,
    this.useSingleChildScrollView = false,
  });

  final String? title;
  final PreferredSizeWidget? appBar;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final List<Widget> children;
  final Widget? bottomBar;
  final bool useSingleChildScrollView;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = SlTokens.of(context).background;
    final resolvedAppBar = appBar ??
        (title == null
            ? null
            : AppBar(
                title: Text(title!),
              ));

    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: useSingleChildScrollView
              ? SingleChildScrollView(
                  controller: scrollController,
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                )
              : ListView(
                  controller: scrollController,
                  padding: padding,
                  children: children,
                ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: resolvedAppBar,
      body: SlBackground(child: content),
      bottomNavigationBar: bottomBar,
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.children,
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.surfaceKey,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Key? surfaceKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null || subtitle != null || trailing != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AgentDesignTokens.gapXs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AgentDesignTokens.gapMd),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: trailing!,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AgentDesignTokens.gapSm),
        ],
        SlSurface(
          key: surfaceKey,
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i != 0) const Divider(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    super.key,
    this.body,
    this.leading,
    this.trailing,
    this.showChevron = false,
    this.dense = false,
    this.enabled = true,
    this.onTap,
  });

  final String title;
  final String? body;
  final Widget? leading;
  final Widget? trailing;
  final bool showChevron;
  final bool dense;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveOnTap = enabled ? onTap : null;

    return InkWell(
      onTap: effectiveOnTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AgentDesignTokens.gapLg,
          vertical: dense ? AgentDesignTokens.gapSm : AgentDesignTokens.gapMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
                child: leading!,
              ),
              const SizedBox(width: AgentDesignTokens.gapMd),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enabled ? scheme.onSurface : scheme.outline,
                    ),
                  ),
                  if (body != null && body!.trim().isNotEmpty) ...[
                    const SizedBox(height: AgentDesignTokens.gapXs),
                    Text(
                      body!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            enabled ? scheme.onSurfaceVariant : scheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AgentDesignTokens.gapMd),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: DefaultTextStyle.merge(
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    child: trailing!,
                  ),
                ),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: AgentDesignTokens.gapSm),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: enabled ? scheme.onSurfaceVariant : scheme.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.body,
    this.leading,
  });

  final String title;
  final String? body;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      body: body,
      leading: leading,
      enabled: onChanged != null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

class SettingsStatusBadge extends StatelessWidget {
  const SettingsStatusBadge({
    required this.label,
    super.key,
    this.badgeKey,
    this.tone = SettingsStatusTone.neutral,
  });

  final String label;
  final Key? badgeKey;
  final SettingsStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      SettingsStatusTone.neutral => (
          scheme.surfaceVariant,
          scheme.onSurfaceVariant,
        ),
      SettingsStatusTone.positive => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      SettingsStatusTone.warning => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      SettingsStatusTone.danger => (
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: AgentDesignTokens.chipPadding,
        child: Text(
          label,
          key: badgeKey,
          style: theme.textTheme.labelMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class SettingsActionBar extends StatelessWidget {
  const SettingsActionBar({
    required this.actions,
    super.key,
    this.alignment = WrapAlignment.start,
  });

  final List<SettingsAction> actions;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      spacing: AgentDesignTokens.gapMd,
      runSpacing: AgentDesignTokens.gapMd,
      children: [
        for (final action in actions)
          SlButton(
            buttonKey: action.key,
            onPressed: action.onPressed,
            icon: action.icon,
            variant: action.variant,
            child: Text(action.label),
          ),
      ],
    );
  }
}

class SettingsInlineMessage extends StatelessWidget {
  const SettingsInlineMessage({
    required this.message,
    super.key,
    this.tone = SettingsInlineMessageTone.info,
  });

  final String message;
  final SettingsInlineMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final (icon, background, foreground) = switch (tone) {
      SettingsInlineMessageTone.info => (
          Icons.info_outline_rounded,
          tokens.surface2,
          scheme.onSurfaceVariant,
        ),
      SettingsInlineMessageTone.success => (
          Icons.check_circle_outline_rounded,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      SettingsInlineMessageTone.warning => (
          Icons.warning_amber_rounded,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      SettingsInlineMessageTone.error => (
          Icons.error_outline_rounded,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: AgentDesignTokens.gapSm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
