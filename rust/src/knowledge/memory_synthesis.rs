use anyhow::Result;
use rusqlite::Connection;
use std::collections::BTreeMap;

use crate::crypto::decrypt_bytes;
use crate::db;
use crate::knowledge::models::GeneratedMemoryKind;
use crate::knowledge::{
    memory_dedup, ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeOriginType, KnowledgeRole,
    KnowledgeSourceKind, KnowledgeVersionSet,
};

struct GeneratedMemoryDraft {
    kind: GeneratedMemoryKind,
    facet_key: String,
    title: String,
    raw_text: String,
    created_at_ms: i64,
    updated_at_ms: i64,
    anchors: KnowledgeAnchorSet,
    source_id: Option<String>,
}

struct RawUserMessage {
    message_id: String,
    conversation_id: String,
    content: String,
    created_at_ms: i64,
    updated_at_ms: i64,
}

impl GeneratedMemoryDraft {
    fn into_document(self) -> ContentKnowledgeDocument {
        let document_id = memory_dedup::build_generated_document_id(
            self.kind,
            &self.facet_key,
            self.source_id.as_deref(),
        );
        ContentKnowledgeDocument {
            document_id,
            origin_type: KnowledgeOriginType::Generated,
            source_kind: KnowledgeSourceKind::Summary,
            role: KnowledgeRole::Summary,
            language: None,
            quality_score: 1.0,
            created_at_ms: self.created_at_ms,
            updated_at_ms: self.updated_at_ms,
            versions: KnowledgeVersionSet::current(),
            anchors: self.anchors,
            title: Some(self.title),
            summary: Some(self.raw_text.lines().next().unwrap_or_default().to_string()),
            raw_text: self.raw_text.clone(),
            normalized_text: self.raw_text,
        }
    }
}

pub fn collect_generated_memory_documents(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Vec<ContentKnowledgeDocument>> {
    let raw_messages = collect_raw_user_messages(conn, key)?;
    let mut drafts = Vec::<GeneratedMemoryDraft>::new();
    collect_preference_memories(&raw_messages, &mut drafts);
    collect_profile_memories(&raw_messages, &mut drafts);
    collect_event_memories(&raw_messages, &mut drafts);
    collect_pattern_memories(conn, key, &mut drafts)?;

    let mut merged = BTreeMap::<String, GeneratedMemoryDraft>::new();
    for draft in drafts {
        let document_id = memory_dedup::build_generated_document_id(
            draft.kind,
            &draft.facet_key,
            draft.source_id.as_deref(),
        );
        merged
            .entry(document_id)
            .and_modify(|existing| merge_generated_memory_draft(existing, &draft))
            .or_insert(draft);
    }

    Ok(merged
        .into_values()
        .map(GeneratedMemoryDraft::into_document)
        .collect())
}

fn merge_generated_memory_draft(
    existing: &mut GeneratedMemoryDraft,
    incoming: &GeneratedMemoryDraft,
) {
    use crate::knowledge::memory_dedup::MemoryMergePolicy;

    existing.created_at_ms = existing.created_at_ms.min(incoming.created_at_ms);
    match memory_dedup::merge_policy(existing.kind) {
        MemoryMergePolicy::ReplaceLatest => {
            if incoming.updated_at_ms >= existing.updated_at_ms {
                existing.title = incoming.title.clone();
                existing.raw_text = incoming.raw_text.clone();
                existing.updated_at_ms = incoming.updated_at_ms;
                existing.anchors = incoming.anchors.clone();
                existing.source_id = incoming.source_id.clone();
            }
        }
        MemoryMergePolicy::AppendOnly | MemoryMergePolicy::MergeByFacet => {
            existing.raw_text = memory_dedup::merge_lines(&existing.raw_text, &incoming.raw_text);
            existing.updated_at_ms = existing.updated_at_ms.max(incoming.updated_at_ms);
        }
    }
}

fn collect_raw_user_messages(conn: &Connection, key: &[u8; 32]) -> Result<Vec<RawUserMessage>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, conversation_id, content, created_at, updated_at
           FROM messages
           WHERE role = 'user'
             AND COALESCE(is_deleted, 0) = 0
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    let mut out = Vec::<RawUserMessage>::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let conversation_id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let updated_at_ms: i64 = row.get(4)?;
        let bytes = match decrypt_bytes(key, &content_blob, b"message.content") {
            Ok(value) => value,
            Err(_) => continue,
        };
        let content = match String::from_utf8(bytes) {
            Ok(value) => value,
            Err(_) => continue,
        };
        out.push(RawUserMessage {
            message_id,
            conversation_id,
            content,
            created_at_ms,
            updated_at_ms,
        });
    }
    Ok(out)
}

