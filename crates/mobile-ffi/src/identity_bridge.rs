use crate::identity_runtime::{
    MobileIdentityError, MobileIdentityInitConfig, MobileIdentityRuntime,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicI64, Ordering};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

static NEXT_IDENTITY_HANDLE: AtomicI64 = AtomicI64::new(1);
static IDENTITIES: OnceLock<Mutex<HashMap<i64, Arc<MobileIdentityRuntime>>>> = OnceLock::new();

#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum MobileIdentityRequest {
    Status,
    BeginAuthorization { force_account_selection: bool },
    CompleteAuthorization { callback_url: String },
    Refresh,
    GatewayCredential,
    Logout,
}

#[derive(Serialize)]
struct BridgeError {
    code: &'static str,
    message: &'static str,
}

pub fn initialize_identity_runtime_json(request_json: &str, master_key: &[u8]) -> String {
    let result = (|| {
        let config: MobileIdentityInitConfig = serde_json::from_str(request_json)
            .map_err(|_| IdentityBridgeError::InvalidInitialization)?;
        let runtime = MobileIdentityRuntime::initialize(config, master_key)
            .map_err(|_| IdentityBridgeError::InvalidInitialization)?;
        let handle = NEXT_IDENTITY_HANDLE.fetch_add(1, Ordering::Relaxed);
        identities()
            .lock()
            .map_err(|_| IdentityBridgeError::Unavailable)?
            .insert(handle, Arc::new(runtime));
        Ok(json!({ "handle": handle }))
    })();
    bridge_result(result)
}

pub fn invoke_identity_runtime_json(handle: i64, request_json: &str) -> String {
    let result = (|| {
        let request = parse_identity_request(request_json)?;
        let runtime = identity(handle)?;
        match request {
            MobileIdentityRequest::Status => serde_json::to_value(runtime.status()),
            MobileIdentityRequest::BeginAuthorization {
                force_account_selection,
            } => serde_json::to_value(
                runtime
                    .begin_authorization(force_account_selection)
                    .map_err(IdentityBridgeError::from)?,
            ),
            MobileIdentityRequest::CompleteAuthorization { callback_url } => serde_json::to_value(
                runtime
                    .complete_authorization(&callback_url)
                    .map_err(IdentityBridgeError::from)?,
            ),
            MobileIdentityRequest::Refresh => {
                serde_json::to_value(runtime.refresh().map_err(IdentityBridgeError::from)?)
            }
            MobileIdentityRequest::GatewayCredential => serde_json::to_value(
                runtime
                    .gateway_credential()
                    .map_err(IdentityBridgeError::from)?,
            ),
            MobileIdentityRequest::Logout => {
                serde_json::to_value(runtime.logout().map_err(IdentityBridgeError::from)?)
            }
        }
        .map_err(|_| IdentityBridgeError::Unavailable)
    })();
    bridge_result(result)
}

fn parse_identity_request(
    request_json: &str,
) -> Result<MobileIdentityRequest, IdentityBridgeError> {
    let value: Value =
        serde_json::from_str(request_json).map_err(|_| IdentityBridgeError::InvalidRequest)?;
    let object = value
        .as_object()
        .ok_or(IdentityBridgeError::InvalidRequest)?;
    let operation = object
        .get("operation")
        .and_then(Value::as_str)
        .ok_or(IdentityBridgeError::InvalidRequest)?;
    let allowed: &[&str] = match operation {
        "status" | "refresh" | "gateway_credential" | "logout" => &["operation"],
        "begin_authorization" => &["operation", "force_account_selection"],
        "complete_authorization" => &["operation", "callback_url"],
        _ => return Err(IdentityBridgeError::InvalidRequest),
    };
    if object.keys().any(|key| !allowed.contains(&key.as_str()))
        || allowed.iter().any(|key| !object.contains_key(*key))
    {
        return Err(IdentityBridgeError::InvalidRequest);
    }
    serde_json::from_value(value).map_err(|_| IdentityBridgeError::InvalidRequest)
}

pub fn close_identity_runtime(handle: i64) -> String {
    let result = (|| {
        let runtime = identities()
            .lock()
            .map_err(|_| IdentityBridgeError::Unavailable)?
            .remove(&handle)
            .ok_or(IdentityBridgeError::InvalidHandle)?;
        runtime.close();
        Ok(Value::Null)
    })();
    bridge_result(result)
}

fn identity(handle: i64) -> Result<Arc<MobileIdentityRuntime>, IdentityBridgeError> {
    identities()
        .lock()
        .map_err(|_| IdentityBridgeError::Unavailable)?
        .get(&handle)
        .cloned()
        .ok_or(IdentityBridgeError::InvalidHandle)
}

fn identities() -> &'static Mutex<HashMap<i64, Arc<MobileIdentityRuntime>>> {
    IDENTITIES.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Clone, Copy, Debug)]
