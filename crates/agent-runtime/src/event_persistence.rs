use crate::events::RuntimeEvent;
use crate::tools::ToolPersistence;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

pub fn project_runtime_event_for_persistence(event: &RuntimeEvent) -> anyhow::Result<Value> {
    match event {
        RuntimeEvent::ToolCallStarted {
            call_id,
            name,
            arguments,
            persistence: ToolPersistence::MetadataOnly,
        } => Ok(json!({
            "type": "tool_call_started",
            "call_id": call_id,
            "name": name,
            "persistence": ToolPersistence::MetadataOnly,
            "arguments_metadata": value_metadata(arguments)?,
        })),
        RuntimeEvent::ToolCallFinished {
            call_id,
            result,
            persistence: ToolPersistence::MetadataOnly,
        } => Ok(json!({
            "type": "tool_call_finished",
            "call_id": call_id,
            "persistence": ToolPersistence::MetadataOnly,
            "result_metadata": result_metadata(result)?,
        })),
        _ => serde_json::to_value(event).map_err(Into::into),
    }
}

fn value_metadata(value: &Value) -> anyhow::Result<Value> {
    let encoded = serde_json::to_vec(value)?;
    let mut summary = ShapeSummary::default();
    summarize_shape(value, 0, &mut summary);
    let fingerprint = shape_fingerprint(value);
    Ok(json!({
        "serialized_bytes": encoded.len(),
        "top_level_type": value_type(value),
        "node_count": summary.node_count,
        "max_depth": summary.max_depth,
        "object_fields": summary.object_fields,
        "array_items": summary.array_items,
        "shape_sha256": hex::encode(Sha256::digest(fingerprint)),
    }))
}

fn result_metadata(result: &Value) -> anyhow::Result<Value> {
    let mut metadata = value_metadata(result)?;
    let object = metadata
        .as_object_mut()
        .expect("value metadata must be an object");
    copy_bool(result, object, "ok", &["ok"]);
    copy_bool(result, object, "retryable", &["error", "retryable"]);
    copy_u64(result, object, "duration_ms", &["metadata", "duration_ms"]);
    for field in ["stdout_truncated", "stderr_truncated", "output_truncated"] {
        copy_bool(result, object, field, &["metadata", field]);
    }
    if result.get("ok").and_then(Value::as_bool) == Some(false) {
        let code = result
            .pointer("/error/code")
            .and_then(Value::as_str)
            .filter(|code| is_safe_error_code(code))
            .unwrap_or("unclassified_error");
        object.insert("error_code".into(), Value::String(code.into()));
    }
    Ok(metadata)
}

fn copy_bool(source: &Value, target: &mut Map<String, Value>, name: &str, path: &[&str]) {
    if let Some(value) = value_at_path(source, path).and_then(Value::as_bool) {
        target.insert(name.into(), Value::Bool(value));
    }
}

fn copy_u64(source: &Value, target: &mut Map<String, Value>, name: &str, path: &[&str]) {
    if let Some(value) = value_at_path(source, path).and_then(Value::as_u64) {
        target.insert(name.into(), Value::Number(value.into()));
    }
}

fn value_at_path<'a>(mut value: &'a Value, path: &[&str]) -> Option<&'a Value> {
    for segment in path {
        value = value.get(*segment)?;
    }
    Some(value)
}

fn is_safe_error_code(code: &str) -> bool {
    !code.is_empty()
        && code.len() <= 64
        && code
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
}

#[derive(Default)]
struct ShapeSummary {
    node_count: usize,
    max_depth: usize,
    object_fields: usize,
    array_items: usize,
}

fn summarize_shape(value: &Value, depth: usize, summary: &mut ShapeSummary) {
    summary.node_count += 1;
    summary.max_depth = summary.max_depth.max(depth);
    match value {
        Value::Array(values) => {
            summary.array_items += values.len();
            for value in values {
                summarize_shape(value, depth + 1, summary);
            }
        }
        Value::Object(values) => {
            summary.object_fields += values.len();
            for value in values.values() {
                summarize_shape(value, depth + 1, summary);
            }
        }
        _ => {}
    }
}

