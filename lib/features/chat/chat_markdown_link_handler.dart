import 'package:url_launcher/url_launcher.dart';

typedef ChatMarkdownInAppLinkHandler = Future<bool> Function(String href);

Future<void> handleChatMarkdownTapLink(
  String? href, {
  required ChatMarkdownInAppLinkHandler handleInApp,
}) async {
  final target = href?.trim();
  if (target == null || target.isEmpty) {
    return;
  }

  final handledInApp = await handleInApp(target);
  if (handledInApp) {
    return;
  }

  final uri = Uri.tryParse(target);
  if (uri == null) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
