enum AgentSettingsTab {
  account('account'),
  connection('connection'),
  permissions('permissions'),
  memory('memory'),
  activity('activity');

  const AgentSettingsTab(this.id);

  final String id;
}
