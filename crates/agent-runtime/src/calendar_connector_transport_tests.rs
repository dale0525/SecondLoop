use super::*;
use crate::calendar::FakeCalendarConnector;

fn scope() -> CredentialScope {
    CredentialScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
    }
}

#[tokio::test]
async fn transport_publishes_valid_bounded_tools() {
    let transport =
        CalendarConnectorTransport::new(Arc::new(FakeCalendarConnector::default()), scope())
            .unwrap();
    let tools = transport.list_tools().await.unwrap();
    assert_eq!(tools.len(), CALENDAR_TOOL_NAMES.len());
    assert_eq!(
        tools
            .iter()
            .map(|tool| tool.name.as_str())
            .collect::<BTreeSet<_>>(),
        CALENDAR_TOOL_NAMES.into_iter().collect()
    );
    for tool in tools {
        tool.validate().unwrap();
    }
}

#[test]
fn descriptor_requires_external_approval_for_writes() {
    let descriptor = CalendarConnectorTransport::descriptor("Fake Calendar", true);
    assert_eq!(descriptor.id, CALENDAR_CONNECTOR_ID);
    assert_eq!(descriptor.approval_mode, ConnectorApprovalMode::Writes);
}
