use super::*;
use std::collections::HashMap;
use std::ffi::OsString;

fn workspace_mode(values: &[(&str, &str)]) -> anyhow::Result<WorkspaceProviderMode> {
    let values = values
        .iter()
        .map(|(name, value)| ((*name).to_string(), OsString::from(value)))
        .collect::<HashMap<_, _>>();
    workspace_provider_mode_from_lookup(|name| values.get(name).cloned())
}

#[test]
fn workspace_provider_selects_google_microsoft_or_fake_and_rejects_unknown_values() {
    assert_eq!(workspace_mode(&[]).unwrap(), WorkspaceProviderMode::Fake);
    assert_eq!(
        workspace_mode(&[("AGENTWEAVE_WORKSPACE_PROVIDER", "google")]).unwrap(),
        WorkspaceProviderMode::Google
    );
    assert_eq!(
        workspace_mode(&[("AGENTWEAVE_WORKSPACE_PROVIDER", "microsoft")]).unwrap(),
        WorkspaceProviderMode::Microsoft
    );
    assert!(workspace_mode(&[("AGENTWEAVE_WORKSPACE_PROVIDER", "unknown")]).is_err());
}
