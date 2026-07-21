//! Firebase Authentication email/password identity provider for AgentWeave hosts.
//!
//! Firebase web configuration is public application metadata. End-user passwords,
//! ID tokens, and refresh tokens remain behind the trusted Host boundary.

mod client;
mod config;
mod descriptor;
mod error;
mod secret;
mod store;

pub use client::*;
pub use config::*;
pub use descriptor::*;
pub use error::*;
pub use secret::*;
pub use store::*;

#[cfg(test)]
mod tests;
