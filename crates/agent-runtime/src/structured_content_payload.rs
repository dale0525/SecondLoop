use crate::structured_content::{validate_id, validate_public_payload};
use serde_json::{Map, Value};
use std::collections::BTreeSet;

pub(crate) const AGENTWEAVE_CARD_MIME: &str = "application/vnd.agentweave.card+json";
const A2UI_MIME_PREFIX: &str = "application/vnd.a2ui.";

pub(crate) fn supports_interactive_mime(mime_type: &str) -> bool {
    mime_type == AGENTWEAVE_CARD_MIME || mime_type.starts_with(A2UI_MIME_PREFIX)
}

pub(crate) fn validate_payload_for_mime(
    mime_type: &str,
    schema_version: &str,
    payload: &Value,
) -> anyhow::Result<()> {
    validate_public_payload(payload)?;
    if mime_type == AGENTWEAVE_CARD_MIME {
        anyhow::ensure!(
            schema_version == "1",
            "AgentWeave card schema is unsupported"
        );
        validate_agentweave_card(payload)?;
    } else if mime_type.starts_with(A2UI_MIME_PREFIX) {
        anyhow::ensure!(
            matches!(schema_version, "0.8" | "1"),
            "A2UI card schema is unsupported"
        );
        validate_a2ui_card(payload)?;
    }
    Ok(())
}

fn validate_agentweave_card(payload: &Value) -> anyhow::Result<()> {
    let card = payload
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("AgentWeave card payload must be an object"))?;
    anyhow::ensure!(
        card.keys().all(|key| matches!(
            key.as_str(),
            "title" | "summary" | "status" | "fields" | "actions" | "actionBindings"
        )),
        "AgentWeave card payload contains unknown fields"
    );
    bounded_text(card, "title", 256, true)?;
    bounded_text(card, "summary", 4_096, false)?;
    if let Some(status) = card.get("status") {
        validate_status(status, false)?;
    }
    validate_card_rows(card, "fields", &["label", "value"], 32)?;
    validate_actions(card)?;
    Ok(())
}

fn validate_a2ui_card(payload: &Value) -> anyhow::Result<()> {
    let card = payload
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("A2UI card payload must be an object"))?;
    anyhow::ensure!(
        card.keys()
            .all(|key| matches!(key.as_str(), "components" | "actions" | "actionBindings")),
        "A2UI card payload contains unknown fields"
    );
    let components = card
        .get("components")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow::anyhow!("A2UI card components are required"))?;
    anyhow::ensure!(
        !components.is_empty() && components.len() <= 64,
        "A2UI card components exceed limit"
    );
    for component in components {
        validate_a2ui_component(component)?;
    }
    validate_actions(card)?;
    Ok(())
}

fn validate_a2ui_component(value: &Value) -> anyhow::Result<()> {
    let component = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("A2UI component is invalid"))?;
    let component_type = component
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("A2UI component type is required"))?;
    match component_type {
        "text" => {
            exact_keys(component, &["type", "text", "style"], "A2UI text component")?;
            bounded_text(component, "text", 4_000, true)?;
            if let Some(style) = component.get("style") {
                anyhow::ensure!(
                    matches!(style.as_str(), Some("body" | "caption" | "heading")),
                    "A2UI text style is invalid"
                );
            }
        }
        "field" => {
            exact_keys(
                component,
                &["type", "label", "value"],
                "A2UI field component",
            )?;
            bounded_text(component, "label", 4_096, true)?;
            bounded_text(component, "value", 4_096, true)?;
        }
        "status" => validate_status(value, true)?,
        "list" => {
            exact_keys(component, &["type", "items"], "A2UI list component")?;
            let items = component
                .get("items")
                .and_then(Value::as_array)
                .ok_or_else(|| anyhow::anyhow!("A2UI list items are required"))?;
            anyhow::ensure!(
                !items.is_empty() && items.len() <= 24,
                "A2UI list items exceed limit"
            );
            for item in items {
                let text = item
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("A2UI list item is invalid"))?;
                anyhow::ensure!(
                    !text.trim().is_empty() && text.len() <= 500,
                    "A2UI list item is invalid"
                );
            }
        }
        _ => anyhow::bail!("A2UI component type is unsupported"),
    }
    Ok(())
}

