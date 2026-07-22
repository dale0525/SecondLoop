use commerce_runtime::{
    CommerceEnvironment, CommerceError, SubscriptionFact, SubscriptionStatus, VerifiedWebhookEvent,
};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fmt;
use zeroize::Zeroizing;

const MAX_WEBHOOK_BYTES: usize = 256 * 1_024;

pub struct CreemWebhookSecret(Zeroizing<Vec<u8>>);

impl CreemWebhookSecret {
    pub fn new(value: impl Into<Vec<u8>>) -> Result<Self, CommerceError> {
        let value = value.into();
        if !(16..=4_096).contains(&value.len()) {
            return Err(CommerceError::InvalidRequest);
        }
        Ok(Self(Zeroizing::new(value)))
    }
}

impl fmt::Debug for CreemWebhookSecret {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("CreemWebhookSecret([REDACTED])")
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CreemSubscriptionEvent {
    pub verified: VerifiedWebhookEvent,
    pub subscription_id: String,
    pub customer_id: String,
    pub product_id: String,
    pub status: Option<SubscriptionStatus>,
    pub period_start_unix_ms: Option<i64>,
    pub period_end_unix_ms: Option<i64>,
    pub paid_event: bool,
    pub revoke_event: bool,
    pub provider_updated_at_unix_ms: i64,
    pub subject_ref: Option<String>,
    pub plan_id: Option<String>,
}

pub fn verify_creem_webhook(
    secret: &CreemWebhookSecret,
    raw_body: &[u8],
    signature: &str,
) -> Result<CreemSubscriptionEvent, CommerceError> {
    if raw_body.is_empty() || raw_body.len() > MAX_WEBHOOK_BYTES || signature.len() != 64 {
        return Err(CommerceError::InvalidWebhookSignature);
    }
    let signature = hex::decode(signature).map_err(|_| CommerceError::InvalidWebhookSignature)?;
    let mut mac = Hmac::<Sha256>::new_from_slice(&secret.0)
        .map_err(|_| CommerceError::InvalidWebhookSignature)?;
    mac.update(raw_body);
    mac.verify_slice(&signature)
        .map_err(|_| CommerceError::InvalidWebhookSignature)?;
    parse_creem_event(raw_body)
}

pub fn parse_creem_event(raw_body: &[u8]) -> Result<CreemSubscriptionEvent, CommerceError> {
    if raw_body.is_empty() || raw_body.len() > MAX_WEBHOOK_BYTES {
        return Err(CommerceError::InvalidResponse);
    }
    let envelope: WebhookEnvelope =
        serde_json::from_slice(raw_body).map_err(|_| CommerceError::InvalidResponse)?;
    normalize(envelope, raw_body)
}

pub fn reduce_subscription_event(
    event: &CreemSubscriptionEvent,
    current: Option<&SubscriptionFact>,
    mapped_plan_id: &str,
) -> Result<SubscriptionFact, CommerceError> {
    validate_id(&event.subscription_id, "sub_")?;
    validate_id(&event.customer_id, "cust_")?;
    validate_id(&event.product_id, "prod_")?;
    if mapped_plan_id.is_empty() || mapped_plan_id.len() > 128 {
        return Err(CommerceError::InvalidRequest);
    }
    if let Some(current) = current {
        if current.provider_subscription_id != event.subscription_id
            || current.provider_customer_id != event.customer_id
            || current.product_id != event.product_id
        {
            return Err(CommerceError::Conflict);
        }
        if event.provider_updated_at_unix_ms < current.provider_updated_at_unix_ms
            && !event.revoke_event
        {
            return Ok(current.clone());
        }
    }
    let status = event
        .status
        .or_else(|| current.map(|fact| fact.status))
        .ok_or(CommerceError::InvalidResponse)?;
    let mut paid_through = current.and_then(|fact| fact.paid_through_unix_ms);
    if event.paid_event || status == SubscriptionStatus::Trialing {
        let end = event
            .period_end_unix_ms
            .ok_or(CommerceError::InvalidResponse)?;
        if end <= event.provider_updated_at_unix_ms {
            return Err(CommerceError::InvalidResponse);
        }
        paid_through = Some(paid_through.map_or(end, |existing| existing.max(end)));
    }
    let revoked_at_unix_ms = if event.revoke_event
        || matches!(
            status,
            SubscriptionStatus::Expired
                | SubscriptionStatus::Unpaid
                | SubscriptionStatus::Refunded
                | SubscriptionStatus::Disputed
        ) {
        Some(event.provider_updated_at_unix_ms)
    } else {
        current.and_then(|fact| fact.revoked_at_unix_ms)
    };
    Ok(SubscriptionFact {
        provider_subscription_id: event.subscription_id.clone(),
        provider_customer_id: event.customer_id.clone(),
        product_id: event.product_id.clone(),
        plan_id: mapped_plan_id.into(),
        status,
        period_start_unix_ms: event
            .period_start_unix_ms
            .or_else(|| current.and_then(|fact| fact.period_start_unix_ms)),
        period_end_unix_ms: event
            .period_end_unix_ms
            .or_else(|| current.and_then(|fact| fact.period_end_unix_ms)),
        paid_through_unix_ms: paid_through,
        provider_updated_at_unix_ms: event.provider_updated_at_unix_ms,
        revoked_at_unix_ms,
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WebhookEnvelope {
    id: String,
    #[serde(rename = "eventType")]
    event_type: String,
    created_at: i64,
    object: Value,
}

fn normalize(
    envelope: WebhookEnvelope,
    raw_body: &[u8],
) -> Result<CreemSubscriptionEvent, CommerceError> {
    validate_id(&envelope.id, "evt_")?;
    if envelope.created_at < 0 || envelope.event_type.len() > 128 {
        return Err(CommerceError::InvalidResponse);
    }
    let object = envelope
        .object
        .as_object()
        .ok_or(CommerceError::InvalidResponse)?;
    let mode = text(object.get("mode"))?;
    let environment = mode_environment(mode)?;
    let subscription = subscription_object(object);
    let subscription_id = id_from(subscription.get("id"), "sub_")?;
    let customer_id = nested_id(subscription.get("customer"), "cust_")?;
    let product_id = nested_id(subscription.get("product"), "prod_")?;
    let status = event_status(&envelope.event_type, subscription.get("status"))?;
    let period_start_unix_ms = date_millis(subscription.get("current_period_start_date"))?;
    let period_end_unix_ms = date_millis(subscription.get("current_period_end_date"))?;
    let updated = date_millis(subscription.get("updated_at"))?.unwrap_or(envelope.created_at);
    let metadata = subscription
        .get("metadata")
        .and_then(Value::as_object)
        .or_else(|| object.get("metadata").and_then(Value::as_object));
    let subject_ref = metadata
        .and_then(|values| values.get("agentweaveSubjectRef"))
        .and_then(Value::as_str)
        .map(str::to_owned);
    let plan_id = metadata
        .and_then(|values| values.get("agentweavePlanId"))
        .and_then(Value::as_str)
        .map(str::to_owned);
    let paid_event = envelope.event_type == "subscription.paid";
    let revoke_event = matches!(
        envelope.event_type.as_str(),
        "subscription.expired" | "subscription.unpaid" | "refund.created" | "dispute.created"
    );
    let mut normalized = BTreeMap::from([
        ("subscriptionId".into(), subscription_id.clone()),
        ("customerId".into(), customer_id.clone()),
        ("productId".into(), product_id.clone()),
    ]);
    if let Some(value) = &subject_ref {
        normalized.insert("subjectRef".into(), value.clone());
    }
    if let Some(value) = &plan_id {
        normalized.insert("planId".into(), value.clone());
    }
    let verified = VerifiedWebhookEvent {
        event_id: envelope.id,
        event_type: envelope.event_type,
        environment,
        provider_created_at_unix_ms: envelope.created_at,
        body_sha256: hex::encode(Sha256::digest(raw_body)),
        normalized,
    };
    Ok(CreemSubscriptionEvent {
        verified,
        subscription_id,
        customer_id,
        product_id,
        status,
        period_start_unix_ms,
        period_end_unix_ms,
        paid_event,
        revoke_event,
        provider_updated_at_unix_ms: updated,
        subject_ref,
        plan_id,
    })
}

fn subscription_object(object: &serde_json::Map<String, Value>) -> &serde_json::Map<String, Value> {
    object
        .get("subscription")
        .and_then(Value::as_object)
        .unwrap_or(object)
}

fn nested_id(value: Option<&Value>, prefix: &str) -> Result<String, CommerceError> {
    match value {
        Some(Value::String(value)) => id_from(Some(&Value::String(value.clone())), prefix),
        Some(Value::Object(value)) => id_from(value.get("id"), prefix),
        _ => Err(CommerceError::InvalidResponse),
    }
}

fn id_from(value: Option<&Value>, prefix: &str) -> Result<String, CommerceError> {
    let value = text(value)?;
    validate_id(value, prefix)?;
    Ok(value.into())
}

fn validate_id(value: &str, prefix: &str) -> Result<(), CommerceError> {
    (value.starts_with(prefix)
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_'))
    .then_some(())
    .ok_or(CommerceError::InvalidResponse)
}

fn text(value: Option<&Value>) -> Result<&str, CommerceError> {
    value
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty() && value.len() <= 2_048)
        .ok_or(CommerceError::InvalidResponse)
}

fn mode_environment(mode: &str) -> Result<CommerceEnvironment, CommerceError> {
    match mode {
        "test" | "sandbox" | "local" => Ok(CommerceEnvironment::Test),
        "prod" => Ok(CommerceEnvironment::Production),
        _ => Err(CommerceError::InvalidResponse),
    }
}

fn event_status(
    event_type: &str,
    provider_status: Option<&Value>,
) -> Result<Option<SubscriptionStatus>, CommerceError> {
    let explicit = match event_type {
        "subscription.trialing" => Some(SubscriptionStatus::Trialing),
        "subscription.active" | "subscription.paid" | "subscription.update" => {
            provider_status.and_then(Value::as_str).and_then(map_status)
        }
        "subscription.scheduled_cancel" => Some(SubscriptionStatus::ScheduledCancel),
        "subscription.past_due" => Some(SubscriptionStatus::PastDue),
        "subscription.paused" => Some(SubscriptionStatus::Paused),
        "subscription.canceled" => Some(SubscriptionStatus::Canceled),
        "subscription.expired" => Some(SubscriptionStatus::Expired),
        "subscription.unpaid" => Some(SubscriptionStatus::Unpaid),
        "refund.created" => Some(SubscriptionStatus::Refunded),
        "dispute.created" => Some(SubscriptionStatus::Disputed),
        "checkout.completed" => None,
        _ => return Err(CommerceError::InvalidResponse),
    };
    Ok(explicit)
}

fn map_status(value: &str) -> Option<SubscriptionStatus> {
    match value {
        "trialing" => Some(SubscriptionStatus::Trialing),
        "active" => Some(SubscriptionStatus::Active),
        "scheduled_cancel" => Some(SubscriptionStatus::ScheduledCancel),
        "past_due" => Some(SubscriptionStatus::PastDue),
        "paused" => Some(SubscriptionStatus::Paused),
        "canceled" => Some(SubscriptionStatus::Canceled),
        "expired" => Some(SubscriptionStatus::Expired),
        "unpaid" => Some(SubscriptionStatus::Unpaid),
        _ => None,
    }
}

fn date_millis(value: Option<&Value>) -> Result<Option<i64>, CommerceError> {
    let Some(value) = value else { return Ok(None) };
    match value {
        Value::Number(number) => number
            .as_i64()
            .map(Some)
            .ok_or(CommerceError::InvalidResponse),
        Value::String(value) => chrono_millis(value).map(Some),
        Value::Null => Ok(None),
        _ => Err(CommerceError::InvalidResponse),
    }
}

fn chrono_millis(value: &str) -> Result<i64, CommerceError> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|timestamp| timestamp.timestamp_millis())
        .map_err(|_| CommerceError::InvalidResponse)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn signed(body: &[u8]) -> (CreemWebhookSecret, String) {
        let secret = CreemWebhookSecret::new(b"webhook-secret-sentinel".to_vec()).unwrap();
        let mut mac = Hmac::<Sha256>::new_from_slice(b"webhook-secret-sentinel").unwrap();
        mac.update(body);
        (secret, hex::encode(mac.finalize().into_bytes()))
    }

    fn event(event_type: &str, status: &str, end: &str) -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "id": "evt_123",
            "eventType": event_type,
            "created_at": 1_800_000_000_000_i64,
            "object": {
                "id": "sub_123", "mode": "test", "status": status,
                "customer": "cust_123", "product": "prod_123",
                "current_period_start_date": "2027-01-01T00:00:00Z",
                "current_period_end_date": end,
                "updated_at": "2027-01-01T00:00:00Z",
                "metadata": {"agentweaveSubjectRef": "v1_subject", "agentweavePlanId": "pro"}
            }
        }))
        .unwrap()
    }

    #[test]
    fn raw_body_signature_and_paid_through_are_enforced() {
        let body = event("subscription.paid", "active", "2027-02-01T00:00:00Z");
        let (secret, signature) = signed(&body);
        let event = verify_creem_webhook(&secret, &body, &signature).unwrap();
        let fact = reduce_subscription_event(&event, None, "pro").unwrap();
        assert!(fact.paid_through_unix_ms.is_some());
        assert!(fact.permits_new_requests(fact.paid_through_unix_ms.unwrap() - 1));
        assert!(!fact.permits_new_requests(fact.paid_through_unix_ms.unwrap()));
        assert_eq!(
            verify_creem_webhook(&secret, b"{}", &signature),
            Err(CommerceError::InvalidWebhookSignature)
        );
    }

    #[test]
    fn scheduled_cancel_preserves_paid_time_and_refund_revokes_immediately() {
        let paid_body = event("subscription.paid", "active", "2027-02-01T00:00:00Z");
        let (secret, signature) = signed(&paid_body);
        let paid = verify_creem_webhook(&secret, &paid_body, &signature).unwrap();
        let current = reduce_subscription_event(&paid, None, "pro").unwrap();

        let cancel_body = event(
            "subscription.scheduled_cancel",
            "scheduled_cancel",
            "2027-02-01T00:00:00Z",
        );
        let (secret, signature) = signed(&cancel_body);
        let cancel = verify_creem_webhook(&secret, &cancel_body, &signature).unwrap();
        let canceled = reduce_subscription_event(&cancel, Some(&current), "pro").unwrap();
        assert_eq!(canceled.paid_through_unix_ms, current.paid_through_unix_ms);
        assert!(canceled.permits_new_requests(current.paid_through_unix_ms.unwrap() - 1));

        let refund_body = event("refund.created", "active", "2027-02-01T00:00:00Z");
        let (secret, signature) = signed(&refund_body);
        let refund = verify_creem_webhook(&secret, &refund_body, &signature).unwrap();
        let refunded = reduce_subscription_event(&refund, Some(&current), "pro").unwrap();
        assert!(!refunded.permits_new_requests(1_800_000_000_001));
        assert_eq!(refunded.status, SubscriptionStatus::Refunded);
    }
}
