//! Provider-neutral commerce and entitlement-policy contracts.
//!
//! Provider credentials, customer identifiers, and payment data stay behind provider or Host
//! boundaries. Runtime-facing requests are always keyed by verified AgentWeave identity facts.

mod contract;
mod state;

pub use contract::*;
pub use state::*;