fn validate_status(value: &Value, include_type: bool) -> anyhow::Result<()> {
    let status = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("card status is invalid"))?;
    let keys = if include_type {
        &["type", "label", "tone"][..]
    } else {
        &["label", "tone"][..]
    };
    exact_keys(status, keys, "card status")?;
    bounded_text(status, "label", 128, true)?;
    if let Some(tone) = status.get("tone") {
        anyhow::ensure!(
            matches!(
                tone.as_str(),
                Some("neutral" | "info" | "success" | "warning" | "danger")
            ),
            "card status tone is invalid"
        );
    }
    Ok(())
}

fn validate_actions(card: &Map<String, Value>) -> anyhow::Result<()> {
    let action_ids = if let Some(actions) = card.get("actions") {
        let actions = actions
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("card actions are invalid"))?;
        anyhow::ensure!(actions.len() <= 8, "card has too many actions");
        let mut ids = BTreeSet::new();
        for action in actions {
            let action = exact_object(action, &["id", "label", "style"], "card action")?;
            let id = bounded_text(action, "id", 255, true)?
                .ok_or_else(|| anyhow::anyhow!("card action id is required"))?;
            validate_id(id, "card action id")?;
            anyhow::ensure!(ids.insert(id), "duplicate card action id");
            bounded_text(action, "label", 128, true)?;
            if let Some(style) = action.get("style") {
                anyhow::ensure!(
                    matches!(style.as_str(), Some("primary" | "secondary" | "danger")),
                    "card action style is invalid"
                );
            }
        }
        ids
    } else {
        BTreeSet::new()
    };

    let binding_ids = if let Some(bindings) = card.get("actionBindings") {
        let bindings = bindings
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("card action bindings are invalid"))?;
        anyhow::ensure!(bindings.len() <= 8, "card has too many action bindings");
        for (action_id, binding_id) in bindings {
            validate_id(action_id, "card action id")?;
            validate_id(
                binding_id
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("card action binding is invalid"))?,
                "card action binding",
            )?;
        }
        bindings.keys().map(String::as_str).collect::<BTreeSet<_>>()
    } else {
        BTreeSet::new()
    };
    anyhow::ensure!(
        binding_ids.is_empty() || binding_ids == action_ids,
        "card actions and bindings do not match"
    );
    Ok(())
}

fn validate_card_rows(
    card: &Map<String, Value>,
    name: &str,
    keys: &[&str],
    maximum: usize,
) -> anyhow::Result<()> {
    let Some(rows) = card.get(name) else {
        return Ok(());
    };
    let rows = rows
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("card {name} are invalid"))?;
    anyhow::ensure!(rows.len() <= maximum, "card {name} exceed limit");
    for row in rows {
        let row = exact_object(row, keys, "card row")?;
        for key in keys {
            bounded_text(row, key, 4_096, true)?;
        }
    }
    Ok(())
}

fn exact_object<'a>(
    value: &'a Value,
    keys: &[&str],
    label: &str,
) -> anyhow::Result<&'a Map<String, Value>> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("{label} is invalid"))?;
    exact_keys(object, keys, label)?;
    Ok(object)
}

fn exact_keys(object: &Map<String, Value>, keys: &[&str], label: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        object.keys().all(|key| keys.contains(&key.as_str())),
        "{label} contains unknown fields"
    );
    Ok(())
}

fn bounded_text<'a>(
    object: &'a Map<String, Value>,
    key: &str,
    maximum: usize,
    required: bool,
) -> anyhow::Result<Option<&'a str>> {
    let Some(value) = object.get(key) else {
        anyhow::ensure!(!required, "card {key} is required");
        return Ok(None);
    };
    let value = value
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("card {key} is invalid"))?;
    anyhow::ensure!(
        !value.trim().is_empty() && value.len() <= maximum,
        "card {key} is invalid"
    );
    Ok(Some(value))
}
