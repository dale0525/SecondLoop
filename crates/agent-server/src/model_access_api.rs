use crate::api::{ApiError, AppState};

pub(crate) fn validate_model_override(state: &AppState, requested: bool) -> Result<(), ApiError> {
    if requested && !state.allows_user_model_configuration() {
        return Err(ApiError::BadRequest(
            "model settings are managed by the Agent App",
        ));
    }
    Ok(())
}
