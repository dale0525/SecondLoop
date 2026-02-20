fn push_unique_tag(out: &mut Vec<String>, seen: &mut std::collections::HashSet<String>, value: &str) {
    let normalized = normalize_tag_name(value);
    if normalized.is_empty() {
        return;
    }

    let final_value = map_to_system_key(&normalized)
        .map(std::string::ToString::to_string)
        .unwrap_or(normalized);

    if seen.insert(final_value.clone()) {
        out.push(final_value);
    }
}

fn collect_suggested_tag_values(
    value: &serde_json::Value,
    out: &mut Vec<String>,
    seen: &mut std::collections::HashSet<String>,
) {
    match value {
        serde_json::Value::Array(items) => {
            for item in items {
                collect_suggested_tag_values(item, out, seen);
            }
        }
        serde_json::Value::String(tag) => push_unique_tag(out, seen, tag),
        serde_json::Value::Object(map) => {
            for key in ["tag", "name", "label", "value", "key"] {
                let Some(tag) = map.get(key).and_then(|item| item.as_str()) else {
                    continue;
                };
                push_unique_tag(out, seen, tag);
                break;
            }
        }
        _ => {}
    }
}

fn payload_number_to_f64(value: &serde_json::Value) -> Option<f64> {
    match value {
        serde_json::Value::Number(number) => number.as_f64(),
        serde_json::Value::String(raw) => raw.trim().parse::<f64>().ok(),
        _ => None,
    }
}

fn read_confidence_from_map(
    map: &serde_json::Map<String, serde_json::Value>,
    keys: &[&str],
) -> Option<f64> {
    keys.iter()
        .find_map(|key| map.get(*key).and_then(payload_number_to_f64))
}

fn collect_semantic_high_confidence_tag_values(
    payload: &serde_json::Value,
    out: &mut Vec<String>,
    seen: &mut std::collections::HashSet<String>,
) {
    const MIN_CONFIDENCE: f64 = 0.82;

    let Some(map) = payload.as_object() else {
        return;
    };

    let domain_confidence = read_confidence_from_map(
        map,
        &[
            "domain_confidence",
            "domainConfidence",
            "domain_score",
            "domainScore",
        ],
    )
    .or_else(|| read_confidence_from_map(map, &["confidence", "score"]));
    if domain_confidence.is_some_and(|value| value >= MIN_CONFIDENCE) {
        for key in ["domain", "domain_key", "domainKey"] {
            if let Some(domain) = map.get(key).and_then(|item| item.as_str()) {
                push_unique_tag(out, seen, domain);
                break;
            }
        }
    }

    let topic_confidence = read_confidence_from_map(
        map,
        &["topic_confidence", "topicConfidence", "topic_score", "topicScore"],
    )
    .or_else(|| read_confidence_from_map(map, &["confidence", "score"]));
    if topic_confidence.is_some_and(|value| value >= MIN_CONFIDENCE) {
        if let Some(topic) = map.get("topic").and_then(|item| item.as_str()) {
            push_unique_tag(out, seen, topic);
        }
    }

    for key in ["domains", "topics"] {
        let Some(values) = map.get(key).and_then(|item| item.as_array()) else {
            continue;
        };

        for value in values {
            match value {
                serde_json::Value::String(tag) => push_unique_tag(out, seen, tag),
                serde_json::Value::Object(item) => {
                    let confidence = read_confidence_from_map(
                        item,
                        &["confidence", "score", "probability", "weight"],
                    );
                    if confidence.is_some_and(|number| number < MIN_CONFIDENCE) {
                        continue;
                    }

                    for field in ["tag", "name", "label", "value", "key"] {
                        let Some(tag) = item.get(field).and_then(|entry| entry.as_str()) else {
                            continue;
                        };
                        push_unique_tag(out, seen, tag);
                        break;
                    }
                }
                _ => {}
            }
        }
    }
}

fn collect_suggested_tags_from_payload(
    payload: &serde_json::Value,
    out: &mut Vec<String>,
    seen: &mut std::collections::HashSet<String>,
    depth: usize,
) {
    if depth > 3 || out.len() >= MAX_SUGGESTED_TAGS_PER_MESSAGE {
        return;
    }

    if let Some(tag_value) = payload.get("tag") {
        collect_suggested_tag_values(tag_value, out, seen);
    }
    if let Some(tags_value) = payload.get("tags") {
        collect_suggested_tag_values(tags_value, out, seen);
    }

    for key in [
        "suggested_tags",
        "suggestedTags",
        "tag_candidates",
        "tagCandidates",
    ] {
        if let Some(value) = payload.get(key) {
            collect_suggested_tag_values(value, out, seen);
        }
    }

    collect_semantic_high_confidence_tag_values(payload, out, seen);

    for key in [
        "semantic_parse",
        "semanticParse",
        "semantic",
        "analysis",
        "classification",
        "result",
        "metadata",
        "payload",
    ] {
        if let Some(next) = payload.get(key) {
            collect_suggested_tags_from_payload(next, out, seen, depth + 1);
        }
    }
}

pub fn list_message_suggested_tags(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
) -> Result<Vec<String>> {
    let payloads = list_message_attachment_annotation_payloads(conn, db_key, message_id)?;

    let mut out = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    for payload in &payloads {
        collect_suggested_tags_from_payload(payload, &mut out, &mut seen, 0);
        if out.len() >= MAX_SUGGESTED_TAGS_PER_MESSAGE {
            break;
        }
    }

    if out.len() < MAX_SUGGESTED_TAGS_PER_MESSAGE {
        let autofill = list_message_tag_autofill_suggested_tags(conn, message_id, 20)?;
        for candidate in autofill {
            push_unique_tag(&mut out, &mut seen, &candidate);
            if out.len() >= MAX_SUGGESTED_TAGS_PER_MESSAGE {
                break;
            }
        }
    }

    out.truncate(MAX_SUGGESTED_TAGS_PER_MESSAGE);
    Ok(out)
}
