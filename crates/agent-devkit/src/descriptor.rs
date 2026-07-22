use crate::{DevkitError, DevkitResult, SensitiveInputHandle};
use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use url::Url;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderKind {
    Identity,
    Entitlement,
    Commerce,
    GatewayDeployment,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ProtocolCompatibility {
    pub requirement: VersionReq,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum HostPlatform {
    Macos,
    Windows,
    Linux,
    Android,
    Ios,
    Server,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ConfigFieldType {
    String,
    Integer,
    Boolean,
    HttpsUrl,
    Url,
    StringList,
    StringMap,
    IntegerMap,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct ConfigFieldDescriptor {
    pub id: String,
    pub label: String,
    pub description: String,
    pub field_type: ConfigFieldType,
    pub required: bool,
    pub default_value: Option<Value>,
    pub allowed_values: Vec<Value>,
    pub minimum_length: Option<usize>,
    pub maximum_length: Option<usize>,
    pub advanced: bool,
    pub visible_when: Option<FieldCondition>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct SensitiveFieldDescriptor {
    pub id: String,
    pub label: String,
    pub description: String,
    pub required: bool,
    pub purpose: String,
    pub rotation_supported: bool,
    pub visible_when: Option<FieldCondition>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct FieldCondition {
    pub field_id: String,
    pub equals: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CrossFieldRule {
    pub rule_id: String,
    pub description: String,
    pub required_together: BTreeSet<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct ProviderConfigurationSchema {
    pub schema_version: u32,
    pub migration_version: u32,
    pub public_fields: Vec<ConfigFieldDescriptor>,
    pub sensitive_fields: Vec<SensitiveFieldDescriptor>,
    pub cross_field_rules: Vec<CrossFieldRule>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct ProviderDescriptor {
    pub schema_version: u32,
    pub package_id: String,
    pub provider_id: String,
    pub provider_version: Version,
    pub protocol_compatibility: ProtocolCompatibility,
    pub kind: ProviderKind,
    pub display_name: String,
    pub description: String,
    pub documentation_url: Url,
    pub risk_notice: String,
    pub platforms: BTreeSet<HostPlatform>,
    pub capabilities: BTreeSet<String>,
    pub configuration_schema: ProviderConfigurationSchema,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub developer_authorization_schema: Option<ProviderConfigurationSchema>,
}

impl ProviderDescriptor {
    pub fn validate(&self) -> DevkitResult<()> {
        validate_kebab_identifier("package id", &self.package_id)?;
        validate_provider_identifier(&self.provider_id)?;
        if self.schema_version == 0 {
            return Err(DevkitError::invalid_configuration(
                "provider schema versions must be non-zero",
            ));
        }
        if self.documentation_url.scheme() != "https" {
            return Err(DevkitError::invalid_configuration(
                "provider documentation URL must use HTTPS",
            ));
        }
        validate_configuration_schema(&self.configuration_schema)?;
        if let Some(schema) = &self.developer_authorization_schema {
            validate_configuration_schema(schema)?;
        }
        Ok(())
    }
}

fn validate_configuration_schema(schema: &ProviderConfigurationSchema) -> DevkitResult<()> {
    if schema.schema_version == 0 {
        return Err(DevkitError::invalid_configuration(
            "provider schema versions must be non-zero",
        ));
    }
    let mut ids = BTreeSet::new();
    for field in &schema.public_fields {
        validate_field_identifier("configuration field id", &field.id)?;
        if !ids.insert(field.id.as_str()) {
            return Err(DevkitError::invalid_configuration(
                "provider configuration field ids must be unique",
            ));
        }
    }
    for field in &schema.sensitive_fields {
        validate_field_identifier("sensitive field id", &field.id)?;
        if !ids.insert(field.id.as_str()) {
            return Err(DevkitError::invalid_configuration(
                "provider configuration field ids must be unique",
            ));
        }
    }
    Ok(())
}

#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct ProviderConfiguration {
    pub schema_version: u32,
    pub public: BTreeMap<String, Value>,
    pub sensitive: BTreeMap<String, SensitiveInputHandle>,
}

impl std::fmt::Debug for ProviderConfiguration {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ProviderConfiguration")
            .field("schema_version", &self.schema_version)
            .field("public", &self.public)
            .field("sensitive_keys", &self.sensitive.keys().collect::<Vec<_>>())
            .finish()
    }
}

impl ProviderConfiguration {
    pub fn validate_against(&self, descriptor: &ProviderDescriptor) -> DevkitResult<()> {
        descriptor.validate()?;
        self.validate_against_schema(&descriptor.configuration_schema)
    }

    pub fn validate_developer_authorization_against(
        &self,
        descriptor: &ProviderDescriptor,
    ) -> DevkitResult<()> {
        descriptor.validate()?;
        let schema = descriptor
            .developer_authorization_schema
            .as_ref()
            .ok_or_else(|| {
                DevkitError::invalid_configuration(
                    "provider does not declare developer authorization configuration",
                )
            })?;
        self.validate_against_schema(schema)
    }

    fn validate_against_schema(&self, schema: &ProviderConfigurationSchema) -> DevkitResult<()> {
        if self.schema_version != schema.schema_version {
            return Err(DevkitError::invalid_configuration(
                "provider configuration schema version is incompatible",
            ));
        }
        let public_descriptors = schema
            .public_fields
            .iter()
            .map(|field| (field.id.as_str(), field))
            .collect::<BTreeMap<_, _>>();
        let sensitive_descriptors = schema
            .sensitive_fields
            .iter()
            .map(|field| (field.id.as_str(), field))
            .collect::<BTreeMap<_, _>>();
        if let Some(key) = self
            .public
            .keys()
            .find(|key| !public_descriptors.contains_key(key.as_str()))
        {
            return Err(DevkitError::invalid_configuration(format!(
                "unknown public configuration field: {key}"
            )));
        }
        if let Some(key) = self
            .sensitive
            .keys()
            .find(|key| !sensitive_descriptors.contains_key(key.as_str()))
        {
            return Err(DevkitError::invalid_configuration(format!(
                "unknown sensitive configuration field: {key}"
            )));
        }
        for field in public_descriptors.values() {
            if field.required && !self.public.contains_key(&field.id) {
                return Err(DevkitError::invalid_configuration(format!(
                    "required public configuration field is missing: {}",
                    field.id
                )));
            }
            if let Some(value) = self.public.get(&field.id) {
                validate_field_value(field, value)?;
            }
        }
        for field in sensitive_descriptors.values() {
            if field.required && !self.sensitive.contains_key(&field.id) {
                return Err(DevkitError::invalid_configuration(format!(
                    "required sensitive configuration field is missing: {}",
                    field.id
                )));
            }
        }
        for rule in &schema.cross_field_rules {
            let present = rule
                .required_together
                .iter()
                .filter(|id| self.public.contains_key(*id) || self.sensitive.contains_key(*id))
                .count();
            if present != 0 && present != rule.required_together.len() {
                return Err(DevkitError::invalid_configuration(format!(
                    "cross-field configuration rule is not satisfied: {}",
                    rule.rule_id
                )));
            }
        }
        Ok(())
    }
}

fn validate_kebab_identifier(label: &str, value: &str) -> DevkitResult<()> {
    let valid = !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-');
    if !valid {
        return Err(DevkitError::invalid_configuration(format!(
            "{label} must be a stable kebab-case identifier"
        )));
    }
    Ok(())
}

fn validate_provider_identifier(value: &str) -> DevkitResult<()> {
    let valid = !value.is_empty()
        && value.len() <= 128
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'.' | b'-' | b'_')
        })
        && value
            .bytes()
            .next()
            .is_some_and(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        && value
            .bytes()
            .next_back()
            .is_some_and(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit());
    if valid {
        Ok(())
    } else {
        Err(DevkitError::invalid_configuration(
            "provider id must be a stable lowercase identifier",
        ))
    }
}

fn validate_field_identifier(label: &str, value: &str) -> DevkitResult<()> {
    let valid = !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .next()
            .is_some_and(|byte| byte.is_ascii_lowercase())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'));
    if valid {
        Ok(())
    } else {
        Err(DevkitError::invalid_configuration(format!(
            "{label} must be a stable configuration identifier"
        )))
    }
}

fn validate_field_value(field: &ConfigFieldDescriptor, value: &Value) -> DevkitResult<()> {
    let type_valid = match field.field_type {
        ConfigFieldType::String | ConfigFieldType::HttpsUrl | ConfigFieldType::Url => {
            value.is_string()
        }
        ConfigFieldType::Integer => value.is_i64() || value.is_u64(),
        ConfigFieldType::Boolean => value.is_boolean(),
        ConfigFieldType::StringList => value
            .as_array()
            .is_some_and(|values| values.iter().all(Value::is_string)),
        ConfigFieldType::StringMap => value
            .as_object()
            .is_some_and(|values| values.values().all(Value::is_string)),
        ConfigFieldType::IntegerMap => value.as_object().is_some_and(|values| {
            values
                .values()
                .all(|value| value.is_i64() || value.is_u64())
        }),
    };
    if !type_valid {
        return Err(DevkitError::invalid_configuration(format!(
            "configuration field has the wrong type: {}",
            field.id
        )));
    }
    if matches!(
        field.field_type,
        ConfigFieldType::HttpsUrl | ConfigFieldType::Url
    ) {
        let url = Url::parse(value.as_str().unwrap_or_default()).map_err(|_| {
            DevkitError::invalid_configuration(format!(
                "configuration URL field is invalid: {}",
                field.id
            ))
        })?;
        let allowed = match field.field_type {
            ConfigFieldType::HttpsUrl => url.scheme() == "https" && url.host().is_some(),
            ConfigFieldType::Url => {
                (url.scheme() == "https" && url.host().is_some())
                    || (url.scheme() == "http"
                        && url.host_str().is_some_and(|host| {
                            host.eq_ignore_ascii_case("localhost")
                                || host
                                    .parse::<std::net::IpAddr>()
                                    .is_ok_and(|address| address.is_loopback())
                        }))
                    || (url.host().is_none() && url.scheme().contains('.'))
            }
            _ => false,
        };
        if !allowed {
            return Err(DevkitError::invalid_configuration(format!(
                "configuration URL field must use HTTPS or an explicitly local callback: {}",
                field.id
            )));
        }
    }
    if let Some(text) = value.as_str()
        && (field
            .minimum_length
            .is_some_and(|minimum| text.len() < minimum)
            || field
                .maximum_length
                .is_some_and(|maximum| text.len() > maximum))
    {
        return Err(DevkitError::invalid_configuration(format!(
            "configuration field length is invalid: {}",
            field.id
        )));
    }
    if !field.allowed_values.is_empty() && !field.allowed_values.contains(value) {
        return Err(DevkitError::invalid_configuration(format!(
            "configuration field value is not allowed: {}",
            field.id
        )));
    }
    Ok(())
}
