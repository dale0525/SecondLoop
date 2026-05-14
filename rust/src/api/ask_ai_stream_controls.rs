use anyhow::Result;
use serde::Serialize;

use crate::frb_generated::StreamSink;
use crate::rag;

const ASK_AI_META_PREFIX: &str = "\u{001e}SL_META\u{001e}";
const ASK_AI_REASONING_PREFIX: &str = "\u{001e}SL_REASONING\u{001e}";
const ASK_AI_META_REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";
const ASK_AI_REASONING_DELTA_ROLE_PREFIX: &str = "secondloop_reasoning_delta:";

pub(crate) fn meta_frame_for_role(role: Option<&str>) -> Option<String> {
    let request_id = role?.strip_prefix(ASK_AI_META_REQUEST_ID_ROLE_PREFIX)?;
    if request_id.trim().is_empty() {
        return None;
    }

    #[derive(Serialize)]
    struct RequestIdMeta<'a> {
        r#type: &'static str,
        request_id: &'a str,
    }

    let payload = serde_json::to_string(&RequestIdMeta {
        r#type: "cloud_request_id",
        request_id,
    })
    .expect("request id meta json should serialize");

    Some(format!("{ASK_AI_META_PREFIX}{payload}"))
}

pub(crate) fn reasoning_frame_for_role(role: Option<&str>) -> Option<String> {
    let reasoning_delta = role?.strip_prefix(ASK_AI_REASONING_DELTA_ROLE_PREFIX)?;
    if reasoning_delta.trim().is_empty() {
        return None;
    }

    Some(format!(
        "{ASK_AI_REASONING_PREFIX}{}",
        serde_json::json!({ "text": reasoning_delta })
    ))
}

pub(crate) fn control_frame_for_role(role: Option<&str>) -> Option<String> {
    meta_frame_for_role(role).or_else(|| reasoning_frame_for_role(role))
}

pub(crate) fn emit_control_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    emit_frame_if_any(sink, control_frame_for_role(role))
}

pub(crate) fn emit_request_meta_if_any(
    sink: &StreamSink<String>,
    role: Option<&str>,
) -> Result<()> {
    emit_frame_if_any(sink, meta_frame_for_role(role))
}

pub(crate) fn emit_reasoning_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    emit_frame_if_any(sink, reasoning_frame_for_role(role))
}

fn emit_frame_if_any(sink: &StreamSink<String>, frame: Option<String>) -> Result<()> {
    let Some(frame) = frame else {
        return Ok(());
    };

    if sink.add(frame).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn control_frame_for_reasoning_role_emits_reasoning_json() {
        let frame = control_frame_for_role(Some(
            "secondloop_reasoning_delta:I should inspect \"local\" context.",
        ));

        assert_eq!(
            frame.as_deref(),
            Some("\u{001e}SL_REASONING\u{001e}{\"text\":\"I should inspect \\\"local\\\" context.\"}"),
        );
    }

    #[test]
    fn control_frame_for_request_id_role_keeps_existing_meta_contract() {
        let frame = control_frame_for_role(Some("secondloop_request_id:req_123"));

        assert_eq!(
            frame.as_deref(),
            Some(
                "\u{001e}SL_META\u{001e}{\"type\":\"cloud_request_id\",\"request_id\":\"req_123\"}"
            ),
        );
    }

    #[test]
    fn control_frame_for_normal_assistant_role_is_none() {
        assert_eq!(control_frame_for_role(Some("assistant")), None);
    }
}
