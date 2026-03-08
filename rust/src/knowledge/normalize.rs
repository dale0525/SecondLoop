use crate::knowledge::KnowledgeSourceKind;

fn collapse_spaces(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn title_case_ascii_words(value: &str) -> String {
    value
        .split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            let Some(first) = chars.next() else {
                return String::new();
            };
            let mut out = String::new();
            out.extend(first.to_uppercase());
            out.push_str(&chars.as_str().to_ascii_lowercase());
            out
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn normalize_transcript_line(line: &str) -> String {
    let trimmed = collapse_spaces(line.trim());
    if trimmed.is_empty() {
        return String::new();
    }

    let mut working = trimmed.as_str();
    let mut prefix = String::new();
    if let Some(rest) = working.strip_prefix('[') {
        if let Some(close_idx) = rest.find(']') {
            prefix = format!("[{}] ", rest[..close_idx].trim());
            working = rest[close_idx + 1..].trim();
        }
    }

    if let Some(colon_idx) = working.find(':') {
        let maybe_speaker = working[..colon_idx].trim();
        let content = working[colon_idx + 1..].trim();
        if !maybe_speaker.is_empty() && !content.is_empty() {
            return format!(
                "{}{}: {}",
                prefix,
                title_case_ascii_words(maybe_speaker),
                content
            );
        }
    }

    format!("{prefix}{working}")
}

pub fn normalize_text_for_source(source_kind: KnowledgeSourceKind, text: &str) -> String {
    let normalized_newlines = text.replace("\r\n", "\n").replace('\r', "\n");
    let lines = normalized_newlines
        .split('\n')
        .map(|line| match source_kind {
            KnowledgeSourceKind::Transcript => normalize_transcript_line(line),
            KnowledgeSourceKind::Metadata => {
                if let Some(colon_idx) = line.find(':') {
                    let key = title_case_ascii_words(line[..colon_idx].trim());
                    let value = collapse_spaces(line[colon_idx + 1..].trim());
                    if key.is_empty() || value.is_empty() {
                        collapse_spaces(line.trim())
                    } else {
                        format!("{key}: {value}")
                    }
                } else {
                    collapse_spaces(line.trim())
                }
            }
            _ => collapse_spaces(line.trim()),
        })
        .collect::<Vec<_>>();

    let mut out = String::new();
    let mut blank_run = 0usize;
    for line in lines {
        if line.is_empty() {
            blank_run += 1;
            if blank_run > 1 {
                continue;
            }
        } else {
            blank_run = 0;
        }

        if !out.is_empty() {
            out.push('\n');
        }
        out.push_str(&line);
    }
    out.trim().to_string()
}
