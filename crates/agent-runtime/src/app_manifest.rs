use crate::app_access_manifest::reject_secret_like_fields;
pub use crate::app_access_manifest::{
    AgentAppEntitlementConfiguration, AgentAppEntitlementMode, AgentAppIdentityConfiguration,
    AgentAppIdentityMode, AgentAppModelAccess, AgentAppModelAuthentication,
    AgentAppModelConfigurationPolicy, AgentAppModelProfile, AgentAppProviderBinding,
};
use crate::platform::PlatformId;
use anyhow::Context;
use semver::{Version, VersionReq};
use serde::{Deserialize, Deserializer, Serialize, Serializer, de};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::io::ErrorKind;
use std::path::{Component, Path, PathBuf};

pub const AGENT_APP_MANIFEST_SCHEMA_VERSION: u32 = 2;
pub const AGENT_APP_MANIFEST_MIN_SCHEMA_VERSION: u32 = 1;
pub const AGENT_APP_MANIFEST_FILE: &str = "agent-app.json";
const MAX_REVERSE_DNS_ID_LENGTH: usize = 128;
const MAX_IDENTIFIER_LENGTH: usize = 128;
const MAX_DISPLAY_NAME_LENGTH: usize = 128;
const MAX_SHORT_TEXT_LENGTH: usize = 512;
const MAX_APP_LOCALES: usize = 32;
const MAX_LOCALE_CATALOG_BYTES: usize = 1024 * 1024;
const MAX_LOCALE_MESSAGE_BYTES: usize = 4096;
const VS_CODE_BUILTIN_THEME_IDS: &[&str] = &[
    "vscode.abyss",
    "vscode.dark-2026",
    "vscode.dark-modern",
    "vscode.dark-plus",
    "vscode.high-contrast-dark",
    "vscode.high-contrast-light",
    "vscode.kimbie-dark",
    "vscode.light-2026",
    "vscode.light-modern",
    "vscode.light-plus",
    "vscode.monokai",
    "vscode.monokai-dimmed",
    "vscode.quiet-light",
    "vscode.red",
    "vscode.solarized-dark",
    "vscode.solarized-light",
    "vscode.tomorrow-night-blue",
    "vscode.visual-studio-dark",
    "vscode.visual-studio-light",
];

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct AgentAppId(String);

