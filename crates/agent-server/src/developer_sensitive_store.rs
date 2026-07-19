use agent_devkit::{
    DevkitError, DevkitErrorCode, DevkitResult, SensitiveInputHandle, SensitiveInputResolver,
    SensitiveInputStore, SensitiveValue,
};
use agent_runtime::credential::{CredentialScope, SecretId, SecretMaterial, SecretStore};
use async_trait::async_trait;
use std::fmt;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

/// Bridges developer-control-plane inputs into the encrypted Runtime SecretStore while enforcing
/// a scope that cannot overlap an Agent App end-user or connector credential scope.
pub(crate) struct DeveloperSensitiveStore {
    inner: Arc<dyn SecretStore>,
    scope: CredentialScope,
    handle_prefix: String,
    capture: Mutex<Option<Vec<SensitiveInputHandle>>>,
}

impl DeveloperSensitiveStore {
    pub(crate) fn new(inner: Arc<dyn SecretStore>, project_key: &str) -> DevkitResult<Self> {
        if project_key.len() != 64 || !project_key.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(DevkitError::invalid_configuration(
                "developer project key is invalid",
            ));
        }
        let scope = CredentialScope {
            app_id: "agentweave.developer-control-plane".into(),
            tenant_id: format!("project-{project_key}"),
            user_id: "local-developer-host".into(),
        };
        scope.validate().map_err(|_| {
            DevkitError::invalid_configuration("developer credential scope is invalid")
        })?;
        Ok(Self {
            inner,
            scope,
            handle_prefix: format!("awdev.v1.{project_key}."),
            capture: Mutex::new(None),
        })
    }

    pub(crate) fn begin_capture(&self) -> DevkitResult<()> {
        let mut capture = self.capture.lock().map_err(|_| internal_store_error())?;
        if capture.is_some() {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "a sensitive input transaction is already active",
            ));
        }
        *capture = Some(Vec::new());
        Ok(())
    }

    pub(crate) fn finish_capture(&self) -> DevkitResult<Vec<SensitiveInputHandle>> {
        self.capture
            .lock()
            .map_err(|_| internal_store_error())?
            .take()
            .ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::Internal,
                    "sensitive input transaction is unavailable",
                )
            })
    }

    pub(crate) async fn delete_handle(&self, handle: &SensitiveInputHandle) -> DevkitResult<bool> {
        let secret_id = self.secret_id(handle)?;
        self.inner
            .delete(&self.scope, &secret_id)
            .await
            .map_err(|_| secure_store_unavailable())
    }

    pub(crate) async fn delete_handles(
        &self,
        handles: impl IntoIterator<Item = SensitiveInputHandle>,
    ) -> DevkitResult<()> {
        for handle in handles {
            self.delete_handle(&handle).await?;
        }
        Ok(())
    }

    fn secret_id(&self, handle: &SensitiveInputHandle) -> DevkitResult<SecretId> {
        let reference = handle.opaque_reference();
        let value = reference.strip_prefix(&self.handle_prefix).ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::SensitiveInputUnavailable,
                "sensitive input belongs to a different developer project",
            )
        })?;
        SecretId::parse(value).map_err(|_| {
            DevkitError::new(
                DevkitErrorCode::SensitiveInputUnavailable,
                "sensitive input reference is invalid",
            )
        })
    }
}

impl fmt::Debug for DeveloperSensitiveStore {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DeveloperSensitiveStore")
            .field("scope", &"[DEVELOPER_PROJECT_SCOPE]")
            .finish_non_exhaustive()
    }
}

#[async_trait]
impl SensitiveInputResolver for DeveloperSensitiveStore {
    async fn resolve(&self, handle: &SensitiveInputHandle) -> DevkitResult<SensitiveValue> {
        let secret_id = self.secret_id(handle)?;
        let value = self
            .inner
            .load(&self.scope, &secret_id)
            .await
            .map_err(|_| secure_store_unavailable())?
            .ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::SensitiveInputUnavailable,
                    "sensitive input is unavailable",
                )
            })?;
        let bytes = value.with_exposed_bytes(<[u8]>::to_vec);
        SensitiveValue::new(bytes)
    }
}

#[async_trait]
impl SensitiveInputStore for DeveloperSensitiveStore {
    async fn store(
        &self,
        namespace: &str,
        value: SensitiveValue,
    ) -> DevkitResult<SensitiveInputHandle> {
        if namespace.is_empty() || namespace.len() > 256 || namespace.chars().any(char::is_control)
        {
            return Err(DevkitError::invalid_configuration(
                "sensitive input namespace is invalid",
            ));
        }
        let secret_id = SecretId::parse(&format!("devcp.{}", Uuid::new_v4().simple()))
            .map_err(|_| internal_store_error())?;
        let material = value.expose(|bytes| {
            SecretMaterial::new(bytes.to_vec()).map_err(|_| {
                DevkitError::invalid_configuration("sensitive input has an invalid size")
            })
        })?;
        self.inner
            .save(&self.scope, &secret_id, material)
            .await
            .map_err(|_| secure_store_unavailable())?;
        let handle = SensitiveInputHandle::from_opaque_reference(format!(
            "{}{}",
            self.handle_prefix,
            secret_id.as_str()
        ))?;
        let mut capture = self.capture.lock().map_err(|_| internal_store_error())?;
        if let Some(handles) = capture.as_mut() {
            handles.push(handle.clone());
        }
        Ok(handle)
    }
}

fn secure_store_unavailable() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::SensitiveInputUnavailable,
        "developer secure storage is unavailable",
    )
}

fn internal_store_error() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::Internal,
        "developer secure storage state is unavailable",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::credential::InMemorySecretStore;

    #[tokio::test]
    async fn handles_are_bound_to_one_developer_project_scope() {
        let inner = Arc::new(InMemorySecretStore::default());
        let first = DeveloperSensitiveStore::new(inner.clone(), &"a".repeat(64)).unwrap();
        let second = DeveloperSensitiveStore::new(inner, &"b".repeat(64)).unwrap();
        let handle = first
            .store("test", SensitiveValue::new(b"secret".to_vec()).unwrap())
            .await
            .unwrap();

        assert!(first.resolve(&handle).await.is_ok());
        assert!(second.resolve(&handle).await.is_err());
        assert!(!format!("{first:?}").contains("secret"));
    }
}
