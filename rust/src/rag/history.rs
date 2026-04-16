use anyhow::Result;
use rusqlite::Connection;

use crate::db;
use crate::message_citations::message_citation_link;

const DEFAULT_MAX_HISTORY_MESSAGES: usize = 6;
const DEFAULT_MAX_HISTORY_MESSAGE_CHARS: usize = 1200;

pub(super) fn format_history_line(role: &str, message_id: &str, content: &str) -> String {
    match message_citation_link(message_id) {
        Some(citation) => {
            let sep = if content.ends_with('\n') { "" } else { "\n" };
            format!("{role}: {content}{sep}{citation}\n")
        }
        None => format!("{role}: {content}\n"),
    }
}

pub(super) fn build_recent_conversation_history(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
) -> Result<Option<String>> {
    let page = db::list_messages_page(conn, key, conversation_id, None, None, 32)?;

    let mut kept = Vec::new();
    for msg in page {
        let content = msg.content.trim();
        if content.is_empty() {
            continue;
        }

        let role = match msg.role.as_str() {
            "user" => "User",
            "assistant" => "Assistant",
            other => other,
        };

        let truncated: String = content
            .chars()
            .take(DEFAULT_MAX_HISTORY_MESSAGE_CHARS)
            .collect();
        kept.push((role.to_string(), msg.id.clone(), truncated));
        if kept.len() >= DEFAULT_MAX_HISTORY_MESSAGES {
            break;
        }
    }

    if kept.is_empty() {
        return Ok(None);
    }

    kept.reverse();

    let mut out = String::new();
    for (role, message_id, content) in kept {
        out.push_str(&format_history_line(&role, &message_id, &content));
    }

    Ok(Some(out))
}

pub(super) fn build_recent_conversation_history_in_range(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Option<String>> {
    let page = db::list_messages_page(conn, key, conversation_id, None, None, 200)?;

    let mut kept = Vec::new();
    for msg in page {
        if msg.created_at_ms < start_at_ms_inclusive {
            break;
        }
        if msg.created_at_ms >= end_at_ms_exclusive {
            continue;
        }

        let content = msg.content.trim();
        if content.is_empty() {
            continue;
        }

        let role = match msg.role.as_str() {
            "user" => "User",
            "assistant" => "Assistant",
            other => other,
        };

        let truncated: String = content
            .chars()
            .take(DEFAULT_MAX_HISTORY_MESSAGE_CHARS)
            .collect();
        kept.push((role.to_string(), msg.id.clone(), truncated));
        if kept.len() >= DEFAULT_MAX_HISTORY_MESSAGES {
            break;
        }
    }

    if kept.is_empty() {
        return Ok(None);
    }

    kept.reverse();

    let mut out = String::new();
    for (role, message_id, content) in kept {
        out.push_str(&format_history_line(&role, &message_id, &content));
    }

    Ok(Some(out))
}

#[cfg(test)]
mod tests {
    use super::format_history_line;

    #[test]
    fn format_history_line_moves_citation_below_content() {
        let line = format_history_line("User", "history-1", "Project kickoff moved to Friday.");
        assert_eq!(
            line,
            "User: Project kickoff moved to Friday.\n[History](secondloop://message/history-1)\n"
        );
    }

    #[test]
    fn format_history_line_preserves_trailing_newline_before_citation() {
        let line = format_history_line("Assistant", "history-2", "Line one\n");
        assert_eq!(
            line,
            "Assistant: Line one\n[History](secondloop://message/history-2)\n"
        );
    }
}