fn shape_fingerprint(value: &Value) -> Vec<u8> {
    match value {
        Value::Null => vec![b'n'],
        Value::Bool(_) => vec![b'b'],
        Value::Number(_) => vec![b'd'],
        Value::String(_) => vec![b's'],
        Value::Array(values) => {
            let mut encoded = vec![b'['];
            append_len(&mut encoded, values.len());
            for value in values {
                let child = shape_fingerprint(value);
                append_len(&mut encoded, child.len());
                encoded.extend_from_slice(&child);
            }
            encoded.push(b']');
            encoded
        }
        Value::Object(values) => {
            let mut children = values.values().map(shape_fingerprint).collect::<Vec<_>>();
            children.sort_unstable();
            let mut encoded = vec![b'{'];
            append_len(&mut encoded, children.len());
            for child in children {
                append_len(&mut encoded, child.len());
                encoded.extend_from_slice(&child);
            }
            encoded.push(b'}');
            encoded
        }
    }
}

fn append_len(encoded: &mut Vec<u8>, len: usize) {
    encoded.extend_from_slice(&u64::try_from(len).unwrap_or(u64::MAX).to_le_bytes());
}

fn value_type(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_only_started_event_drops_values_and_field_names() {
        let event = RuntimeEvent::ToolCallStarted {
            call_id: "call-sensitive".into(),
            name: "vault/read".into(),
            arguments: json!({"private-key-name": "argument-secret", "nested": [true, 7]}),
            persistence: ToolPersistence::MetadataOnly,
        };

        let projected = project_runtime_event_for_persistence(&event).unwrap();
        let encoded = projected.to_string();
        assert_eq!(projected["persistence"], "metadata_only");
        assert!(projected.get("arguments").is_none());
        assert!(!encoded.contains("argument-secret"));
        assert!(!encoded.contains("private-key-name"));
        assert_eq!(projected["arguments_metadata"]["top_level_type"], "object");
    }

    #[test]
    fn metadata_only_finished_event_keeps_bounded_envelope_metadata() {
        let event = RuntimeEvent::ToolCallFinished {
            call_id: "call-sensitive".into(),
            result: json!({
                "ok": false,
                "tool": "vault/read",
                "call_id": "call-sensitive",
                "data": null,
                "error": {
                    "code": "permission_denied",
                    "message": "result-secret",
                    "retryable": false
                },
                "metadata": {
                    "duration_ms": 12,
                    "stdout_truncated": false,
                    "stderr_truncated": false,
                    "output_truncated": true
                }
            }),
            persistence: ToolPersistence::MetadataOnly,
        };

        let projected = project_runtime_event_for_persistence(&event).unwrap();
        let encoded = projected.to_string();
        assert!(projected.get("result").is_none());
        assert!(!encoded.contains("result-secret"));
        assert_eq!(projected["result_metadata"]["ok"], false);
        assert_eq!(
            projected["result_metadata"]["error_code"],
            "permission_denied"
        );
        assert_eq!(projected["result_metadata"]["duration_ms"], 12);
        assert_eq!(projected["result_metadata"]["output_truncated"], true);
    }

    #[test]
    fn full_event_preserves_original_payload() {
        let event = RuntimeEvent::ToolCallStarted {
            call_id: "call-public".into(),
            name: "echo".into(),
            arguments: json!({"text": "public-value"}),
            persistence: ToolPersistence::Full,
        };

        assert_eq!(
            project_runtime_event_for_persistence(&event).unwrap(),
            serde_json::to_value(event).unwrap()
        );
    }

    #[test]
    fn event_missing_a_persistence_policy_fails_closed() {
        let event: RuntimeEvent = serde_json::from_value(json!({
            "type": "tool_call_started",
            "call_id": "call-legacy",
            "name": "legacy/read",
            "arguments": {"secret": "legacy-secret"}
        }))
        .unwrap();

        let projected = project_runtime_event_for_persistence(&event).unwrap();

        assert_eq!(projected["persistence"], "metadata_only");
        assert!(!projected.to_string().contains("legacy-secret"));
    }
}
