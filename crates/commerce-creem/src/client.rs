use async_trait::async_trait;
use commerce_runtime::{
    CheckoutSession, CommerceEnvironment, CommerceError, CommerceProduct, CustomerPortalSession,
};
use reqwest::{Method, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fmt;
use std::sync::Arc;
use url::Url;
use zeroize::Zeroizing;

const MAX_RESPONSE_BYTES: usize = 512 * 1_024;
const MAX_PRODUCT_PAGES: u64 = 100;

pub struct CreemApiKey(Zeroizing<String>);

impl CreemApiKey {
    pub fn new(value: impl Into<String>) -> Result<Self, CommerceError> {
        let value = value.into();
        if !(16..=4_096).contains(&value.len())
            || value != value.trim()
            || value.chars().any(char::is_control)
        {
            return Err(CommerceError::InvalidRequest);
        }
        Ok(Self(Zeroizing::new(value)))
    }

    fn expose(&self) -> &str {
        self.0.as_str()
    }
}

impl fmt::Debug for CreemApiKey {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("CreemApiKey([REDACTED])")
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CreemMethod {
    Get,
    Post,
}

pub struct CreemRequest {
    pub method: CreemMethod,
    pub url: Url,
    pub headers: BTreeMap<String, String>,
    pub body: Option<Vec<u8>>,
}

impl fmt::Debug for CreemRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CreemRequest")
            .field("method", &self.method)
            .field("url", &self.url)
            .field("headers", &self.headers.keys().collect::<Vec<_>>())
            .field("body_bytes", &self.body.as_ref().map(Vec::len))
            .finish()
    }
}

#[derive(Clone, Debug)]
pub struct CreemResponse {
    pub status: u16,
    pub body: Vec<u8>,
    pub retry_after_seconds: Option<u64>,
}

#[async_trait]
pub trait CreemTransport: Send + Sync {
    async fn execute(&self, request: CreemRequest) -> Result<CreemResponse, CommerceError>;
}

pub struct ReqwestCreemTransport {
    client: reqwest::Client,
}

impl ReqwestCreemTransport {
    pub fn new() -> Result<Self, CommerceError> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(std::time::Duration::from_secs(15))
            .build()
            .map_err(|_| CommerceError::Unavailable)?;
        Ok(Self { client })
    }
}

#[async_trait]
impl CreemTransport for ReqwestCreemTransport {
    async fn execute(&self, request: CreemRequest) -> Result<CreemResponse, CommerceError> {
        let mut builder = self.client.request(
            match request.method {
                CreemMethod::Get => Method::GET,
                CreemMethod::Post => Method::POST,
            },
            request.url,
        );
        for (name, value) in request.headers {
            builder = builder.header(name, value);
        }
        if let Some(body) = request.body {
            builder = builder
                .header("content-type", "application/json")
                .body(body);
        }
        let response = builder
            .send()
            .await
            .map_err(|_| CommerceError::Unavailable)?;
        if response.status().is_redirection() {
            return Err(CommerceError::InvalidResponse);
        }
        let status = response.status().as_u16();
        let retry_after_seconds = response
            .headers()
            .get("retry-after")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse().ok());
        let body = response
            .bytes()
            .await
            .map_err(|_| CommerceError::Unavailable)?;
        if body.len() > MAX_RESPONSE_BYTES {
            return Err(CommerceError::InvalidResponse);
        }
        Ok(CreemResponse {
            status,
            body: body.to_vec(),
            retry_after_seconds,
        })
    }
}

pub struct CreemClient<T> {
    environment: CommerceEnvironment,
    api_key: CreemApiKey,
    transport: Arc<T>,
}

impl<T: CreemTransport> CreemClient<T> {
    pub fn new(environment: CommerceEnvironment, api_key: CreemApiKey, transport: Arc<T>) -> Self {
        Self {
            environment,
            api_key,
            transport,
        }
    }

