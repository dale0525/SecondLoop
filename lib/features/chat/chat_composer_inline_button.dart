import 'package:flutter/material.dart';

class ChatComposerInlineButton extends StatelessWidget {
  const ChatComposerInlineButton({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    this.iconOnly = false,
    this.minButtonWidth = 44,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool iconOnly;
  final double minButtonWidth;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isEnabled = onPressed != null;

    final effectiveBackground =
        isEnabled ? backgroundColor : backgroundColor.withOpacity(0.52);
    final effectiveForeground =
        isEnabled ? foregroundColor : foregroundColor.withOpacity(0.62);

    final borderRadius = BorderRadius.circular(999);
    final currentBorderColor = borderColor;
    final borderSide = currentBorderColor == null
        ? BorderSide.none
        : BorderSide(color: currentBorderColor);

    return Semantics(
      key: buttonKey,
      button: true,
      label: label,
      child: Material(
        color: effectiveBackground,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: borderSide,
        ),
        child: InkWell(
          onTap: onPressed,
          canRequestFocus: false,
          borderRadius: borderRadius,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 44,
              minWidth: minButtonWidth,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? 10 : 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: effectiveForeground),
                  if (!iconOnly) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: textTheme.labelLarge?.copyWith(
                        color: effectiveForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