fn detect_response_language(message: &RawUserMessage, lower: &str) -> Option<&'static str> {
    let mentions_chinese = lower.contains("chinese") || message.content.contains("中文");
    let mentions_english = lower.contains("english") || message.content.contains("英文");
    let rejects_chinese = lower.contains("not in chinese")
        || lower.contains("don't answer in chinese")
        || lower.contains("do not answer in chinese")
        || message.content.contains("不要中文")
        || message.content.contains("别用中文");
    let rejects_english = lower.contains("not in english")
        || lower.contains("don't answer in english")
        || lower.contains("do not answer in english")
        || message.content.contains("不要英文")
        || message.content.contains("别用英文");

    match (mentions_chinese, mentions_english) {
        (true, false) => Some("Chinese"),
        (false, true) => Some("English"),
        (true, true) if rejects_chinese && !rejects_english => Some("English"),
        (true, true) if rejects_english && !rejects_chinese => Some("Chinese"),
        _ => None,
    }
}

fn collect_preference_memories(messages: &[RawUserMessage], out: &mut Vec<GeneratedMemoryDraft>) {
    for message in messages {
        let lower = message.content.trim().to_lowercase();
        let anchors = KnowledgeAnchorSet {
            message_id: Some(message.message_id.clone()),
            conversation_id: Some(message.conversation_id.clone()),
            section_label: Some("generated_preference".to_string()),
            ..KnowledgeAnchorSet::default()
        };

        if lower.contains("please answer in")
            || lower.contains("reply in")
            || message.content.contains("请用")
        {
            if let Some(language) = detect_response_language(message, &lower) {
                out.push(GeneratedMemoryDraft {
                    kind: GeneratedMemoryKind::Preference,
                    facet_key: "response_language".to_string(),
                    title: "Response language preference".to_string(),
                    raw_text: format!("User prefers responses in {language}."),
                    created_at_ms: message.created_at_ms,
                    updated_at_ms: message.updated_at_ms,
                    anchors: anchors.clone(),
                    source_id: Some(message.message_id.clone()),
                });
            }
        }

        if lower.contains("keep responses short")
            || lower.contains("be concise")
            || message.content.contains("简短")
            || message.content.contains("精简")
        {
            out.push(GeneratedMemoryDraft {
                kind: GeneratedMemoryKind::Preference,
                facet_key: "response_style".to_string(),
                title: "Response style preference".to_string(),
                raw_text: "User prefers concise, practical responses.".to_string(),
                created_at_ms: message.created_at_ms,
                updated_at_ms: message.updated_at_ms,
                anchors: anchors.clone(),
                source_id: Some(message.message_id.clone()),
            });
        }

        if lower.contains("bullet")
            || message.content.contains("要点")
            || message.content.contains("列表")
        {
            out.push(GeneratedMemoryDraft {
                kind: GeneratedMemoryKind::Preference,
                facet_key: "response_format".to_string(),
                title: "Response format preference".to_string(),
                raw_text: "User prefers bullet-style structure when possible.".to_string(),
                created_at_ms: message.created_at_ms,
                updated_at_ms: message.updated_at_ms,
                anchors,
                source_id: Some(message.message_id.clone()),
            });
        }
    }
}

