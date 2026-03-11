use crate::knowledge::retrieval::test_support::seeded_fixture;

use super::{try_build_knowledge_contexts, Focus};

fn source_from_context(value: &str) -> Option<String> {
    let header = value
        .lines()
        .find(|line| line.trim_start().starts_with("[knowledge "))?;
    let after = header.split("source=").nth(1)?;
    let end = after
        .find(|ch: char| [' ', ']'].contains(&ch))
        .unwrap_or(after.len());
    Some(after[..end].trim().to_string())
}

#[test]
fn knowledge_ask_ai_contexts_include_transcript_and_headers() {
    let fixture = seeded_fixture();
    let contexts = try_build_knowledge_contexts(
        &fixture.conn,
        &fixture.key,
        "freeze-signal budget decision",
        6,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("contexts");

    assert!(!contexts.is_empty());
    assert!(contexts.iter().any(|ctx| ctx.contains("[knowledge layer=")));
    assert!(contexts
        .iter()
        .any(|ctx| ctx.contains("source=transcript") && ctx.contains("freeze-signal")));
    assert!(contexts
        .iter()
        .any(|ctx| ctx.contains("attachment_sha256=")));
}

#[test]
fn knowledge_ask_ai_contexts_prefer_evidence_over_metadata() {
    let fixture = seeded_fixture();
    let contexts = try_build_knowledge_contexts(
        &fixture.conn,
        &fixture.key,
        "freeze-signal budget freeze overview",
        8,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("contexts");

    assert!(!contexts.is_empty());
    let first = contexts.first().expect("first context");
    assert!(
        !first.contains("role=metadata"),
        "first context was metadata: {first}"
    );
}

#[test]
fn knowledge_ask_ai_contexts_include_multiple_sources() {
    let fixture = seeded_fixture();
    let contexts = try_build_knowledge_contexts(
        &fixture.conn,
        &fixture.key,
        "roadmap-q1 freeze-signal orchard invoice",
        10,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("contexts");

    assert!(!contexts.is_empty());

    let mut sources = Vec::<String>::new();
    for context in &contexts {
        if let Some(source) = source_from_context(context) {
            if !sources.contains(&source) {
                sources.push(source);
            }
        }
    }

    assert!(
        sources.iter().any(|source| source == "transcript"),
        "expected transcript in sources: {sources:?}"
    );
    assert!(
        sources.len() >= 2,
        "expected at least 2 sources in contexts: {sources:?}"
    );
}

#[test]
fn knowledge_ask_ai_contexts_include_message_deeplinks() {
    let fixture = seeded_fixture();
    let contexts = try_build_knowledge_contexts(
        &fixture.conn,
        &fixture.key,
        "freeze-signal budget decision",
        6,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("contexts");

    assert!(contexts
        .iter()
        .any(|ctx| ctx.contains("secondloop://message/")));
}
