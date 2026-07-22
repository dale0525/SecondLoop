use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum BudgetLimit {
    Unlimited,
    Limited { value: u64 },
}

impl BudgetLimit {
    pub fn from_project_value(value: u64) -> Self {
        if value == 0 {
            Self::Unlimited
        } else {
            Self::Limited { value }
        }
    }

    pub fn validate(&self) -> Result<(), CommerceStateError> {
        match self {
            Self::Unlimited => Ok(()),
            Self::Limited { value } if *value > 0 => Ok(()),
            Self::Limited { .. } => Err(CommerceStateError::InvalidLimit),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlanLimits {
    pub requests: BudgetLimit,
    pub units: BudgetLimit,
    pub concurrency: BudgetLimit,
}

impl PlanLimits {
    pub fn validate(&self) -> Result<(), CommerceStateError> {
        self.requests.validate()?;
        self.units.validate()?;
        self.concurrency.validate()
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SubscriptionStatus {
    Trialing,
    Active,
    ScheduledCancel,
    PastDue,
    Paused,
    Canceled,
    Expired,
    Unpaid,
    Refunded,
    Disputed,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SubscriptionFact {
    pub provider_subscription_id: String,
    pub provider_customer_id: String,
    pub product_id: String,
    pub plan_id: String,
    pub status: SubscriptionStatus,
    pub period_start_unix_ms: Option<i64>,
    pub period_end_unix_ms: Option<i64>,
    pub paid_through_unix_ms: Option<i64>,
    pub provider_updated_at_unix_ms: i64,
    pub revoked_at_unix_ms: Option<i64>,
}

impl SubscriptionFact {
    pub fn permits_new_requests(&self, now_unix_ms: i64) -> bool {
        if self.revoked_at_unix_ms.is_some()
            || matches!(
                self.status,
                SubscriptionStatus::Expired
                    | SubscriptionStatus::Unpaid
                    | SubscriptionStatus::Refunded
                    | SubscriptionStatus::Disputed
            )
        {
            return false;
        }
        self.paid_through_unix_ms
            .is_some_and(|paid_through| now_unix_ms < paid_through)
    }
}

#[derive(Clone, Copy, Debug, thiserror::Error, Eq, PartialEq)]
pub enum CommerceStateError {
    #[error("commerce plan limit is invalid")]
    InvalidLimit,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fact(status: SubscriptionStatus) -> SubscriptionFact {
        SubscriptionFact {
            provider_subscription_id: "sub_1".into(),
            provider_customer_id: "cust_1".into(),
            product_id: "prod_1".into(),
            plan_id: "pro".into(),
            status,
            period_start_unix_ms: Some(1_000),
            period_end_unix_ms: Some(5_000),
            paid_through_unix_ms: Some(5_000),
            provider_updated_at_unix_ms: 1_000,
            revoked_at_unix_ms: None,
        }
    }

    #[test]
    fn project_zero_is_an_explicit_unlimited_limit() {
        assert_eq!(BudgetLimit::from_project_value(0), BudgetLimit::Unlimited);
        assert_eq!(
            BudgetLimit::from_project_value(42),
            BudgetLimit::Limited { value: 42 }
        );
    }

    #[test]
    fn cancellation_preserves_paid_time_but_revoke_states_do_not() {
        for status in [
            SubscriptionStatus::ScheduledCancel,
            SubscriptionStatus::PastDue,
            SubscriptionStatus::Paused,
            SubscriptionStatus::Canceled,
        ] {
            assert!(fact(status).permits_new_requests(4_999));
            assert!(!fact(status).permits_new_requests(5_000));
        }
        for status in [
            SubscriptionStatus::Expired,
            SubscriptionStatus::Unpaid,
            SubscriptionStatus::Refunded,
            SubscriptionStatus::Disputed,
        ] {
            assert!(!fact(status).permits_new_requests(2_000));
        }
    }
}
