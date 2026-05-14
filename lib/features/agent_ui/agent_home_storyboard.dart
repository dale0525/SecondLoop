import 'package:flutter/material.dart';

part 'agent_home_storyboard_desktop.dart';
part 'agent_home_storyboard_context_mobile.dart';
part 'agent_home_storyboard_notes_shared.dart';
part 'agent_review_storyboard.dart';
part 'agent_memory_preferences_storyboard.dart';
part 'agent_memory_people_storyboard.dart';
part 'agent_memory_projects_storyboard.dart';
part 'agent_memory_sources_storyboard.dart';
part 'agent_memory_sources_mobile_storyboard.dart';
part 'agent_memory_suggestions_storyboard.dart';
part 'agent_settings_account_storyboard.dart';
part 'agent_settings_connection_storyboard.dart';
part 'agent_settings_permissions_storyboard.dart';
part 'agent_settings_memory_storyboard.dart';
part 'agent_settings_activity_storyboard.dart';
part 'agent_files_media_storyboard.dart';
part 'agent_files_media_mobile_storyboard.dart';
part 'agent_daily_brief_storyboard.dart';
part 'agent_daily_brief_mobile_storyboard.dart';
part 'agent_calendar_email_storyboard.dart';
part 'agent_calendar_email_mobile_storyboard.dart';
part 'agent_research_storyboard.dart';
part 'agent_research_mobile_storyboard.dart';

final class AgentHomeStoryboard extends StatelessWidget {
  const AgentHomeStoryboard({super.key});

  static const canvasSize = Size(2048, 1365);
  static const canvasWidth = 2048.0;
  static const canvasHeight = 1365.0;
  static const blue = Color(0xFF0B5CF6);
  static const ink = Color(0xFF101936);
  static const muted = Color(0xFF63708A);
  static const line = Color(0xFFE1E7F0);
  static const panel = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F9FC);

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: ink,
        fontFamily: 'Inter',
        fontSize: 14,
        decoration: TextDecoration.none,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return const _MobileConversationCanvas();
          }
          return const ColoredBox(
            color: soft,
            child: FittedBox(
              alignment: Alignment.topLeft,
              fit: BoxFit.contain,
              child: SizedBox(
                width: AgentHomeStoryboard.canvasWidth,
                height: AgentHomeStoryboard.canvasHeight,
                child: _DesktopCanvas(),
              ),
            ),
          );
        },
      ),
    );
  }
}
