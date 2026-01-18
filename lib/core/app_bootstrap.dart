import 'package:flutter/material.dart';

import 'backend/app_backend.dart';
import '../i18n/strings.g.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({required this.child, super.key});

  final Widget child;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Future<void>? _initFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initFuture ??= AppBackendScope.of(context).init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                context.t.errors.initFailed(error: '${snapshot.error}'),
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}
