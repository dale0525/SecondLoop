use crate::skill_policy::ActorContext;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TurnGoal {
    pub objective: String,
}

impl TurnGoal {
    pub fn new(objective: impl Into<String>) -> Self {
        Self {
            objective: objective.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TurnRequest {
    pub user_text: String,
    pub conversation_history: Vec<serde_json::Value>,
    pub goal: Option<TurnGoal>,
    pub token_budget: Option<u64>,
    pub context_budget_bytes: Option<usize>,
    pub session_id: Option<String>,
    pub turn_id: Option<String>,
    pub actor_context: ActorContext,
}

impl TurnRequest {
    pub fn new(user_text: impl Into<String>) -> Self {
        Self {
            user_text: user_text.into(),
            conversation_history: Vec::new(),
            goal: None,
            token_budget: None,
            context_budget_bytes: None,
            session_id: None,
            turn_id: None,
            actor_context: ActorContext::anonymous(),
        }
    }

    pub fn with_goal(mut self, goal: TurnGoal) -> Self {
        self.goal = Some(goal);
        self
    }

    pub fn with_conversation_history(
        mut self,
        conversation_history: Vec<serde_json::Value>,
    ) -> Self {
        self.conversation_history = conversation_history;
        self
    }

    pub fn with_token_budget(mut self, token_budget: u64) -> Self {
        self.token_budget = Some(token_budget);
        self
    }

    pub fn with_context_budget_bytes(mut self, context_budget_bytes: usize) -> Self {
        self.context_budget_bytes = Some(context_budget_bytes);
        self
    }

    pub fn with_session_id(mut self, session_id: impl Into<String>) -> Self {
        self.session_id = Some(session_id.into());
        self
    }

    pub fn with_turn_id(mut self, turn_id: impl Into<String>) -> Self {
        self.turn_id = Some(turn_id.into());
        self
    }

    pub fn with_actor_context(mut self, actor_context: ActorContext) -> Self {
        self.actor_context = actor_context;
        self
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UsageSnapshot {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub total_tokens: u64,
    pub exceeded: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BudgetPolicy {
    token_budget: Option<u64>,
    total_tokens: u64,
}

impl BudgetPolicy {
    pub fn new(token_budget: Option<u64>) -> Self {
        Self {
            token_budget,
            total_tokens: 0,
        }
    }

    pub fn record_usage(&mut self, input_tokens: u64, output_tokens: u64) -> UsageSnapshot {
        let turn_tokens = input_tokens.saturating_add(output_tokens);
        self.total_tokens = self.total_tokens.saturating_add(turn_tokens);
        UsageSnapshot {
            input_tokens,
            output_tokens,
            total_tokens: self.total_tokens,
            exceeded: self
                .token_budget
                .map(|budget| self.total_tokens > budget)
                .unwrap_or(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill_policy::{ActorContext, SkillGrant};

    #[test]
    fn budget_policy_tracks_total_tokens() {
        let mut budget = BudgetPolicy::new(Some(10));

        assert!(!budget.record_usage(3, 4).exceeded);
        let usage = budget.record_usage(2, 2);

        assert_eq!(usage.total_tokens, 11);
        assert!(usage.exceeded);
    }

    #[test]
    fn new_request_uses_anonymous_actor_without_grants() {
        let request = TurnRequest::new("inspect skills");

        assert_eq!(request.actor_context, ActorContext::anonymous());
        assert!(request.actor_context.grants.is_empty());
    }

    #[test]
    fn actor_context_builder_carries_host_identity_without_changing_grants() {
        let mut actor =
            ActorContext::owner("owner-1", [SkillGrant::Activate, SkillGrant::Activate]);
        actor.tenant_id = Some("tenant-1".into());
        actor.device_id = Some("device-1".into());

        let request = TurnRequest::new("activate skill").with_actor_context(actor.clone());

        assert_eq!(request.actor_context, actor);
        assert_eq!(request.actor_context.grants.len(), 1);
    }
}
