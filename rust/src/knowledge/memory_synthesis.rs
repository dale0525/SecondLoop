use anyhow::Result;
use rusqlite::Connection;
use std::collections::{BTreeMap, BTreeSet};

use crate::crypto::decrypt_bytes;
use crate::db;
use crate::knowledge::models::GeneratedMemoryKind;
use crate::knowledge::{
    infer_generated_memory_section, infer_memory_status, memory_dedup, ContentKnowledgeDocument,
    KnowledgeAnchorSet, KnowledgeMemoryDisplay, KnowledgeMemoryFeedback, KnowledgeOriginType,
    KnowledgeRole, KnowledgeSourceKind, KnowledgeVersionSet,
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
    source_keys: BTreeSet<String>,
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
        let title = self.title;
        let raw_text = self.raw_text;
        let summary = raw_text.lines().next().unwrap_or_default().to_string();
        let memory_feedback = KnowledgeMemoryFeedback::default();
        let memory_display =
            infer_generated_memory_section(&document_id, Some(&title), Some(&summary), &raw_text)
                .map(|section| KnowledgeMemoryDisplay {
                    section,
                    source_count: self.source_keys.len().max(1) as i64,
                    status: infer_memory_status(&document_id, self.updated_at_ms, &memory_feedback),
                });
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
            title: Some(title),
            summary: Some(summary.clone()),
            raw_text: raw_text.clone(),
            normalized_text: raw_text,
            memory_display,
            memory_feedback,
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
    existing
        .source_keys
        .extend(incoming.source_keys.iter().cloned());
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
            conversation_id: None,
            section_label: Some("generated_preference".to_string()),
            ..KnowledgeAnchorSet::default()
        };

        if lower.contains("please answer in")
            || lower.contains("please reply in")
            || lower.contains("respond in")
            || lower.contains("answer me in")
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
                    source_keys: BTreeSet::from([message.message_id.clone()]),
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
                source_keys: BTreeSet::from([message.message_id.clone()]),
            });
        }

        let requests_bullet_format = lower.contains("use bullet")
            || lower.contains("using bullet")
            || lower.contains("in bullet")
            || lower.contains("as bullet")
            || lower.contains("bullet list")
            || lower.contains("bulleted")
            || message.content.contains("用要点格式")
            || message.content.contains("用列表格式")
            || message.content.contains("用要点回答")
            || message.content.contains("用列表回答")
            || message.content.contains("按要点回答")
            || message.content.contains("按列表回答");
        if requests_bullet_format {
            out.push(GeneratedMemoryDraft {
                kind: GeneratedMemoryKind::Preference,
                facet_key: "response_format".to_string(),
                title: "Response format preference".to_string(),
                raw_text: "User prefers bullet-style structure when possible.".to_string(),
                created_at_ms: message.created_at_ms,
                updated_at_ms: message.updated_at_ms,
                anchors,
                source_id: Some(message.message_id.clone()),
                source_keys: BTreeSet::from([message.message_id.clone()]),
            });
        }
    }
}

fn looks_like_profile_statement(trimmed: &str, lower: &str) -> bool {
    if lower.starts_with("my name is ") {
        return true;
    }
    if let Some(rest) = lower
        .strip_prefix("i am ")
        .or_else(|| lower.strip_prefix("i'm "))
    {
        let identity_keywords = [
            "developer",
            "engineer",
            "student",
            "designer",
            "teacher",
            "manager",
            "founder",
            "freelancer",
            "writer",
            "doctor",
            "researcher",
            "programmer",
            "consultant",
            "lawyer",
            "nurse",
            "parent",
        ];
        return identity_keywords.iter().any(|keyword| {
            if let Some(position) = rest.find(keyword) {
                !rest[..position]
                    .split_whitespace()
                    .any(|word| matches!(word, "not" | "never" | "no"))
            } else {
                false
            }
        });
    }
    if let Some(rest) = trimmed.strip_prefix("我是") {
        let identity_keywords = [
            "学生",
            "工程师",
            "开发",
            "程序员",
            "设计师",
            "老师",
            "产品经理",
            "研究员",
            "医生",
            "律师",
            "创始人",
            "自由职业",
            "家长",
        ];
        let rest = rest.trim();
        if rest.starts_with('不') {
            return false;
        }
        return rest.starts_with("一名")
            || rest.starts_with("叫")
            || identity_keywords
                .iter()
                .any(|keyword| rest.contains(keyword));
    }
    false
}

