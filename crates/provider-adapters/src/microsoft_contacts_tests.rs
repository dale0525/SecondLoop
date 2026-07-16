use super::*;
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
        scopes: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial> {
        assert_eq!(connector_id, CONTACTS_CONNECTOR_ID);
        assert_eq!(account_id, "primary");
        assert_eq!(scopes, &BTreeSet::from([CONTACTS_SCOPE.into()]));
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

fn contact_json(email: &str, change_key: &str, etag: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "id": "contact-1",
        "@odata.etag": etag,
        "changeKey": change_key,
        "displayName": "Alex Chen",
        "emailAddresses": [{"name": "Alex Chen", "address": email}],
        "businessPhones": ["+1 555 0100"],
        "homePhones": [],
        "mobilePhone": null,
        "companyName": "Example",
        "lastModifiedDateTime": Utc::now()
    }))
    .unwrap()
}

#[tokio::test]
async fn approved_update_preserves_provider_id_and_uses_if_match() {
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().extend([
        ProviderHttpResponse {
            status: 200,
            body: contact_json("old@example.test", "change-1", "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: contact_json("old@example.test", "change-1", "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: contact_json("old@example.test", "change-1", "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: contact_json("new@example.test", "change-2", "etag-2"),
        },
    ]);
    let connector = MicrosoftContactsConnector::new(http.clone(), Arc::new(FakeCredentials));
    let current = connector.get(&scope(), "contact-1").await.unwrap().unwrap();
    let mut replacement = current.clone();
    replacement.provider_id = Some("model-controlled-id".into());
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
    assert_eq!(
        preview.replacement.provider_id.as_deref(),
        Some("contact-1")
    );
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
    let patch = requests.last().unwrap();
    assert_eq!(patch.method, Method::PATCH);
    assert_eq!(patch.path, "/v1.0/me/contacts/contact%2D1");
    assert_eq!(
        patch.headers.get("If-Match").map(String::as_str),
        Some("etag-1")
    );
}

#[tokio::test]
async fn resolve_follows_only_origin_confined_graph_pages() {
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().extend([
        ProviderHttpResponse {
            status: 200,
            body: serde_json::to_vec(&json!({
                "value": [],
                "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/contacts?$skiptoken=next"
            }))
            .unwrap(),
        },
        ProviderHttpResponse {
            status: 200,
            body: serde_json::to_vec(&json!({
                "value": [serde_json::from_slice::<Value>(&contact_json("alex@example.test", "change-1", "etag-1")).unwrap()]
            }))
            .unwrap(),
        },
    ]);
    let connector = MicrosoftContactsConnector::new(http.clone(), Arc::new(FakeCredentials));
    let matches = connector.resolve(&scope(), "alex@", 10).await.unwrap();
    assert_eq!(matches.len(), 1);
    let requests = http.requests.lock().unwrap();
    assert_eq!(
        requests[1].query,
        vec![("$skiptoken".into(), "next".into())]
    );
    assert!(next_page_request("https://example.test/v1.0/me/contacts?$skiptoken=bad").is_err());
}
