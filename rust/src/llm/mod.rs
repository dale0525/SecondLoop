pub mod openai;

#[derive(Clone, Debug, PartialEq)]
pub struct ChatDelta {
    pub role: Option<String>,
    pub text_delta: String,
    pub done: bool,
}