fn collect_profile_memories(messages: &[RawUserMessage], out: &mut Vec<GeneratedMemoryDraft>) {
    for message in messages {
        let trimmed = message.content.trim();
        let lower = trimmed.to_lowercase();
        if !looks_like_profile_statement(trimmed, &lower) {
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
                conversation_id: None,
                section_label: Some("generated_profile".to_string()),
                ..KnowledgeAnchorSet::default()
            },
            source_id: Some(message.message_id.clone()),
            source_keys: BTreeSet::from([message.message_id.clone()]),
        });
    }
}

fn looks_like_decision_statement(content: &str, lower: &str) -> bool {
    lower.contains("we decided")
        || lower.contains("team decided")
        || lower.contains("it was decided")
        || content.contains("我们决定")
        || content.contains("团队决定")
        || content.contains("已决定")
        || content.contains("决定了")
}

fn collect_event_memories(messages: &[RawUserMessage], out: &mut Vec<GeneratedMemoryDraft>) {
    for message in messages {
        let lower = message.content.to_lowercase();
        if !looks_like_decision_statement(&message.content, &lower) {
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
            source_keys: BTreeSet::from([message.message_id.clone()]),
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
    let created_at_ms = active
        .iter()
        .map(|todo| todo.updated_at_ms)
        .min()
        .unwrap_or(0);
    let updated_at_ms = active
        .iter()
        .map(|todo| todo.updated_at_ms)
        .max()
        .unwrap_or(0);
    let mut recent_active = active;
    recent_active.sort_by(|left, right| right.updated_at_ms.cmp(&left.updated_at_ms));
    let lines = recent_active
        .iter()
        .take(4)
        .map(|todo| format!("- {} [{}]", todo.title, todo.status))
        .collect::<Vec<_>>();
    let source_keys = recent_active
        .iter()
        .take(4)
        .map(|todo| todo.id.clone())
        .collect::<BTreeSet<_>>();
    out.push(GeneratedMemoryDraft {
        kind: GeneratedMemoryKind::Pattern,
        facet_key: "active_task_focus".to_string(),
        title: "Active task pattern".to_string(),
        raw_text: format!(
            "User is actively working across these task threads:\n{}",
            lines.join("\n")
        ),
        created_at_ms,
        updated_at_ms,
        anchors: KnowledgeAnchorSet {
            section_label: Some("generated_pattern".to_string()),
            ..KnowledgeAnchorSet::default()
        },
        source_id: None,
        source_keys,
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

    #[test]
    fn collect_generated_memory_documents_ignores_bullet_mentions_without_format_request() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [94u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "There is no silver bullet for this problem.",
        )
        .expect("message");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        assert!(!docs
            .iter()
            .any(|doc| doc.document_id == "generated:preference:response-format"));
    }

    #[test]
    fn collect_generated_memory_documents_sets_pattern_created_at_from_active_todos() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [95u8; 32];
        let todo_a = db::upsert_todo(
            &conn,
            &key,
            "todo-pattern-a",
            "Draft roadmap",
            None,
            "open",
            None,
            None,
            None,
            None,
            None,
            None,
        )
        .expect("todo a");
        let todo_b = db::upsert_todo(
            &conn,
            &key,
            "todo-pattern-b",
            "Review launch notes",
            None,
            "in_progress",
            None,
            None,
            None,
            None,
            None,
            None,
        )
        .expect("todo b");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:pattern:active-task-focus")
            .expect("pattern doc");

        assert_eq!(
            doc.created_at_ms,
            todo_a.updated_at_ms.min(todo_b.updated_at_ms)
        );
    }

    #[test]
    fn collect_generated_memory_documents_prefers_most_recent_active_tasks_in_pattern_memory() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [102u8; 32];
        let todos = [
            ("todo-pattern-1", "Oldest task", 10),
            ("todo-pattern-2", "Second oldest task", 20),
            ("todo-pattern-3", "Middle task", 30),
            ("todo-pattern-4", "Second newest task", 40),
            ("todo-pattern-5", "Newest task", 50),
        ];
        for (id, title, updated_at_ms) in todos {
            let _ = db::upsert_todo(
                &conn, &key, id, title, None, "open", None, None, None, None, None, None,
            )
            .expect("todo");
            conn.execute(
                "UPDATE todos SET updated_at_ms = ?1 WHERE id = ?2",
                rusqlite::params![updated_at_ms, id],
            )
            .expect("set updated_at_ms");
        }

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:pattern:active-task-focus")
            .expect("pattern doc");

        assert!(doc.raw_text.contains("Newest task [open]"));
        assert!(doc.raw_text.contains("Second newest task [open]"));
        assert!(doc.raw_text.contains("Middle task [open]"));
        assert!(doc.raw_text.contains("Second oldest task [open]"));
        assert!(!doc.raw_text.contains("Oldest task [open]"));
    }

    #[test]
    fn collect_generated_memory_documents_ignores_negated_chinese_profile_statements() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [103u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "我是学生。").expect("profile");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "我是不是学生？")
            .expect("negated question");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:profile:self-profile")
            .expect("profile doc");

        assert_eq!(doc.raw_text, "我是学生。");
    }

    #[test]
    fn collect_generated_memory_documents_ignores_non_profile_i_am_sentences() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [96u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "I am a developer.")
            .expect("profile");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "I am worried the API will break.",
        )
        .expect("non-profile");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:profile:self-profile")
            .expect("profile doc");

        assert_eq!(doc.raw_text, "I am a developer.");
    }

    #[test]
    fn collect_generated_memory_documents_ignores_common_chinese_list_terms_without_format_request()
    {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [97u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "查看任务列表")
            .expect("list message");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "这个项目的要点是什么？")
            .expect("key points message");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        assert!(!docs
            .iter()
            .any(|doc| doc.document_id == "generated:preference:response-format"));
    }

    #[test]
    fn collect_generated_memory_documents_ignores_non_profile_i_am_a_phrases() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [98u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "I am a developer.")
            .expect("profile");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "I am a bit confused about the deadline.",
        )
        .expect("non-profile");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:profile:self-profile")
            .expect("profile doc");

        assert_eq!(doc.raw_text, "I am a developer.");
    }

    #[test]
    fn collect_generated_memory_documents_ignores_common_decision_phrases() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [99u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "I decided to refactor this module.",
        )
        .expect("english phrase");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "把变量名改为camelCase")
            .expect("chinese phrase");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        assert!(!docs
            .iter()
            .any(|doc| doc.document_id.starts_with("generated:event:")));
    }

    #[test]
    fn collect_generated_memory_documents_ignores_passive_reply_in_language_phrases() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [100u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(
            &conn,
            &key,
            &conv.id,
            "user",
            "I got a reply in Chinese from the API yesterday.",
        )
        .expect("message");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        assert!(!docs
            .iter()
            .any(|doc| doc.document_id == "generated:preference:response-language"));
    }

    #[test]
    fn collect_generated_memory_documents_ignores_negated_profile_statements() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let key = [101u8; 32];
        let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "I am a developer.")
            .expect("profile");
        let _ = db::insert_message(&conn, &key, &conv.id, "user", "I am not a student.")
            .expect("negated profile");

        let docs = collect_generated_memory_documents(&conn, &key).expect("collect");
        let doc = docs
            .iter()
            .find(|doc| doc.document_id == "generated:profile:self-profile")
            .expect("profile doc");

        assert_eq!(doc.raw_text, "I am a developer.");
    }
}