    pub async fn list_products(&self) -> Result<Vec<CommerceProduct>, CommerceError> {
        let mut page = 1;
        let mut products = Vec::new();
        loop {
            if page > MAX_PRODUCT_PAGES {
                return Err(CommerceError::InvalidResponse);
            }
            let mut url = self.endpoint("v1/products/search")?;
            url.query_pairs_mut()
                .append_pair("page_number", &page.to_string())
                .append_pair("page_size", "100");
            let response: ProductListWire = self.get_json(url).await?;
            for item in response.items {
                products.push(item.into_product(self.environment)?);
            }
            match response.pagination.next_page {
                Some(next) if next > page && next <= response.pagination.total_pages => page = next,
                Some(_) => return Err(CommerceError::InvalidResponse),
                None => break,
            }
        }
        Ok(products)
    }

    pub async fn create_checkout(
        &self,
        product_id: &str,
        request_id: &str,
        success_url: &Url,
        metadata: BTreeMap<String, String>,
    ) -> Result<CheckoutSession, CommerceError> {
        self.create_checkout_for_customer(product_id, request_id, success_url, metadata, None)
            .await
    }

    pub async fn create_checkout_for_customer(
        &self,
        product_id: &str,
        request_id: &str,
        success_url: &Url,
        metadata: BTreeMap<String, String>,
        customer_id: Option<&str>,
    ) -> Result<CheckoutSession, CommerceError> {
        validate_provider_id(product_id, "prod_")?;
        validate_request_id(request_id)?;
        validate_https_url(success_url, None)?;
        if let Some(customer_id) = customer_id {
            validate_provider_id(customer_id, "cust_")?;
        }
        if metadata.is_empty()
            || metadata.len() > 16
            || metadata.iter().any(|(key, value)| {
                key.is_empty()
                    || key.len() > 128
                    || value.is_empty()
                    || value.len() > 2_048
                    || key.chars().any(char::is_control)
                    || value.chars().any(char::is_control)
            })
        {
            return Err(CommerceError::InvalidRequest);
        }
        let body = CheckoutRequestWire {
            request_id,
            product_id,
            units: 1,
            success_url: success_url.as_str(),
            metadata,
            customer: customer_id.map(|id| CheckoutCustomerWire { id }),
        };
        let response: CheckoutResponseWire = self
            .post_json(self.endpoint("v1/checkouts")?, &body)
            .await?;
        self.ensure_mode(&response.mode)?;
        let checkout_url = response
            .checkout_url
            .ok_or(CommerceError::InvalidResponse)
            .and_then(|value| trusted_creem_url(&value))?;
        validate_provider_id(&response.id, "ch_")?;
        Ok(CheckoutSession {
            checkout_id: response.id,
            checkout_url,
        })
    }

    pub async fn create_customer_portal(
        &self,
        customer_id: &str,
    ) -> Result<CustomerPortalSession, CommerceError> {
        validate_provider_id(customer_id, "cust_")?;
        let response: CustomerLinksWire = self
            .post_json(
                self.endpoint("v1/customers/billing")?,
                &serde_json::json!({"customer_id": customer_id}),
            )
            .await?;
        Ok(CustomerPortalSession {
            portal_url: trusted_creem_url(&response.customer_portal_link)?,
        })
    }

    pub async fn get_subscription(&self, subscription_id: &str) -> Result<Value, CommerceError> {
        validate_provider_id(subscription_id, "sub_")?;
        let mut url = self.endpoint("v1/subscriptions")?;
        url.query_pairs_mut()
            .append_pair("subscription_id", subscription_id);
        let value: Value = self.get_json(url).await?;
        let mode = value
            .get("mode")
            .and_then(Value::as_str)
            .ok_or(CommerceError::InvalidResponse)?;
        self.ensure_mode(mode)?;
        Ok(value)
    }

    fn endpoint(&self, path: &str) -> Result<Url, CommerceError> {
        let base = match self.environment {
            CommerceEnvironment::Test => "https://test-api.creem.io/",
            CommerceEnvironment::Production => "https://api.creem.io/",
        };
        Url::parse(base)
            .and_then(|url| url.join(path))
            .map_err(|_| CommerceError::InvalidRequest)
    }

    fn ensure_mode(&self, mode: &str) -> Result<(), CommerceError> {
        let valid = match self.environment {
            CommerceEnvironment::Test => matches!(mode, "test" | "sandbox" | "local"),
            CommerceEnvironment::Production => mode == "prod",
        };
        valid
            .then_some(())
            .ok_or(CommerceError::EnvironmentMismatch)
    }

    async fn get_json<R: for<'de> Deserialize<'de>>(&self, url: Url) -> Result<R, CommerceError> {
        self.execute_json(CreemMethod::Get, url, None).await
    }

