import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../ui/sl_surface.dart';
import 'web_app_shell.dart';
import 'web_entry_intent.dart';

class WebPublicEntryScaffold extends StatelessWidget {
  const WebPublicEntryScaffold({
    required this.entryIntent,
    required this.signedIn,
    required this.child,
    super.key,
  });

  final WebEntryIntent entryIntent;
  final bool signedIn;
  final Widget child;

  ({String title, String body}) _copy(BuildContext context) {
    final intentCopy = context.t.app.web.entryIntent;
    switch (entryIntent) {
      case WebEntryIntent.subscribe:
        return (
          title: intentCopy.subscribe.title,
          body: signedIn
              ? intentCopy.subscribe.signedInBody
              : intentCopy.subscribe.signedOutBody,
        );
      case WebEntryIntent.manage:
        return (
          title: intentCopy.manage.title,
          body: signedIn
              ? intentCopy.manage.signedInBody
              : intentCopy.manage.signedOutBody,
        );
      case WebEntryIntent.open:
        return (
          title: intentCopy.open.title,
          body: signedIn
              ? intentCopy.open.signedInBody
              : intentCopy.open.signedOutBody,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.app.web.title)),
      body: WebAppPanelFrame(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SlSurface(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(copy.body),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
