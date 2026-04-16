use anyhow::{anyhow, Result};
use serde_json::Value;

pub fn cloud_gateway_reverse_geocode_url(gateway_base_url: &str) -> String {
    format!("{}/v1/geo/reverse", gateway_base_url.trim_end_matches('/'))
}

pub struct CloudGatewayGeoClient;

impl CloudGatewayGeoClient {
    pub fn new(_gateway_base_url: String, _id_token: String) -> Self {
        Self
    }

    pub fn reverse_geocode(&self, _lat: f64, _lon: f64, _lang: &str) -> Result<Value> {
        Err(anyhow!("cloud_gateway_geo_unsupported_on_wasm"))
    }
}
