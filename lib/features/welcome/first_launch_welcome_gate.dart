import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'welcome_page.dart';

class FirstLaunchWelcomeGate extends StatefulWidget {
  const FirstLaunchWelcomeGate({
    super.key,
    required this.child,
  });

  static const seenPrefsKey = 'welcome_guide_seen_v1';

  final Widget child;

  @override
  State<FirstLaunchWelcomeGate> createState() => _FirstLaunchWelcomeGateState();
}

class _FirstLaunchWelcomeGateState extends State<FirstLaunchWelcomeGate> {
  bool? _seen;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeen());
  }

  Future<void> _loadSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _seen = prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey) ?? false;
    });
  }

  Future<void> _completeWelcome() async {
    if (_saving) return;
    _saving = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FirstLaunchWelcomeGate.seenPrefsKey, true);
    if (!mounted) return;
    setState(() => _seen = true);
    _saving = false;
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (seen) return widget.child;

    return WelcomePage(
      onSkipForNow: () => unawaited(_completeWelcome()),
      onFinishSetup: () => unawaited(_completeWelcome()),
    );
  }
}
