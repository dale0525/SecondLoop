use crate::secret::SecretValue;
use async_trait::async_trait;
use std::{fmt, time::Duration};
use url::Url;
use zeroize::Zeroizing;

const MAX_HTTP_BODY_BYTES: usize = 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OidcHttpMethod {
    Get,
    PostForm,
}

struct FormField {
    name: &'static str,
    value: SecretValue,
}

/// A request whose form values are redacted and cannot be serialized.
pub struct OidcHttpRequest {
    method: OidcHttpMethod,
    url: Url,
    form: Vec<FormField>,
}

impl OidcHttpRequest {
    pub(crate) fn get(url: Url) -> Self {
        Self {
            method: OidcHttpMethod::Get,
            url,
            form: Vec::new(),
        }
    }

    pub(crate) fn post_form(url: Url, form: Vec<(&'static str, SecretValue)>) -> Self {
        Self {
            method: OidcHttpMethod::PostForm,
            url,
            form: form
                .into_iter()
                .map(|(name, value)| FormField { name, value })
                .collect(),
        }
    }

    pub fn method(&self) -> OidcHttpMethod {
        self.method
    }

    pub fn url(&self) -> &Url {
        &self.url
    }

    pub fn form_field_names(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.form.iter().map(|field| field.name)
    }

    #[cfg(test)]
    pub(crate) fn form_value(&self, name: &str) -> Option<&str> {
        self.form
            .iter()
            .find(|field| field.name == name)
            .map(|field| field.value.expose_secret())
    }
}

impl fmt::Debug for OidcHttpRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OidcHttpRequest")
            .field("method", &self.method)
            .field("url", &self.url)
            .field(
                "form_fields",
                &self.form.iter().map(|field| field.name).collect::<Vec<_>>(),
            )
            .finish()
    }
}

/// A response body may contain bearer credentials, so its `Debug` output is
/// always redacted and the type has no serialization implementation.
pub struct OidcHttpResponse {
    status: u16,
    final_url: Url,
    body: Zeroizing<Vec<u8>>,
}

impl OidcHttpResponse {
    pub fn new(status: u16, final_url: Url, body: Vec<u8>) -> Self {
        Self {
            status,
            final_url,
            body: Zeroizing::new(body),
        }
    }

    pub fn status(&self) -> u16 {
        self.status
    }

    pub fn final_url(&self) -> &Url {
        &self.final_url
    }

    pub(crate) fn body(&self) -> &[u8] {
        self.body.as_slice()
    }
}

impl fmt::Debug for OidcHttpResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OidcHttpResponse")
            .field("status", &self.status)
            .field("final_url", &self.final_url)
            .field("body", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OidcHttpError;

#[async_trait]
pub trait OidcHttpClient: Send + Sync {
    /// Implementations must not follow redirects. The provider also verifies
    /// that `final_url` exactly matches the pinned request URL.
    async fn send(
        &self,
        request: OidcHttpRequest,
    ) -> std::result::Result<OidcHttpResponse, OidcHttpError>;
}

/// A production HTTP adapter with redirects disabled and bounded responses.
pub struct ReqwestOidcHttpClient {
    client: reqwest::Client,
}

impl ReqwestOidcHttpClient {
    pub fn new() -> std::result::Result<Self, OidcHttpError> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(20))
            .build()
            .map_err(|_| OidcHttpError)?;
        Ok(Self { client })
    }
}

#[async_trait]
impl OidcHttpClient for ReqwestOidcHttpClient {
    async fn send(
        &self,
        request: OidcHttpRequest,
    ) -> std::result::Result<OidcHttpResponse, OidcHttpError> {
        let expected_url = request.url.clone();
        let builder = match request.method {
            OidcHttpMethod::Get => self.client.get(request.url),
            OidcHttpMethod::PostForm => {
                let fields = request
                    .form
                    .iter()
                    .map(|field| (field.name, field.value.expose_secret()))
                    .collect::<Vec<_>>();
                self.client.post(request.url).form(&fields)
            }
        };
        let response = builder.send().await.map_err(|_| OidcHttpError)?;
        let status = response.status().as_u16();
        let final_url = response.url().clone();
        if final_url != expected_url
            || response
                .content_length()
                .is_some_and(|length| length > MAX_HTTP_BODY_BYTES as u64)
        {
            return Err(OidcHttpError);
        }
        let body = response.bytes().await.map_err(|_| OidcHttpError)?;
        if body.len() > MAX_HTTP_BODY_BYTES {
            return Err(OidcHttpError);
        }
        Ok(OidcHttpResponse::new(status, final_url, body.to_vec()))
    }
}