enum IdentityBridgeError {
    InvalidInitialization,
    InvalidHandle,
    InvalidRequest,
    NotConfigured,
    AuthenticationRequired,
    AccessDenied,
    Unavailable,
    SecureStorage,
}

impl From<MobileIdentityError> for IdentityBridgeError {
    fn from(error: MobileIdentityError) -> Self {
        match error {
            MobileIdentityError::NotConfigured => Self::NotConfigured,
            MobileIdentityError::InvalidRequest => Self::InvalidRequest,
            MobileIdentityError::AuthenticationRequired => Self::AuthenticationRequired,
            MobileIdentityError::AccessDenied => Self::AccessDenied,
            MobileIdentityError::Unavailable => Self::Unavailable,
            MobileIdentityError::SecureStorage => Self::SecureStorage,
        }
    }
}

impl IdentityBridgeError {
    fn payload(self) -> BridgeError {
        match self {
            Self::InvalidInitialization => BridgeError {
                code: "identity_initialization_failed",
                message: "Identity could not be initialized",
            },
            Self::InvalidHandle => BridgeError {
                code: "identity_handle_invalid",
                message: "Identity session is unavailable",
            },
            Self::InvalidRequest => BridgeError {
                code: "identity_request_invalid",
                message: "Identity request is invalid",
            },
            Self::NotConfigured => BridgeError {
                code: "identity_not_configured",
                message: "Identity is not configured for this App",
            },
            Self::AuthenticationRequired => BridgeError {
                code: "identity_authentication_required",
                message: "Sign-in is required",
            },
            Self::AccessDenied => BridgeError {
                code: "identity_access_denied",
                message: "Identity authorization was denied",
            },
            Self::Unavailable => BridgeError {
                code: "identity_unavailable",
                message: "Identity provider is unavailable",
            },
            Self::SecureStorage => BridgeError {
                code: "identity_storage_unavailable",
                message: "Identity secure storage is unavailable",
            },
        }
    }
}

fn bridge_result(result: Result<Value, IdentityBridgeError>) -> String {
    match result {
        Ok(data) => json!({ "ok": true, "data": data }).to_string(),
        Err(error) => json!({ "ok": false, "error": error.payload() }).to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn unpackaged_identity_runtime_is_explicitly_not_required() {
        let directory = TempDir::new().unwrap();
        let config = json!({
            "app_data_dir": directory.path().join("files"),
            "no_backup_dir": directory.path().join("no-backup"),
            "app_package_dir": null,
            "metadata_database_path": directory.path().join("no-backup/identity/metadata.db"),
            "secret_store_dir": directory.path().join("no-backup/identity/secrets"),
            "tenant_id": "local"
        });
        let initialized = initialize_identity_runtime_json(&config.to_string(), &[7; 32]);
        let envelope: Value = serde_json::from_str(&initialized).unwrap();
        let handle = envelope["data"]["handle"].as_i64().unwrap();

        let status: Value = serde_json::from_str(&invoke_identity_runtime_json(
            handle,
            r#"{"operation":"status"}"#,
        ))
        .unwrap();
        assert_eq!(status["data"]["state"], "not_required");
        assert_eq!(status["data"]["securityContext"], Value::Null);
        assert!(close_identity_runtime(handle).contains("\"ok\":true"));
    }

    #[test]
    fn initialization_key_and_request_shape_fail_closed() {
        let directory = TempDir::new().unwrap();
        let app_data = directory.path().join("files");
        let app_package = app_data.join("package");
        std::fs::create_dir_all(&app_data).unwrap();
        copy_tree(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../examples/managed-gateway-agent"),
            &app_package,
        );
        let config = json!({
            "app_data_dir": app_data,
            "no_backup_dir": directory.path().join("no-backup"),
            "app_package_dir": app_package,
            "metadata_database_path": directory.path().join("no-backup/identity.db"),
            "secret_store_dir": directory.path().join("no-backup/secrets"),
            "tenant_id": "local"
        });
        assert!(
            initialize_identity_runtime_json(&config.to_string(), &[7; 31])
                .contains("identity_initialization_failed")
        );

        let initialized = initialize_identity_runtime_json(&config.to_string(), &[7; 32]);
        let envelope: Value = serde_json::from_str(&initialized).unwrap();
        let handle = envelope["data"]["handle"].as_i64().unwrap();
        let response =
            invoke_identity_runtime_json(handle, r#"{"operation":"status","principal":"forged"}"#);
        assert!(
            response.contains("identity_request_invalid"),
            "unexpected response: {response}"
        );
        let _ = close_identity_runtime(handle);
    }

    fn copy_tree(source: &std::path::Path, target: &std::path::Path) {
        std::fs::create_dir_all(target).unwrap();
        for entry in std::fs::read_dir(source).unwrap() {
            let entry = entry.unwrap();
            let destination = target.join(entry.file_name());
            if entry.file_type().unwrap().is_dir() {
                copy_tree(&entry.path(), &destination);
            } else {
                std::fs::copy(entry.path(), destination).unwrap();
            }
        }
    }
}
