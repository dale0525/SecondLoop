use axum::Json;
use axum::body::Body;
use axum::extract::{Request, State};
use axum::http::{HeaderMap, HeaderName, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Arc;
use tokio::net::TcpListener;
use zeroize::Zeroize;

pub const DEVELOPMENT_PORT: u16 = 49_321;
pub const LAUNCH_CONFIG_FD_ENV: &str = "AGENTWEAVE_LAUNCH_CONFIG_FD";
pub const LAUNCH_RESULT_FD_ENV: &str = "AGENTWEAVE_LAUNCH_RESULT_FD";
pub const TRANSPORT_HEADER: HeaderName = HeaderName::from_static("x-agentweave-transport");

const LAUNCH_SCHEMA_VERSION: u8 = 1;
const MAX_LAUNCH_BYTES: usize = 4_096;
const MIN_TOKEN_BYTES: usize = 43;
const MAX_TOKEN_BYTES: usize = 128;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LaunchConfigWire {
    schema_version: u8,
    launch_id: String,
    transport_token: String,
    #[serde(default)]
    data_protection_key_hex: Option<String>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LaunchResult {
    pub schema_version: u8,
    pub launch_id: String,
    pub pid: u32,
    pub origin: String,
}

struct TransportSecret(Vec<u8>);

impl Drop for TransportSecret {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

#[derive(Clone)]
pub struct TransportAuth {
    secret: Arc<TransportSecret>,
}

impl TransportAuth {
    pub fn new(token: impl AsRef<[u8]>) -> anyhow::Result<Self> {
        let token = token.as_ref();
        anyhow::ensure!(valid_token(token), "local transport credential is invalid");
        Ok(Self {
            secret: Arc::new(TransportSecret(token.to_vec())),
        })
    }

    pub fn authenticate(&self, headers: &HeaderMap) -> bool {
        let supplied = headers
            .get(&TRANSPORT_HEADER)
            .map(|value| value.as_bytes())
            .unwrap_or_default();
        constant_time_eq(&self.secret.0, supplied)
    }
}

struct LaunchConfig {
    launch_id: String,
    auth: TransportAuth,
    data_protection_key: Option<agent_runtime::credential::SecretMaterial>,
}

pub struct PreparedLocalTransport {
    listener: TcpListener,
    auth: Option<TransportAuth>,
    address: SocketAddr,
    data_protection_key: Option<agent_runtime::credential::SecretMaterial>,
}

impl PreparedLocalTransport {
    pub fn take_data_protection_key(
        &mut self,
    ) -> Option<agent_runtime::credential::SecretMaterial> {
        self.data_protection_key.take()
    }

    pub fn auth(&self) -> Option<TransportAuth> {
        self.auth.clone()
    }

    pub fn address(&self) -> SocketAddr {
        self.address
    }

    pub fn into_listener(self) -> TcpListener {
        self.listener
    }
}

pub async fn prepare_from_environment() -> anyhow::Result<PreparedLocalTransport> {
    let descriptors = launch_descriptors(|name| std::env::var(name).ok())?;
    let Some((config_fd, result_fd)) = descriptors else {
        let address = SocketAddr::from((Ipv4Addr::LOCALHOST, DEVELOPMENT_PORT));
        let listener = TcpListener::bind(address).await?;
        return Ok(PreparedLocalTransport {
            listener,
            auth: None,
            address,
            data_protection_key: None,
        });
    };

    #[cfg(not(unix))]
    {
        let _ = (config_fd, result_fd);
        anyhow::bail!("inherited local transport pipes are unsupported on this platform");
    }

    #[cfg(unix)]
    {
        let config = read_launch_config_fd(config_fd)?;
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
        let address = listener.local_addr()?;
        let result = LaunchResult {
            schema_version: LAUNCH_SCHEMA_VERSION,
            launch_id: config.launch_id,
            pid: std::process::id(),
            origin: format!("http://{address}"),
        };
        write_launch_result_fd(result_fd, &result)?;
        Ok(PreparedLocalTransport {
            listener,
            auth: Some(config.auth),
            address,
            data_protection_key: config.data_protection_key,
        })
    }
}

pub async fn require_transport(
    State(auth): State<TransportAuth>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if !auth.authenticate(request.headers()) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "error": "unauthorized" })),
        )
            .into_response();
    }
    next.run(request).await
}