    async fn post_json<R, B>(&self, url: Url, body: &B) -> Result<R, CommerceError>
    where
        R: for<'de> Deserialize<'de>,
        B: Serialize,
    {
        let body = serde_json::to_vec(body).map_err(|_| CommerceError::InvalidRequest)?;
        if body.len() > 64 * 1_024 {
            return Err(CommerceError::InvalidRequest);
        }
        self.execute_json(CreemMethod::Post, url, Some(body)).await
    }

    async fn execute_json<R: for<'de> Deserialize<'de>>(
        &self,
        method: CreemMethod,
        url: Url,
        body: Option<Vec<u8>>,
    ) -> Result<R, CommerceError> {
        let response = self
            .transport
            .execute(CreemRequest {
                method,
                url,
                headers: BTreeMap::from([("x-api-key".into(), self.api_key.expose().into())]),
                body,
            })
            .await?;
        match StatusCode::from_u16(response.status).map_err(|_| CommerceError::InvalidResponse)? {
            status if status.is_success() => {}
            StatusCode::TOO_MANY_REQUESTS | StatusCode::REQUEST_TIMEOUT => {
                return Err(CommerceError::Unavailable);
            }
            StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN | StatusCode::NOT_FOUND => {
                return Err(CommerceError::ProviderRejected);
            }
            status if status.is_server_error() => return Err(CommerceError::Unavailable),
            _ => return Err(CommerceError::InvalidResponse),
        }
        if response.body.is_empty() || response.body.len() > MAX_RESPONSE_BYTES {
            return Err(CommerceError::InvalidResponse);
        }
        serde_json::from_slice(&response.body).map_err(|_| CommerceError::InvalidResponse)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ProductListWire {
    items: Vec<ProductWire>,
    pagination: PaginationWire,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PaginationWire {
    total_pages: u64,
    #[allow(dead_code)]
    current_page: u64,
    next_page: Option<u64>,
    #[allow(dead_code)]
    prev_page: Option<u64>,
    #[allow(dead_code)]
    total_records: u64,
}

#[derive(Deserialize)]
struct ProductWire {
    id: String,
    mode: String,
    name: String,
    #[serde(default)]
    description: String,
    price: u64,
    currency: String,
    billing_type: String,
    billing_period: String,
    status: String,
}

impl ProductWire {
    fn into_product(self, expected: CommerceEnvironment) -> Result<CommerceProduct, CommerceError> {
        validate_provider_id(&self.id, "prod_")?;
        let environment = mode_environment(&self.mode)?;
        if environment != expected {
            return Err(CommerceError::EnvironmentMismatch);
        }
        for value in [
            self.name.as_str(),
            self.currency.as_str(),
            self.billing_type.as_str(),
            self.billing_period.as_str(),
        ] {
            if value.is_empty() || value.len() > 512 || value.chars().any(char::is_control) {
                return Err(CommerceError::InvalidResponse);
            }
        }
        Ok(CommerceProduct {
            id: self.id,
            name: self.name,
            description: self.description,
            environment,
            price_minor: self.price,
            currency: self.currency,
            billing_type: self.billing_type,
            billing_period: self.billing_period,
            active: self.status == "active",
        })
    }
}

#[derive(Serialize)]
struct CheckoutRequestWire<'a> {
    request_id: &'a str,
    product_id: &'a str,
    units: u64,
    success_url: &'a str,
    metadata: BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    customer: Option<CheckoutCustomerWire<'a>>,
}

#[derive(Serialize)]
struct CheckoutCustomerWire<'a> {
    id: &'a str,
}

#[derive(Deserialize)]
struct CheckoutResponseWire {
    id: String,
    mode: String,
    checkout_url: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CustomerLinksWire {
    customer_portal_link: String,
}

fn mode_environment(mode: &str) -> Result<CommerceEnvironment, CommerceError> {
    match mode {
        "test" | "sandbox" | "local" => Ok(CommerceEnvironment::Test),
        "prod" => Ok(CommerceEnvironment::Production),
        _ => Err(CommerceError::InvalidResponse),
    }
}

fn validate_provider_id(value: &str, prefix: &str) -> Result<(), CommerceError> {
    (value.starts_with(prefix)
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_'))
    .then_some(())
    .ok_or(CommerceError::InvalidResponse)
}

fn validate_request_id(value: &str) -> Result<(), CommerceError> {
    (!value.is_empty()
        && value.len() <= 256
        && value == value.trim()
        && !value.chars().any(char::is_control))
    .then_some(())
    .ok_or(CommerceError::InvalidRequest)
}

fn validate_https_url(url: &Url, trusted_domain: Option<&str>) -> Result<(), CommerceError> {
    let host = url.host_str().ok_or(CommerceError::InvalidResponse)?;
    let trusted =
        trusted_domain.is_none_or(|domain| host == domain || host.ends_with(&format!(".{domain}")));
    (url.scheme() == "https"
        && trusted
        && url.username().is_empty()
        && url.password().is_none()
        && url.fragment().is_none())
    .then_some(())
    .ok_or(CommerceError::InvalidResponse)
}

fn trusted_creem_url(value: &str) -> Result<Url, CommerceError> {
    let url = Url::parse(value).map_err(|_| CommerceError::InvalidResponse)?;
    validate_https_url(&url, Some("creem.io"))?;
    Ok(url)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct FakeTransport {
        responses: Mutex<Vec<CreemResponse>>,
        requests: Mutex<Vec<CreemRequest>>,
    }

    #[async_trait]
    impl CreemTransport for FakeTransport {
        async fn execute(&self, request: CreemRequest) -> Result<CreemResponse, CommerceError> {
            self.requests.lock().unwrap().push(request);
            Ok(self.responses.lock().unwrap().remove(0))
        }
    }

    fn fake_client(body: Value) -> (CreemClient<FakeTransport>, Arc<FakeTransport>) {
        let transport = Arc::new(FakeTransport {
            responses: Mutex::new(vec![CreemResponse {
                status: 200,
                body: serde_json::to_vec(&body).unwrap(),
                retry_after_seconds: None,
            }]),
            requests: Mutex::new(Vec::new()),
        });
        let client = CreemClient::new(
            CommerceEnvironment::Test,
            CreemApiKey::new("creem-test-key-sentinel").unwrap(),
            Arc::clone(&transport),
        );
        (client, transport)
    }

    #[tokio::test]
    async fn product_discovery_preserves_unsupported_one_time_products() {
        let (client, transport) = fake_client(serde_json::json!({
            "items": [{
                "id": "prod_123", "mode": "test", "name": "One time",
                "description": "Not selectable", "price": 1200, "currency": "USD",
                "billing_type": "onetime", "billing_period": "once", "status": "active"
            }],
            "pagination": {"total_records": 1, "total_pages": 1, "current_page": 1, "next_page": null, "prev_page": null}
        }));
        let products = client.list_products().await.unwrap();
        assert_eq!(products[0].billing_type, "onetime");
        let requests = transport.requests.lock().unwrap();
        assert_eq!(requests[0].url.path(), "/v1/products/search");
        assert!(!format!("{:?}", requests[0]).contains("creem-test-key-sentinel"));
    }

    #[tokio::test]
    async fn customer_portal_uses_only_the_bound_customer_and_rejects_foreign_origins() {
        let (client, transport) = fake_client(serde_json::json!({
            "customer_portal_link": "https://app.creem.io/customer/portal-token"
        }));
        let portal = client.create_customer_portal("cust_123").await.unwrap();
        assert_eq!(portal.portal_url.host_str(), Some("app.creem.io"));
        let request = &transport.requests.lock().unwrap()[0];
        assert_eq!(request.url.path(), "/v1/customers/billing");
        assert_eq!(
            serde_json::from_slice::<Value>(request.body.as_ref().unwrap()).unwrap(),
            serde_json::json!({"customer_id": "cust_123"})
        );

        let (foreign, _) = fake_client(serde_json::json!({
            "customer_portal_link": "https://attacker.example/portal-token"
        }));
        assert_eq!(
            foreign.create_customer_portal("cust_123").await,
            Err(CommerceError::InvalidResponse)
        );
    }

    #[test]
    fn api_key_debug_is_redacted() {
        let key = CreemApiKey::new("creem-test-key-sentinel").unwrap();
        assert_eq!(format!("{key:?}"), "CreemApiKey([REDACTED])");
    }
}
