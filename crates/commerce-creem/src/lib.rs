//! Creem adapter for the AgentWeave commerce contract.

mod client;
mod descriptor;
mod provider;
mod webhook;

pub use client::*;
pub use descriptor::*;
pub use provider::*;
pub use webhook::*;

pub const CREEM_PROVIDER_ID: &str = "agentweave.commerce.creem";