impl AgentAppId {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        validate_reverse_dns_id(value, "app id")?;
        Ok(Self(value.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl<'de> Deserialize<'de> for AgentAppId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct AgentAppPackageId(String);

impl AgentAppPackageId {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        validate_reverse_dns_id(value, "app package id")?;
        Ok(Self(value.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl<'de> Deserialize<'de> for AgentAppPackageId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct AgentAppIdentifier(String);

impl AgentAppIdentifier {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        let valid = !value.is_empty()
            && value.len() <= MAX_IDENTIFIER_LENGTH
            && value.split('.').all(is_valid_identifier_segment);
        anyhow::ensure!(valid, "invalid app manifest identifier: {value}");
        Ok(Self(value.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl<'de> Deserialize<'de> for AgentAppIdentifier {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct AgentAppLocaleId(String);

impl AgentAppLocaleId {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        validate_locale_id(value)?;
        Ok(Self(value.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl<'de> Deserialize<'de> for AgentAppLocaleId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct RelativeResourcePath(String);

impl RelativeResourcePath {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        validate_relative_resource_path(value)?;
        Ok(Self(value.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn as_path(&self) -> &Path {
        Path::new(&self.0)
    }
}

impl Serialize for RelativeResourcePath {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&self.0)
    }
}

impl<'de> Deserialize<'de> for RelativeResourcePath {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(de::Error::custom)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum AgentAppPlatform {
    Desktop,
    Android,
    Ios,
    Web,
    Server,
}

impl AgentAppPlatform {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "desktop" | "macos" | "windows" | "linux" => Ok(Self::Desktop),
            "android" => Ok(Self::Android),
            "ios" => Ok(Self::Ios),
            "web" => Ok(Self::Web),
            "server" => Ok(Self::Server),
            _ => anyhow::bail!("unsupported app platform: {value}"),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Desktop => "desktop",
            Self::Android => "android",
            Self::Ios => "ios",
            Self::Web => "web",
            Self::Server => "server",
        }
    }
}

impl From<PlatformId> for AgentAppPlatform {
    fn from(platform: PlatformId) -> Self {
        match platform {
            PlatformId::Desktop => Self::Desktop,
            PlatformId::Android => Self::Android,
            PlatformId::Ios => Self::Ios,
            PlatformId::Web => Self::Web,
            PlatformId::Server => Self::Server,
        }
    }
}

impl Serialize for AgentAppPlatform {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for AgentAppPlatform {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppPackage {
    pub id: AgentAppPackageId,
    pub version: Version,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppPackageRequirement {
    pub id: AgentAppPackageId,
    pub version: VersionReq,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppRequirements {
    #[serde(default)]
    pub packages: Vec<AgentAppPackageRequirement>,
    #[serde(default)]
    pub capabilities: BTreeSet<AgentAppIdentifier>,
    #[serde(default)]
    pub runtime_tools: BTreeSet<AgentAppIdentifier>,
    #[serde(default)]
    pub connectors: BTreeSet<AgentAppIdentifier>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppCompatibility {
    pub runtime: Option<VersionReq>,
    #[serde(default)]
    pub platforms: BTreeSet<AgentAppPlatform>,
}

impl AgentAppCompatibility {
    pub fn supports(&self, platform: PlatformId) -> bool {
        self.platforms.is_empty() || self.platforms.contains(&platform.into())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ExternalSideEffectPolicy {
    Deny,
    RequireApproval,
    AllowByPolicy,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AppNetworkPolicy {
    Deny,
    DeclaredOnly,
    Unrestricted,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundExecutionPolicy {
    Disabled,
    DeclaredOnly,
    Enabled,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MemoryPersistencePolicy {
    Disabled,
    LocalOnly,
    ConfiguredProvider,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AppSkillManagementPolicy {
    Disabled,
    OwnerOnly,
    RuntimePolicy,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppPolicy {
    pub external_side_effects: ExternalSideEffectPolicy,
    pub network: AppNetworkPolicy,
    pub background_execution: BackgroundExecutionPolicy,
    pub memory_persistence: MemoryPersistencePolicy,
    pub skill_management: AppSkillManagementPolicy,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppBranding {
    pub display_name: String,
    pub short_name: Option<String>,
    pub description: Option<String>,
    pub icon: Option<RelativeResourcePath>,
    pub wordmark: Option<RelativeResourcePath>,
    pub accent_color: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppCustomTheme {
    pub id: AgentAppIdentifier,
    pub label: Option<String>,
    pub path: RelativeResourcePath,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppThemes {
    #[serde(default)]
    pub builtins: BTreeSet<AgentAppIdentifier>,
    #[serde(default)]
    pub custom: Vec<AgentAppCustomTheme>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppAppearance {
    pub default_theme: AgentAppIdentifier,
    pub themes: AgentAppThemes,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppInstructionResources {
    pub system: RelativeResourcePath,
    pub developer: Option<RelativeResourcePath>,
    #[serde(default)]
    pub additional: BTreeSet<RelativeResourcePath>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppLocale {
    pub id: AgentAppLocaleId,
    pub label: String,
    pub resource: RelativeResourcePath,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppLocalization {
    pub default_locale: AgentAppLocaleId,
    pub locales: Vec<AgentAppLocale>,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentAppManifest {
    pub schema_version: u32,
    pub app_id: AgentAppId,
    pub package: AgentAppPackage,
    #[serde(default)]
    pub compatibility: AgentAppCompatibility,
    #[serde(default)]
    pub requires: AgentAppRequirements,
    #[serde(default)]
    pub features: BTreeSet<AgentAppIdentifier>,
    pub policy: AgentAppPolicy,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model_access: Option<AgentAppModelAccess>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub identity: Option<AgentAppIdentityConfiguration>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entitlements: Option<AgentAppEntitlementConfiguration>,
    pub branding: AgentAppBranding,
    pub appearance: Option<AgentAppAppearance>,
    pub localization: Option<AgentAppLocalization>,
    pub instructions: AgentAppInstructionResources,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AgentAppManifestWire {
    schema_version: u32,
    app_id: AgentAppId,
    package: AgentAppPackage,
    #[serde(default)]
    compatibility: AgentAppCompatibility,
    #[serde(default)]
    requires: AgentAppRequirements,
    #[serde(default)]
    features: BTreeSet<AgentAppIdentifier>,
    policy: AgentAppPolicy,
    #[serde(default)]
    model_access: Option<AgentAppModelAccess>,
    #[serde(default)]
    identity: Option<AgentAppIdentityConfiguration>,
    #[serde(default)]
    entitlements: Option<AgentAppEntitlementConfiguration>,
    branding: AgentAppBranding,
    appearance: Option<AgentAppAppearance>,
    localization: Option<AgentAppLocalization>,
    instructions: AgentAppInstructionResources,
}

impl TryFrom<AgentAppManifestWire> for AgentAppManifest {
    type Error = anyhow::Error;

    fn try_from(wire: AgentAppManifestWire) -> Result<Self, Self::Error> {
        let mut manifest = Self {
            schema_version: wire.schema_version,
            app_id: wire.app_id,
            package: wire.package,
            compatibility: wire.compatibility,
            requires: wire.requires,
            features: wire.features,
            policy: wire.policy,
            model_access: wire.model_access,
            identity: wire.identity,
            entitlements: wire.entitlements,
            branding: wire.branding,
            appearance: wire.appearance,
            localization: wire.localization,
            instructions: wire.instructions,
        };
        manifest.validate_and_normalize()?;
        Ok(manifest)
    }
}

impl<'de> Deserialize<'de> for AgentAppManifest {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        AgentAppManifestWire::deserialize(deserializer)?
            .try_into()
            .map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug)]
pub struct LoadedAgentAppManifest {
    pub root: PathBuf,
    pub manifest_path: PathBuf,
    pub manifest: AgentAppManifest,
    pub resources: BTreeMap<RelativeResourcePath, PathBuf>,
    canonical_json: Vec<u8>,
    manifest_sha256: String,
}

impl LoadedAgentAppManifest {
    pub fn canonical_json(&self) -> &[u8] {
        &self.canonical_json
    }

    pub fn manifest_sha256(&self) -> &str {
        &self.manifest_sha256
    }

    pub fn resource_path(&self, resource: &RelativeResourcePath) -> Option<&Path> {
        self.resources.get(resource).map(PathBuf::as_path)
    }
}

impl AgentAppManifest {
    pub fn parse_json(bytes: &[u8]) -> anyhow::Result<Self> {
        let value: serde_json::Value =
            serde_json::from_slice(bytes).context("failed to parse agent app manifest JSON")?;
        reject_secret_like_fields(&value, "$")?;
        serde_json::from_value(value).map_err(anyhow::Error::from)
    }

    pub async fn load(package_root: &Path) -> anyhow::Result<LoadedAgentAppManifest> {
        let root_metadata = tokio::fs::symlink_metadata(package_root)
            .await
            .with_context(|| {
                format!(
                    "failed to inspect app package root {}",
                    package_root.display()
                )
            })?;
        anyhow::ensure!(
            root_metadata.is_dir() && !root_metadata.file_type().is_symlink(),
            "app package root must be a real directory: {}",
            package_root.display()
        );

        let canonical_root = tokio::fs::canonicalize(package_root)
            .await
            .with_context(|| {
                format!(
                    "failed to canonicalize app package root {}",
                    package_root.display()
                )
            })?;
        let manifest_path = secure_existing_file(
            &canonical_root,
            &RelativeResourcePath::parse(AGENT_APP_MANIFEST_FILE)?,
        )
        .await
        .context("invalid app manifest file")?;
        let bytes = tokio::fs::read(&manifest_path)
            .await
            .with_context(|| format!("failed to read app manifest {}", manifest_path.display()))?;
        let manifest = Self::parse_json(&bytes)?;

        let mut resources = BTreeMap::new();
        for resource in manifest.resource_references() {
            let resolved = secure_existing_file(&canonical_root, &resource)
                .await
                .with_context(|| format!("invalid app resource {}", resource.as_str()))?;
            resources.insert(resource, resolved);
        }
        validate_locale_resources(&manifest, &resources).await?;

        let canonical_json = manifest.canonical_json()?;
        let manifest_sha256 = hex::encode(Sha256::digest(&canonical_json));
        Ok(LoadedAgentAppManifest {
            root: canonical_root,
            manifest_path,
            manifest,
            resources,
            canonical_json,
            manifest_sha256,
        })
    }

    pub fn canonical_json(&self) -> anyhow::Result<Vec<u8>> {
        let mut normalized = self.clone();
        normalized.validate_and_normalize()?;
        serde_json::to_vec(&normalized).context("failed to serialize canonical app manifest")
    }

    pub fn canonical_sha256(&self) -> anyhow::Result<String> {
        Ok(hex::encode(Sha256::digest(self.canonical_json()?)))
    }

    pub fn supports_platform(&self, platform: PlatformId) -> bool {
        self.compatibility.supports(platform)
    }

    fn validate_and_normalize(&mut self) -> anyhow::Result<()> {
        anyhow::ensure!(
            (AGENT_APP_MANIFEST_MIN_SCHEMA_VERSION..=AGENT_APP_MANIFEST_SCHEMA_VERSION)
                .contains(&self.schema_version),
            "unsupported agent app manifest schema version {}; expected {} through {}",
            self.schema_version,
            AGENT_APP_MANIFEST_MIN_SCHEMA_VERSION,
            AGENT_APP_MANIFEST_SCHEMA_VERSION
        );
        self.validate_access_configuration()?;
        validate_text(
            &self.branding.display_name,
            "branding.displayName",
            MAX_DISPLAY_NAME_LENGTH,
            true,
        )?;
        if let Some(value) = &self.branding.short_name {
            validate_text(value, "branding.shortName", MAX_DISPLAY_NAME_LENGTH, true)?;
        }
        if let Some(value) = &self.branding.description {
            validate_text(value, "branding.description", MAX_SHORT_TEXT_LENGTH, false)?;
        }
        if let Some(color) = &self.branding.accent_color {
            anyhow::ensure!(
                is_valid_hex_color(color),
                "branding.accentColor must be #RRGGBB or #RRGGBBAA"
            );
        }
        if let Some(appearance) = &mut self.appearance {
            for id in &appearance.themes.builtins {
                anyhow::ensure!(
                    VS_CODE_BUILTIN_THEME_IDS.contains(&id.as_str()),
                    "unsupported built-in App theme: {}",
                    id.as_str()
                );
            }
            appearance
                .themes
                .custom
                .sort_by(|left, right| left.id.cmp(&right.id));
            let mut selected = appearance.themes.builtins.clone();
            for custom in &appearance.themes.custom {
                anyhow::ensure!(
                    selected.insert(custom.id.clone()),
                    "duplicate App theme id: {}",
                    custom.id.as_str()
                );
                if let Some(label) = &custom.label {
                    validate_text(
                        label,
                        "appearance theme label",
                        MAX_DISPLAY_NAME_LENGTH,
                        true,
                    )?;
                }
                anyhow::ensure!(
                    custom.path.as_str().starts_with("themes/"),
                    "custom App theme must be inside the themes directory: {}",
                    custom.path.as_str()
                );
                let extension = custom
                    .path
                    .as_path()
                    .extension()
                    .and_then(|value| value.to_str())
                    .unwrap_or_default();
                anyhow::ensure!(
                    extension.eq_ignore_ascii_case("json")
                        || extension.eq_ignore_ascii_case("jsonc"),
                    "custom App theme must be a JSON or JSONC file: {}",
                    custom.path.as_str()
                );
            }
            anyhow::ensure!(
                selected.contains(&appearance.default_theme),
                "appearance.defaultTheme must select a packaged theme"
            );
        }
        if let Some(localization) = &self.localization {
            anyhow::ensure!(
                !localization.locales.is_empty(),
                "localization.locales must contain at least one locale"
            );
            anyhow::ensure!(
                localization.locales.len() <= MAX_APP_LOCALES,
                "localization.locales must contain at most {MAX_APP_LOCALES} locales"
            );
            let mut ids = BTreeSet::new();
            for locale in &localization.locales {
                anyhow::ensure!(
                    ids.insert(locale.id.clone()),
                    "duplicate App locale id: {}",
                    locale.id.as_str()
                );
                validate_text(
                    &locale.label,
                    "localization locale label",
                    MAX_DISPLAY_NAME_LENGTH,
                    true,
                )?;
                anyhow::ensure!(
                    locale.resource.as_str().starts_with("locales/"),
                    "App locale resource must be inside the locales directory: {}",
                    locale.resource.as_str()
                );
                anyhow::ensure!(
                    locale
                        .resource
                        .as_path()
                        .extension()
                        .and_then(|value| value.to_str())
                        .is_some_and(|extension| extension.eq_ignore_ascii_case("json")),
                    "App locale resource must be a JSON file: {}",
                    locale.resource.as_str()
                );
            }
            anyhow::ensure!(
                ids.contains(&localization.default_locale),
                "localization.defaultLocale must select a packaged locale"
            );
        }

        self.requires
            .packages
            .sort_by(|left, right| left.id.cmp(&right.id));
        for pair in self.requires.packages.windows(2) {
            anyhow::ensure!(
                pair[0].id != pair[1].id,
                "duplicate required app package id: {}",
                pair[0].id.as_str()
            );
        }
        Ok(())
    }

    fn resource_references(&self) -> BTreeSet<RelativeResourcePath> {
        let mut resources = self.instructions.additional.clone();
        resources.insert(self.instructions.system.clone());
        if let Some(path) = &self.instructions.developer {
            resources.insert(path.clone());
        }
        if let Some(path) = &self.branding.icon {
            resources.insert(path.clone());
        }
        if let Some(path) = &self.branding.wordmark {
            resources.insert(path.clone());
        }
        if let Some(appearance) = &self.appearance {
            for custom in &appearance.themes.custom {
                resources.insert(custom.path.clone());
            }
        }
        if let Some(localization) = &self.localization {
            for locale in &localization.locales {
                resources.insert(locale.resource.clone());
            }
        }
        resources
    }
}

async fn validate_locale_resources(
    manifest: &AgentAppManifest,
    resources: &BTreeMap<RelativeResourcePath, PathBuf>,
) -> anyhow::Result<()> {
    let Some(localization) = &manifest.localization else {
        return Ok(());
    };
    let mut reference: Option<BTreeMap<String, BTreeSet<String>>> = None;
    for locale in &localization.locales {
        let path = resources
            .get(&locale.resource)
            .context("resolved App locale resource is unavailable")?;
        let bytes = tokio::fs::read(path).await?;
        anyhow::ensure!(
            bytes.len() <= MAX_LOCALE_CATALOG_BYTES,
            "App locale '{}' exceeds {} bytes",
            locale.id.as_str(),
            MAX_LOCALE_CATALOG_BYTES
        );
        let catalog: BTreeMap<String, String> = serde_json::from_slice(&bytes)
            .with_context(|| format!("invalid App locale catalog '{}'", locale.id.as_str()))?;
        let mut shape = BTreeMap::new();
        for (key, value) in catalog {
            anyhow::ensure!(
                valid_message_key(&key),
                "invalid App locale message key: {key}"
            );
            anyhow::ensure!(
                !value.trim().is_empty() && value.len() <= MAX_LOCALE_MESSAGE_BYTES,
                "App locale message '{key}' must be non-empty and at most {MAX_LOCALE_MESSAGE_BYTES} bytes"
            );
            shape.insert(key, message_placeholders(&value));
        }
        if let Some(expected) = &reference {
            anyhow::ensure!(
                expected == &shape,
                "App locale '{}' must preserve message keys and placeholders",
                locale.id.as_str()
            );
        } else {
            reference = Some(shape);
        }
    }
    Ok(())
}

fn valid_message_key(key: &str) -> bool {
    key.bytes()
        .next()
        .is_some_and(|byte| byte.is_ascii_lowercase())
        && key.split(['.', '_', '-']).all(|segment| {
            !segment.is_empty() && segment.bytes().all(|byte| byte.is_ascii_alphanumeric())
        })
}

fn message_placeholders(value: &str) -> BTreeSet<String> {
    value
        .split('{')
        .skip(1)
        .filter_map(|tail| tail.split_once('}').map(|(placeholder, _)| placeholder))
        .filter(|placeholder| {
            placeholder
                .bytes()
                .next()
                .is_some_and(|byte| byte.is_ascii_alphabetic())
                && placeholder
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
        })
        .map(str::to_string)
        .collect()
}

async fn secure_existing_file(
    canonical_root: &Path,
    relative: &RelativeResourcePath,
) -> anyhow::Result<PathBuf> {
    let mut candidate = canonical_root.to_path_buf();
    for component in relative.as_path().components() {
        let Component::Normal(component) = component else {
            anyhow::bail!(
                "resource path is not relative and normal: {}",
                relative.as_str()
            );
        };
        candidate.push(component);
        let metadata = match tokio::fs::symlink_metadata(&candidate).await {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == ErrorKind::NotFound => {
                anyhow::bail!("app resource does not exist: {}", relative.as_str())
            }
            Err(error) => {
                return Err(error).with_context(|| {
                    format!("failed to inspect app resource {}", candidate.display())
                });
            }
        };
        anyhow::ensure!(
            !metadata.file_type().is_symlink(),
            "app resource path must not contain symlinks: {}",
            relative.as_str()
        );
    }

    let metadata = tokio::fs::metadata(&candidate)
        .await
        .with_context(|| format!("failed to inspect app resource {}", candidate.display()))?;
    anyhow::ensure!(
        metadata.is_file(),
        "app resource must be a file: {}",
        relative.as_str()
    );
    let canonical = tokio::fs::canonicalize(&candidate).await.with_context(|| {
        format!(
            "failed to canonicalize app resource {}",
            candidate.display()
        )
    })?;
    anyhow::ensure!(
        canonical.starts_with(canonical_root),
        "app resource escapes package root: {}",
        relative.as_str()
    );
    Ok(canonical)
}

fn validate_reverse_dns_id(value: &str, label: &str) -> anyhow::Result<()> {
    let valid = !value.is_empty()
        && value.len() <= MAX_REVERSE_DNS_ID_LENGTH
        && value.split('.').count() >= 3
        && value.split('.').all(is_valid_reverse_dns_segment);
    anyhow::ensure!(valid, "invalid {label}: {value}");
    Ok(())
}

fn is_valid_reverse_dns_segment(segment: &str) -> bool {
    !segment.is_empty()
        && !segment.starts_with('-')
        && !segment.ends_with('-')
        && segment
            .chars()
            .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-')
}

fn is_valid_identifier_segment(segment: &str) -> bool {
    !segment.is_empty()
        && !segment.starts_with(['-', '_'])
        && !segment.ends_with(['-', '_'])
        && segment
            .chars()
            .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-' || ch == '_')
}

fn validate_relative_resource_path(value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.is_empty(), "app resource path cannot be empty");
    anyhow::ensure!(
        !value.contains('\0'),
        "app resource path cannot contain NUL"
    );
    anyhow::ensure!(
        !value.contains('\\'),
        "app resource paths must use portable '/' separators: {value}"
    );
    anyhow::ensure!(
        !value.starts_with('/') && !looks_like_windows_absolute_path(value),
        "app resource path must be relative: {value}"
    );
    anyhow::ensure!(
        value
            .split('/')
            .all(|segment| !segment.is_empty() && segment != "." && segment != ".."),
        "app resource path must contain only relative normal components: {value}"
    );
    let path = Path::new(value);
    anyhow::ensure!(
        path.components()
            .all(|component| matches!(component, Component::Normal(_))),
        "app resource path must contain only relative normal components: {value}"
    );
    Ok(())
}

fn validate_locale_id(value: &str) -> anyhow::Result<()> {
    let segments = value.split('-').collect::<Vec<_>>();
    let primary = segments.first().copied().unwrap_or_default();
    let valid = (2..=8).contains(&primary.len())
        && primary.bytes().all(|byte| byte.is_ascii_lowercase())
        && segments.iter().skip(1).all(|segment| {
            (1..=8).contains(&segment.len())
                && segment.bytes().all(|byte| byte.is_ascii_alphanumeric())
        });
    anyhow::ensure!(
        valid && value.len() <= 64,
        "invalid App locale id: {value}; use a BCP 47 tag such as en or zh-CN"
    );
    Ok(())
}

fn looks_like_windows_absolute_path(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':'
}

fn validate_text(value: &str, label: &str, maximum: usize, required: bool) -> anyhow::Result<()> {
    anyhow::ensure!(
        value == value.trim(),
        "{label} must not have surrounding whitespace"
    );
    if required {
        anyhow::ensure!(!value.is_empty(), "{label} cannot be empty");
    }
    anyhow::ensure!(
        value.chars().count() <= maximum,
        "{label} exceeds {maximum} characters"
    );
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{label} cannot contain control characters"
    );
    Ok(())
}

fn is_valid_hex_color(value: &str) -> bool {
    matches!(value.len(), 7 | 9)
        && value.starts_with('#')
        && value[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
}

impl fmt::Display for AgentAppPlatform {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[cfg(test)]
#[path = "app_manifest_tests.rs"]
mod tests;
