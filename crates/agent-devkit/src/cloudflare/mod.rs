//! Cloudflare developer control-plane implementation.
//!
//! The transport boundary is injectable so conformance tests never require real credentials or
//! network writes. Production transports pin origins, reject redirects and return sanitized errors.

mod accounts;
mod client;
mod commerce_d1;
mod configuration;
mod d1;
mod managed_worker;
mod oauth;
mod provider;
mod provider_support;
mod schema;
mod transport;

pub use client::*;
pub use oauth::*;
pub use provider::*;
pub use schema::cloudflare_gateway_provider_descriptor;
pub use transport::*;

pub const CLOUDFLARE_PROVIDER_ID: &str = "cloudflare-workers";
pub const CLOUDFLARE_API_BASE_URL: &str = "https://api.cloudflare.com/client/v4/";
pub const CLOUDFLARE_AUTHORIZATION_URL: &str = "https://dash.cloudflare.com/oauth2/auth";
pub const CLOUDFLARE_TOKEN_URL: &str = "https://dash.cloudflare.com/oauth2/token";

#[cfg(test)]
mod conformance_tests;
