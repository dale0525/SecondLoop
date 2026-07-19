use chrono::{DateTime, Utc};

/// Injectable wall clock used to make reservation lifetimes deterministic in host tests.
pub trait EntitlementClock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

#[derive(Clone, Copy, Debug, Default)]
pub struct SystemEntitlementClock;

impl EntitlementClock for SystemEntitlementClock {
    fn now(&self) -> DateTime<Utc> {
        Utc::now()
    }
}
