import 'package:flutter/widgets.dart';

import '../conversation_cards/approval_preview_card.dart';
import '../conversation_cards/calendar_email_card.dart';
import '../conversation_cards/daily_brief_card.dart';
import '../conversation_cards/media_summary_card.dart';
import '../conversation_cards/research_models.dart';
import '../conversation_context/conversation_context_rail.dart';

final class AgentUiAcceptanceController extends ChangeNotifier {
  AgentUiAcceptanceController({
    this.redactedCloudAccountEmail,
  });

  final String? redactedCloudAccountEmail;

  ApprovalPreviewChange? approvalChange;
  MediaSummaryData? mediaSummary;
  DailyBriefData? dailyBrief;
  CalendarEmailData? calendarEmail;
  ResearchBudgetEstimate? researchEstimate;
  ResearchResult? researchResult;
  ConversationContextSnapshot? contextSnapshot;

  bool get hasConversationCards =>
      approvalChange != null ||
      mediaSummary != null ||
      dailyBrief != null ||
      calendarEmail != null ||
      researchEstimate != null ||
      researchResult != null;

  void clear() {
    approvalChange = null;
    mediaSummary = null;
    dailyBrief = null;
    calendarEmail = null;
    researchEstimate = null;
    researchResult = null;
    contextSnapshot = null;
    notifyListeners();
  }

  void simulateTaskChangeProposal() {
    approvalChange = ApprovalPreviewChange.demo();
    contextSnapshot ??= ConversationContextSnapshot.demo();
    notifyListeners();
  }

  void simulateMediaUnderstanding() {
    mediaSummary = MediaSummaryData.demo();
    contextSnapshot ??= ConversationContextSnapshot.demo();
    notifyListeners();
  }

  void simulateDailyBrief() {
    dailyBrief = DailyBriefData.demo();
    contextSnapshot ??= ConversationContextSnapshot.demo();
    notifyListeners();
  }

  void simulateCalendarEmail() {
    calendarEmail = CalendarEmailData.demo();
    contextSnapshot ??= ConversationContextSnapshot.demo();
    notifyListeners();
  }

  void simulateResearchRun() {
    researchEstimate = ResearchBudgetEstimate.demo();
    researchResult = ResearchResult.demo();
    contextSnapshot ??= ConversationContextSnapshot.demo();
    notifyListeners();
  }

  void simulateManagedProConversationWorkspace() {
    approvalChange = ApprovalPreviewChange.demo();
    mediaSummary = MediaSummaryData.demo();
    dailyBrief = DailyBriefData.demo();
    calendarEmail = CalendarEmailData.demo();
    researchEstimate = ResearchBudgetEstimate.demo();
    researchResult = ResearchResult.demo();
    contextSnapshot = ConversationContextSnapshot.demo();
    notifyListeners();
  }

  void resolveTaskChangeProposal() {
    approvalChange = null;
    notifyListeners();
  }
}

final class AgentUiAcceptanceScope
    extends InheritedNotifier<AgentUiAcceptanceController> {
  const AgentUiAcceptanceScope({
    required AgentUiAcceptanceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AgentUiAcceptanceController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AgentUiAcceptanceScope>()
        ?.notifier;
  }
}