fn collect_profile_memories(messages: &[RawUserMessage], out: &mut Vec<GeneratedMemoryDraft>) {
    for message in messages {
        let trimmed = message.content.trim();
        let lower = trimmed.to_lowercase();
        if !(lower.starts_with("i am ")
            || lower.starts_with("i'm ")
            || lower.starts_with("my name is ")
            || trimmed.starts_with("我是"))
        {
            continue;
        }
        out.push(GeneratedMemoryDraft {
            kind: GeneratedMemoryKind::Profile,
            facet_key: "self_profile".to_string(),
            title: "User profile".to_string(),
            raw_text: trimmed.to_string(),
            created_at_ms: message.created_at_ms,
            updated_at_ms: message.updated_at_ms,
            anchors: KnowledgeAnchorSet {
                message_id: Some(message.message_id.clone()),
                conversation_id: Some(message.conversation_id.clone()),
                section_label: Some("generated_profile".to_string()),
                ..KnowledgeAnchorSet::default()
            },
            source_id: Some(message.message_id.clone()),
        });
    }
}

fn collect_event_memories(messages: &[RawUserMessage], out: &mut Vec<GeneratedMemoryDraft>) {
    for message in messages {
        let lower = message.content.to_lowercase();
        if !(lower.contains("we decided")
            || lower.contains("decided to")
            || message.content.contains("决定")
            || message.content.contains("改为"))
        {
            continue;
        }
        out.push(GeneratedMemoryDraft {
            kind: GeneratedMemoryKind::Event,
            facet_key: "decision".to_string(),
            title: "Decision memory".to_string(),
            raw_text: message.content.trim().to_string(),
            created_at_ms: message.created_at_ms,
            updated_at_ms: message.updated_at_ms,
            anchors: KnowledgeAnchorSet {
                message_id: Some(message.message_id.clone()),
                conversation_id: Some(message.conversation_id.clone()),
                section_label: Some("generated_event".to_string()),
                ..KnowledgeAnchorSet::default()
            },
            source_id: Some(message.message_id.clone()),
        });
    }
}

fn collect_pattern_memories(
    conn: &Connection,
    key: &[u8; 32],
    out: &mut Vec<GeneratedMemoryDraft>,
) -> Result<()> {
    let todos = db::list_todos(conn, key)?;
    let active = todos
        .into_iter()
        .filter(|todo| todo.status != "done" && todo.status != "dismissed")
        .collect::<Vec<_>>();
    if active.len() < 2 {
        return Ok(());
    }
    let updated_at_ms = active
        .iter()
        .map(|todo| todo.updated_at_ms)
        .max()
        .unwrap_or(0);
    let lines = active
        .iter()
        .take(4)
        .map(|todo| format!("- {} [{}]", todo.title, todo.status))
        .collect::<Vec<_>>();
    out.push(GeneratedMemoryDraft {
        kind: GeneratedMemoryKind::Pattern,
        facet_key: "active_task_focus".to_string(),
        title: "Active task pattern".to_string(),
        raw_text: format!(
            "User is actively working across these task threads:\n{}",
            lines.join("\n")
        ),
        created_at_ms: 0,
        updated_at_ms,
        anchors: KnowledgeAnchorSet {
            section_label: Some("generated_pattern".to_string()),
            ..KnowledgeAnchorSet::default()
        },
        source_id: None,
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::collect_generated_memory_documents;
    use crate::db;
    use crate::knowledge::KnowledgeOriginType;

    #[test]
    fn collect_generated_memory_documents_emits_preference_memory() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [91u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "Please answer in Chinese and keep responses short.",
        )
        .expect("message");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        assert!(docs.iter().any(|doc| {
            doc.origin_type == KnowledgeOriginType::Generated
                && doc.document_id == "generated:preference:response-language"
        }));
    }

    #[test]
    fn collect_generated_memory_documents_keeps_single_language_preference_when_message_negates_other_language(
    ) {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [92u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "Please answer in English, not in Chinese.",
        )
        .expect("message");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:preference:response-language")
            .expect("language preference doc");

        assert_eq!(doc.raw_text, "User prefers responses in English.");
    }

    #[test]
    fn collect_generated_memory_documents_replaces_profile_with_latest_statement() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [93u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "I am a student.")
            .expect("first profile");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "I am a developer.")
            .expect("second profile");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:profile:self-profile")
            .expect("profile doc");

        assert_eq!(doc.raw_text, "I am a developer.");
    }
}