fn launch_descriptors<F>(lookup: F) -> anyhow::Result<Option<(i32, i32)>>
where
    F: Fn(&str) -> Option<String>,
{
    let config = lookup(LAUNCH_CONFIG_FD_ENV);
    let result = lookup(LAUNCH_RESULT_FD_ENV);
    match (config, result) {
        (None, None) => Ok(None),
        (Some(config), Some(result)) => {
            let config = parse_descriptor(&config)?;
            let result = parse_descriptor(&result)?;
            anyhow::ensure!(
                config != result,
                "local transport descriptors must be distinct"
            );
            Ok(Some((config, result)))
        }
        _ => anyhow::bail!("both local transport descriptors are required"),
    }
}

fn parse_descriptor(value: &str) -> anyhow::Result<i32> {
    let descriptor: i32 = value
        .parse()
        .map_err(|_| anyhow::anyhow!("local transport descriptor is invalid"))?;
    anyhow::ensure!(
        (3..=255).contains(&descriptor),
        "local transport descriptor is invalid"
    );
    Ok(descriptor)
}

fn read_launch_config(mut reader: impl Read) -> anyhow::Result<LaunchConfig> {
    let mut bytes = Vec::new();
    reader
        .by_ref()
        .take((MAX_LAUNCH_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.is_empty() || bytes.len() > MAX_LAUNCH_BYTES {
        bytes.zeroize();
        anyhow::bail!("local transport launch configuration is invalid");
    }
    let parsed = serde_json::from_slice::<LaunchConfigWire>(&bytes);
    bytes.zeroize();
    let wire =
        parsed.map_err(|_| anyhow::anyhow!("local transport launch configuration is invalid"))?;
    validate_launch_config(wire)
}

fn validate_launch_config(wire: LaunchConfigWire) -> anyhow::Result<LaunchConfig> {
    let mut token = wire.transport_token.into_bytes();
    let mut data_protection_key = wire.data_protection_key_hex.map(|value| value.into_bytes());
    let result = (|| {
        anyhow::ensure!(
            wire.schema_version == LAUNCH_SCHEMA_VERSION,
            "local transport launch schema is unsupported"
        );
        let launch_id = uuid::Uuid::parse_str(&wire.launch_id)
            .map_err(|_| anyhow::anyhow!("local transport launch identifier is invalid"))?;
        anyhow::ensure!(
            launch_id.to_string() == wire.launch_id,
            "local transport launch identifier is invalid"
        );
        let auth = TransportAuth::new(&token)?;
        let data_protection_key = data_protection_key
            .as_deref()
            .map(|value| {
                anyhow::ensure!(
                    value.len() == 64
                        && value
                            .iter()
                            .all(|byte| byte.is_ascii_digit() || matches!(byte, b'a'..=b'f')),
                    "data protection key is invalid"
                );
                let decoded = hex::decode(value)
                    .map_err(|_| anyhow::anyhow!("data protection key is invalid"))?;
                anyhow::ensure!(decoded.len() == 32, "data protection key is invalid");
                agent_runtime::credential::SecretMaterial::new(decoded)
            })
            .transpose()?;
        Ok(LaunchConfig {
            launch_id: launch_id.to_string(),
            auth,
            data_protection_key,
        })
    })();
    token.zeroize();
    if let Some(key) = &mut data_protection_key {
        key.zeroize();
    }
    result
}

fn valid_token(token: &[u8]) -> bool {
    (MIN_TOKEN_BYTES..=MAX_TOKEN_BYTES).contains(&token.len())
        && token
            .iter()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

fn write_launch_result(mut writer: impl Write, result: &LaunchResult) -> anyhow::Result<()> {
    serde_json::to_writer(&mut writer, result)?;
    writer.write_all(b"\n")?;
    writer.flush()?;
    Ok(())
}

#[cfg(unix)]
fn read_launch_config_fd(descriptor: i32) -> anyhow::Result<LaunchConfig> {
    use std::os::fd::FromRawFd;
    // SAFETY: the launcher transfers ownership of this inherited descriptor to the child.
    let file = unsafe { std::fs::File::from_raw_fd(descriptor) };
    read_launch_config(file)
}

#[cfg(unix)]
fn write_launch_result_fd(descriptor: i32, result: &LaunchResult) -> anyhow::Result<()> {
    use std::os::fd::FromRawFd;
    // SAFETY: the launcher transfers ownership of this inherited descriptor to the child.
    let file = unsafe { std::fs::File::from_raw_fd(descriptor) };
    write_launch_result(file, result)
}

fn constant_time_eq(expected: &[u8], supplied: &[u8]) -> bool {
    let mut difference = expected.len() ^ supplied.len();
    for (index, expected_byte) in expected.iter().enumerate() {
        let supplied_byte = supplied.get(index).copied().unwrap_or_default();
        difference |= usize::from(expected_byte ^ supplied_byte);
    }
    difference == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    const LAUNCH_ID: &str = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const TOKEN: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";

    #[test]
    fn launch_configuration_is_closed_bounded_and_secret_bearing() {
        let config = read_launch_config(
            format!(r#"{{"schemaVersion":1,"launchId":"{LAUNCH_ID}","transportToken":"{TOKEN}"}}"#)
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(config.launch_id, LAUNCH_ID);
        let mut headers = HeaderMap::new();
        headers.insert(&TRANSPORT_HEADER, HeaderValue::from_static(TOKEN));
        assert!(config.auth.authenticate(&headers));
        assert!(config.data_protection_key.is_none());

        let protected = read_launch_config(
            format!(
                r#"{{"schemaVersion":1,"launchId":"{LAUNCH_ID}","transportToken":"{TOKEN}","dataProtectionKeyHex":"{}"}}"#,
                "ab".repeat(32),
            )
            .as_bytes(),
        )
        .unwrap();
        assert!(protected.data_protection_key.is_some());

        for invalid in [
            format!(r#"{{"schemaVersion":2,"launchId":"{LAUNCH_ID}","transportToken":"{TOKEN}"}}"#),
            format!(r#"{{"schemaVersion":1,"launchId":"not-a-uuid","transportToken":"{TOKEN}"}}"#),
            format!(r#"{{"schemaVersion":1,"launchId":"{LAUNCH_ID}","transportToken":"short"}}"#),
            format!(
                r#"{{"schemaVersion":1,"launchId":"{LAUNCH_ID}","transportToken":"{TOKEN}","dataProtectionKeyHex":"short"}}"#
            ),
            format!(
                r#"{{"schemaVersion":1,"launchId":"{LAUNCH_ID}","transportToken":"{TOKEN}","extra":true}}"#
            ),
        ] {
            assert!(read_launch_config(invalid.as_bytes()).is_err());
        }
        assert!(read_launch_config(vec![b'x'; MAX_LAUNCH_BYTES + 1].as_slice()).is_err());
    }

    #[test]
    fn transport_authentication_is_exact_and_constant_shape() {
        let auth = TransportAuth::new(TOKEN).unwrap();
        let mut headers = HeaderMap::new();
        assert!(!auth.authenticate(&headers));
        headers.insert(&TRANSPORT_HEADER, HeaderValue::from_static("wrong"));
        assert!(!auth.authenticate(&headers));
        headers.insert(&TRANSPORT_HEADER, HeaderValue::from_static(TOKEN));
        assert!(auth.authenticate(&headers));
    }

    #[test]
    fn descriptor_contract_requires_a_distinct_pair() {
        assert_eq!(launch_descriptors(|_| None).unwrap(), None);
        assert!(
            launch_descriptors(|name| (name == LAUNCH_CONFIG_FD_ENV).then(|| "3".into())).is_err()
        );
        assert!(launch_descriptors(|_| Some("3".into())).is_err());
        assert_eq!(
            launch_descriptors(|name| match name {
                LAUNCH_CONFIG_FD_ENV => Some("3".into()),
                LAUNCH_RESULT_FD_ENV => Some("4".into()),
                _ => None,
            })
            .unwrap(),
            Some((3, 4))
        );
    }

    #[test]
    fn launch_result_contains_no_transport_credential() {
        let result = LaunchResult {
            schema_version: 1,
            launch_id: LAUNCH_ID.into(),
            pid: 42,
            origin: "http://127.0.0.1:53119".into(),
        };
        let mut bytes = Vec::new();
        write_launch_result(&mut bytes, &result).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value["launchId"], LAUNCH_ID);
        assert_eq!(value["pid"], 42);
        assert!(value.get("transportToken").is_none());
    }
}
