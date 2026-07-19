//! Host-only contracts for configuring and deploying AgentWeave application infrastructure.
//!
//! This crate is deliberately separate from the agent data plane. Implementations must never
//! register deployment providers as model-callable tools.

pub mod authorization;
pub mod cloudflare;
pub mod deployment;
pub mod descriptor;
pub mod error;
pub mod sensitive;

pub use authorization::*;
pub use deployment::*;
pub use descriptor::*;
pub use error::*;
pub use sensitive::*;
