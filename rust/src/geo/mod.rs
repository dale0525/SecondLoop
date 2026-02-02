use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde_json::Value;

pub fn cloud_gateway_reverse_geocode_url(gateway_base_url: &str) -> String {
    format!("{}/v1/geo/reverse", gateway_base_url.trim_end_matches('/'))
}

pub struct CloudGatewayGeoClient {
    client: Client,
    gateway_base_url: String,
    id_token: String,
}

impl CloudGatewayGeoClient {
    pub fn new(gateway_base_url: String, id_token: String) -> Self {
        Self {
            client: Client::new(),
            gateway_base_url,
            id_token,
        }
    }

    pub fn reverse_geocode(&self, lat: f64, lon: f64, lang: &str) -> Result<Value> {
        let url = cloud_gateway_reverse_geocode_url(&self.gateway_base_url);
        let resp = self
            .client
            .get(url)
            .bearer_auth(&self.id_token)
            .header("x-secondloop-purpose", "geo_reverse")
            .query(&[
                ("lat", lat.to_string()),
                ("lon", lon.to_string()),
                ("lang", lang.to_string()),
            ])
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "cloud-gateway geo reverse request failed: HTTP {status} {body}"
            ));
        }

        let body = resp.text().unwrap_or_default();
        let parsed: Value =
            serde_json::from_str(&body).map_err(|e| anyhow!("invalid geo reverse json: {e}"))?;
        Ok(parsed)
    }
}
