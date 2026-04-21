import '../actions/calendar/event_deeplink.dart';
import '../actions/todo/todo_deeplink.dart';
import '../attachments/attachment_deeplink.dart';
import 'message_deeplink.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ChatMarkdownInAppLinkHandler = Future<bool> Function(String href);
typedef ChatMarkdownUnsupportedLinkHandler = Future<void> Function(String href);

bool canOpenChatMarkdownHref(String? href) {
  final target = href?.trim();
  if (target == null || target.isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(target);
  if (uri == null) {
    return false;
  }
  if (uri.scheme.toLowerCase() != 'secondloop') {
    return true;
  }

  return parseTodoDeepLink(target) != null ||
      parseEventDeepLink(target) != null ||
      parseAttachmentDeepLink(target) != null ||
      parseMessageDeepLink(target) != null;
}

Future<void> handleChatMarkdownTapLink(
  String? href, {
  required ChatMarkdownInAppLinkHandler handleInApp,
  ChatMarkdownUnsupportedLinkHandler? handleUnsupportedSecondLoopLink,
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
  if (uri.scheme.toLowerCase() == 'secondloop') {
    await handleUnsupportedSecondLoopLink?.call(target);
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
