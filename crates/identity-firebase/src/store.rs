use crate::{FirebaseSecret, Result};
use async_trait::async_trait;
use chrono::{DateTime, Utc};

#[derive(Clone, Debug)]
pub struct FirebaseSession {
    pub subject: String,
    pub id_token: FirebaseSecret,
    pub refresh_token: FirebaseSecret,
    pub authenticated_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

#[async_trait]
pub trait FirebaseSessionStore: Send + Sync {
    async fn load_session(&self) -> Result<Option<FirebaseSession>>;
    async fn save_session(&self, session: FirebaseSession) -> Result<()>;
    async fn delete_session(&self) -> Result<()>;
}
