//! Generic OpenID Connect identity infrastructure for AgentWeave hosts.
//!
//! This crate implements the native-app Authorization Code flow with PKCE. It
//! deliberately keeps bearer material behind [`OidcSecretStore`] and exposes
//! only the credential-free [`agent_runtime::identity::SecurityContext`] to the
//! Agent runtime.

mod config;
mod descriptor;
mod error;
mod gateway_projection;
mod jwt;
mod persistent_store;
mod provider;
mod secret;
mod store;
mod transport;

pub use config::*;
pub use descriptor::*;
pub use error::*;
pub use gateway_projection::*;
pub use persistent_store::*;
pub use provider::*;
pub use secret::*;
pub use store::*;
pub use transport::*;

#[cfg(test)]
mod tests;
