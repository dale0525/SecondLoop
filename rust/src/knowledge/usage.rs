use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct KnowledgeUsageStats {
    pub retrieve_count: i64,
    pub last_retrieved_at_ms: Option<i64>,
}

pub const DEFAULT_HALF_LIFE_DAYS: f64 = 7.0;

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(i64::MAX)
}

pub fn hotness_score(retrieve_count: i64, last_retrieved_at_ms: Option<i64>, now_ms: i64) -> f64 {
    hotness_score_with_half_life(
        retrieve_count,
        last_retrieved_at_ms,
        now_ms,
        DEFAULT_HALF_LIFE_DAYS,
    )
}

pub fn hotness_score_with_half_life(
    retrieve_count: i64,
    last_retrieved_at_ms: Option<i64>,
    now_ms: i64,
    half_life_days: f64,
) -> f64 {
    let frequency = 1.0 / (1.0 + (-(retrieve_count.max(0) as f64 + 1.0).ln()).exp());
    let Some(last_retrieved_at_ms) = last_retrieved_at_ms else {
        return 0.0;
    };
    let half_life_ms = (half_life_days.max(0.1) * 24.0 * 60.0 * 60.0 * 1000.0).max(1.0);
    let age_ms = (now_ms - last_retrieved_at_ms).max(0) as f64;
    let decay_rate = std::f64::consts::LN_2 / half_life_ms;
    let recency = (-decay_rate * age_ms).exp();
    (frequency * recency).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::{hotness_score, hotness_score_with_half_life};

    #[test]
    fn hotness_zero_when_no_timestamp() {
        assert_eq!(hotness_score(100, None, 1000), 0.0);
    }

    #[test]
    fn hotness_prefers_recent_and_frequent() {
        let now_ms = 1_800_000_000_000i64;
        let cold = hotness_score(0, Some(now_ms - 30 * 24 * 60 * 60 * 1000), now_ms);
        let hot = hotness_score(10, Some(now_ms - 60 * 60 * 1000), now_ms);
        assert!(hot > cold);
    }

    #[test]
    fn hotness_half_life_affects_decay() {
        let now_ms = 1_800_000_000_000i64;
        let ts = Some(now_ms - 14 * 24 * 60 * 60 * 1000);
        let faster = hotness_score_with_half_life(5, ts, now_ms, 7.0);
        let slower = hotness_score_with_half_life(5, ts, now_ms, 30.0);
        assert!(slower > faster);
    }
}
