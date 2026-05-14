import 'package:flutter/material.dart';

import 'package:secondloop/app/theme.dart';
import 'package:secondloop/features/agent_ui/agent_home_storyboard.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/ui/sl_background.dart';

import '../test_i18n.dart';

final class AgentMvpGoldenApp extends StatelessWidget {
  const AgentMvpGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_mvp_golden_root'),
      child: AgentHomeStoryboard(),
    );
  }
}

final class AgentMvpReviewGoldenApp extends StatelessWidget {
  const AgentMvpReviewGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_review_golden_root'),
      child: AgentReviewStoryboard(),
    );
  }
}

final class AgentMvpMemoryPreferencesGoldenApp extends StatelessWidget {
  const AgentMvpMemoryPreferencesGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_memory_preferences_golden_root'),
      child: AgentMemoryPreferencesStoryboard(),
    );
  }
}

final class AgentMvpMemoryPeopleGoldenApp extends StatelessWidget {
  const AgentMvpMemoryPeopleGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_memory_people_golden_root'),
      child: AgentMemoryPeopleStoryboard(),
    );
  }
}

final class AgentMvpMemoryProjectsGoldenApp extends StatelessWidget {
  const AgentMvpMemoryProjectsGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_memory_projects_golden_root'),
      child: AgentMemoryProjectsStoryboard(),
    );
  }
}

final class AgentMvpMemorySourcesGoldenApp extends StatelessWidget {
  const AgentMvpMemorySourcesGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_memory_sources_golden_root'),
      child: AgentMemorySourcesStoryboard(),
    );
  }
}

final class AgentMvpMemorySuggestionsGoldenApp extends StatelessWidget {
  const AgentMvpMemorySuggestionsGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_memory_suggestions_golden_root'),
      child: AgentMemorySuggestionsStoryboard(),
    );
  }
}

final class AgentMvpSettingsAccountGoldenApp extends StatelessWidget {
  const AgentMvpSettingsAccountGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_settings_account_golden_root'),
      child: AgentSettingsAccountStoryboard(),
    );
  }
}

final class AgentMvpSettingsConnectionGoldenApp extends StatelessWidget {
  const AgentMvpSettingsConnectionGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_settings_connection_golden_root'),
      child: AgentSettingsConnectionStoryboard(),
    );
  }
}

final class AgentMvpSettingsPermissionsGoldenApp extends StatelessWidget {
  const AgentMvpSettingsPermissionsGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_settings_permissions_golden_root'),
      child: AgentSettingsPermissionsStoryboard(),
    );
  }
}

final class AgentMvpSettingsMemoryGoldenApp extends StatelessWidget {
  const AgentMvpSettingsMemoryGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_settings_memory_golden_root'),
      child: AgentSettingsMemoryStoryboard(),
    );
  }
}

final class AgentMvpSettingsActivityGoldenApp extends StatelessWidget {
  const AgentMvpSettingsActivityGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_settings_activity_golden_root'),
      child: AgentSettingsActivityStoryboard(),
    );
  }
}

final class AgentMvpFilesMediaGoldenApp extends StatelessWidget {
  const AgentMvpFilesMediaGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_files_media_golden_root'),
      child: AgentFilesMediaStoryboard(),
    );
  }
}

final class AgentMvpDailyBriefGoldenApp extends StatelessWidget {
  const AgentMvpDailyBriefGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_daily_brief_golden_root'),
      child: AgentDailyBriefStoryboard(),
    );
  }
}

final class AgentMvpCalendarEmailGoldenApp extends StatelessWidget {
  const AgentMvpCalendarEmailGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_calendar_email_golden_root'),
      child: AgentCalendarEmailStoryboard(),
    );
  }
}

final class AgentMvpResearchGoldenApp extends StatelessWidget {
  const AgentMvpResearchGoldenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgentMvpStoryboardGoldenApp(
      rootKey: ValueKey('agent_research_golden_root'),
      child: AgentResearchStoryboard(),
    );
  }
}

final class AgentMvpStoryboardGoldenApp extends StatelessWidget {
  const AgentMvpStoryboardGoldenApp({
    required this.rootKey,
    required this.child,
    super.key,
  });

  final Key rootKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return wrapWithI18n(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: agentMvpGoldenTheme(),
        home: RepaintBoundary(
          key: rootKey,
          child: SlBackground(child: child),
        ),
      ),
    );
  }
}

ThemeData agentMvpGoldenTheme() {
  final base = AppTheme.light(
    locale: LocaleSettings.currentLocale.flutterLocale,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Inter'),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      selectedLabelTextStyle:
          base.navigationRailTheme.selectedLabelTextStyle?.copyWith(
        fontFamily: 'Inter',
      ),
      unselectedLabelTextStyle:
          base.navigationRailTheme.unselectedLabelTextStyle?.copyWith(
        fontFamily: 'Inter',
      ),
    ),
  );
}
