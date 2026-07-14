use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PlatformId {
    Desktop,
    Android,
    Ios,
    Web,
    Server,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Capability(String);

impl Capability {
    pub fn new(name: impl Into<String>) -> Option<Self> {
        let name = name.into().trim().to_string();
        if name.is_empty() {
            return None;
        }
        Some(Self(name))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct CapabilitySet {
    names: Vec<String>,
}

impl CapabilitySet {
    pub fn from_names<I, S>(names: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let mut unique = BTreeSet::new();

        for name in names {
            if let Some(capability) = Capability::new(name) {
                unique.insert(capability.as_str().to_string());
            }
        }

        Self {
            names: unique.into_iter().collect(),
        }
    }

    pub fn android_mvp() -> Self {
        Self::from_names([
            "network.http",
            "filesystem.app_data",
            "secure_storage",
            "model.http_provider",
            "memory-provider",
            "provenance",
            "retention-policy",
            "reversible-history",
            "durable-actions",
            "approval-engine",
            "credential-vault",
            "mail-connector",
            "scheduler",
            "task-provider",
            "host-tools",
        ])
    }

    pub fn desktop_runtime() -> Self {
        Self::from_names([
            "network.http",
            "filesystem.workspace",
            "shell.process",
            "model.http_provider",
            "durable-actions",
            "approval-engine",
            "credential-vault",
            "memory-provider",
            "provenance",
            "retention-policy",
            "reversible-history",
            "mail-connector",
            "scheduler",
            "task-provider",
            "structured-content",
            "host-tools",
            "attachments",
        ])
    }

    pub fn server_runtime() -> Self {
        Self::from_names([
            "network.http",
            "filesystem.workspace",
            "shell.process",
            "model.http_provider",
            "durable-actions",
            "approval-engine",
            "credential-vault",
            "memory-provider",
            "provenance",
            "retention-policy",
            "reversible-history",
            "mail-connector",
            "scheduler",
            "task-provider",
            "structured-content",
            "host-tools",
            "attachments",
        ])
    }

    pub fn names(&self) -> &[String] {
        &self.names
    }

    pub fn contains_name(&self, name: &str) -> bool {
        self.names.iter().any(|item| item == name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn android_mvp_registers_only_mobile_safe_core_capabilities() {
        let capabilities = CapabilitySet::android_mvp();

        assert!(capabilities.contains_name("network.http"));
        assert!(capabilities.contains_name("filesystem.app_data"));
        assert!(capabilities.contains_name("secure_storage"));
        assert!(capabilities.contains_name("model.http_provider"));
        assert!(capabilities.contains_name("scheduler"));
        assert!(capabilities.contains_name("task-provider"));
        assert!(!capabilities.contains_name("shell.process"));
        assert!(!capabilities.contains_name("browser.headless"));
        assert!(!capabilities.contains_name("desktop.automation"));
        assert!(!capabilities.contains_name("filesystem.unrestricted"));
    }

    #[test]
    fn capability_names_are_trimmed_and_deduplicated() {
        let capabilities = CapabilitySet::from_names([
            " network.http ",
            "network.http",
            "",
            "filesystem.app_data",
        ]);

        assert_eq!(
            capabilities.names(),
            &["filesystem.app_data", "network.http"]
        );
    }

    #[test]
    fn desktop_runtime_registers_desktop_host_capabilities() {
        let capabilities = CapabilitySet::desktop_runtime();

        assert!(capabilities.contains_name("network.http"));
        assert!(capabilities.contains_name("filesystem.workspace"));
        assert!(capabilities.contains_name("shell.process"));
        assert!(capabilities.contains_name("model.http_provider"));
        assert!(capabilities.contains_name("task-provider"));
        assert!(capabilities.contains_name("attachments"));
        assert!(!capabilities.contains_name("secure_storage"));
    }

    #[test]
    fn server_runtime_registers_server_host_capabilities() {
        let capabilities = CapabilitySet::server_runtime();

        assert!(capabilities.contains_name("network.http"));
        assert!(capabilities.contains_name("filesystem.workspace"));
        assert!(capabilities.contains_name("shell.process"));
        assert!(capabilities.contains_name("model.http_provider"));
        assert!(capabilities.contains_name("task-provider"));
        assert!(capabilities.contains_name("attachments"));
        assert!(!capabilities.contains_name("secure_storage"));
    }
}
