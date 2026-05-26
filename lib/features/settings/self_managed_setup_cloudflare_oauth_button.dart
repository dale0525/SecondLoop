part of 'self_managed_setup_page.dart';

class _CloudflareOAuthButton extends StatelessWidget {
  const _CloudflareOAuthButton({
    required this.state,
    required this.onOAuth,
  });

  final SelfManagedSetupState state;
  final VoidCallback onOAuth;

  @override
  Widget build(BuildContext context) {
    final ready = state.isCloudflareReady;
    return FilledButton.icon(
      key: const ValueKey('self_managed_cloudflare_oauth'),
      onPressed: onOAuth,
      icon: Icon(
        ready ? Icons.check_circle_outline_rounded : Icons.link_rounded,
        size: 20,
      ),
      label: Text(
        ready
            ? 'Cloudflare Connected - Reconnect'
            : 'Connect / Reconnect Cloudflare Account',
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: _SetupColors.secondary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: _SetupTextStyles.button,
      ),
    );
  }
}
