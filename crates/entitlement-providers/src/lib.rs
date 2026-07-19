//! Replaceable entitlement providers for the AgentWeave runtime contract.
//!
//! The providers in this crate are host infrastructure. They are not model-callable tools and
//! deliberately have no representation for model-provider, Stripe, or other upstream secrets in
//! their serializable configuration.

mod clock;
mod descriptor;
mod devkit_descriptor;
mod error;
mod gateway_projection;
mod http_provider;
mod memory_ledger;
mod static_provider;
mod stripe_projection;

pub use clock::*;
pub use descriptor::*;
pub use devkit_descriptor::*;
pub use error::*;
pub use gateway_projection::*;
pub use http_provider::*;
pub use static_provider::*;
pub use stripe_projection::*;
