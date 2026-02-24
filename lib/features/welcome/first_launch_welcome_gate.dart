import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'welcome_page.dart';

typedef WelcomePrefsProvider = Future<SharedPreferences> Function();

class FirstLaunchWelcomeGate extends StatefulWidget {
  const FirstLaunchWelcomeGate({
    super.key,
    required this.child,
    this.prefsProvider,
  });

  static const seenPrefsKey = 'welcome_guide_seen_v1';

  final Widget child;
  final WelcomePrefsProvider? prefsProvider;

  @override
  State<FirstLaunchWelcomeGate> createState() => _FirstLaunchWelcomeGateState();
}

class _FirstLaunchWelcomeGateState extends State<FirstLaunchWelcomeGate> {
  Future<bool>? _seenFuture;
  bool _dismissed = false;

  Future<bool> _loadSeen() async {
    final provider = widget.prefsProvider ?? SharedPreferences.getInstance;
    final prefs = await provider();
    return prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey) ?? false;
  }

  Future<void> _markSeenAndContinue() async {
    final provider = widget.prefsProvider ?? SharedPreferences.getInstance;
    final prefs = await provider();
    await prefs.setBool(FirstLaunchWelcomeGate.seenPrefsKey, true);
    if (!mounted) return;
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return widget.child;

    final seenFuture = _seenFuture ??= _loadSeen();
    return FutureBuilder<bool>(
      future: seenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) return widget.child;
        if (snapshot.data == true) return widget.child;
        return WelcomePage(
          onSkip: () => unawaited(_markSeenAndContinue()),
          onFinish: () => unawaited(_markSeenAndContinue()),
        );
      },
    );
  }
}
