use super::*;
use crate::http::ProviderHttpResponse;
use agent_runtime::credential::SecretMaterial;
use std::collections::VecDeque;

#[derive(Default)]
struct FakeHttp {
    requests: Mutex<Vec<ProviderHttpRequest>>,
    responses: Mutex<VecDeque<ProviderHttpResponse>>,
}

#[async_trait]
impl ProviderHttpClient for FakeHttp {
    async fn execute(
        &self,
        request: ProviderHttpRequest,
        _: &SecretMaterial,
    ) -> anyhow::Result<ProviderHttpResponse> {
        self.requests.lock().unwrap().push(request);
        self.responses
            .lock()
            .unwrap()
            .pop_front()
            .ok_or_else(|| anyhow::anyhow!("missing response"))
    }
}

struct FakeCredentials;

#[async_trait]
impl ProviderCredentialSource for FakeCredentials {
    async fn access_token(
        &self,
        connector_id: &str,
        account_id: &str,
        _: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial> {
        assert_eq!(connector_id, CONTACTS_CONNECTOR_ID);
        assert_eq!(account_id, "primary");
        SecretMaterial::new("token")
    }
}

fn scope() -> ContactScope {
    ContactScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
        account_id: "primary".into(),
    }
}

fn person(value: &str, etag: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "resourceName": "people/c123",
        "etag": etag,
        "names": [{"displayName": "Alex Chen"}],
        "emailAddresses": [{"value": value, "type": "work"}],
        "phoneNumbers": [],
        "organizations": [{"name": "Example"}]
    }))
    .unwrap()
}

#[tokio::test]
async fn approved_update_preserves_resource_name_and_uses_patch() {
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().extend([
        ProviderHttpResponse {
            status: 200,
            body: person("old@example.test", "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: person("old@example.test", "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: person("old@example.test", "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: person("new@example.test", "etag-2"),
        },
    ]);
    let connector = GoogleContactsConnector::new(http.clone(), Arc::new(FakeCredentials));
    let current = connector
        .get(&scope(), "people/c123")
        .await
        .unwrap()
        .unwrap();
    let mut replacement = current.clone();
    replacement.identities[0].value = "new@example.test".into();
    let preview = connector
        .preview_update(
            &scope(),
            &current.id,
            current.version,
            replacement,
            "update-1".into(),
        )
        .await
        .unwrap();
    let result = connector
        .apply(
            &scope(),
            ApprovedContactMutation {
                preview_id: preview.preview_id,
                preview_hash: preview.preview_hash,
                approval_id: "approval-1".into(),
            },
        )
        .await
        .unwrap();
    assert_eq!(result.identities[0].value, "new@example.test");
    let requests = http.requests.lock().unwrap();
    assert_eq!(requests.last().unwrap().method, Method::PATCH);
    assert_eq!(
        requests.last().unwrap().path,
        "/v1/people/c123:updateContact"
    );
}
