pub(crate) fn strict_attachment_citation_contract() -> &'static str {
    "Attachment citation contract (strict):\n- If a paragraph states any fact from attachment evidence, include at least one citation link in that same paragraph.\n- Allowed citation formats only:\n  1) Resource citation: [label](secondloop://attachment/<sha>)\n  2) Chunk citation: [label](secondloop://attachment/<sha>?kind=<kind>&chunk=<i>)\n- Do NOT use http/https links for citations.\n- Do NOT state attachment facts without citations. If evidence is insufficient, explicitly say so."
}

pub(crate) fn strict_message_citation_contract() -> &'static str {
    "Message citation contract (strict):\n- If a paragraph states any fact from conversation history or memory evidence, include at least one message citation link in that same paragraph.\n- Allowed message citation format only:\n  1) Message citation: [label](secondloop://message/<message_id>)\n- Always emit citations as Markdown links. Do NOT output bare secondloop:// URLs or raw message_id=... references.\n- If memory evidence is insufficient, explicitly say so."
}

pub(crate) fn build_prompt_with_actions_and_history(
    question: &str,
    contexts: &[String],
    actions: Option<&str>,
    history: Option<&str>,
    resources_catalog: Option<&str>,
) -> String {
    let mut out = String::new();
    out.push_str("You are SecondLoop, a helpful personal assistant.\n");
    out.push_str("IMPORTANT: Reply in the same language as the user's question. Ignore any configured UI language. Only switch languages if the user explicitly asks.\n");

    if let Some(history) = history {
        if !history.trim().is_empty() {
            out.push_str("\nRecent conversation (most recent last):\n");
            out.push_str(history);
        }
    }

    if !contexts.is_empty() {
        out.push_str("\nRelevant memories (quoted):\n");
        for (i, ctx) in contexts.iter().enumerate() {
            out.push_str(&format!("{}. \"{}\"\n", i + 1, ctx));
        }
    }

    if let Some(actions) = actions {
        out.push('\n');
        out.push_str(actions);
    }

    if let Some(resources_catalog) = resources_catalog {
        if !resources_catalog.trim().is_empty() {
            out.push('\n');
            out.push_str(resources_catalog);
        }
    }

    out.push('\n');
    out.push_str(strict_attachment_citation_contract());
    out.push('\n');
    out.push_str(strict_message_citation_contract());
    out.push('\n');

    out.push_str(
        "\nAnswer the user's question. If the memories are irrelevant, answer normally.\n",
    );
    out.push_str(
        "\nIf you suggest actionable todos or calendar events, append ONE machine-readable block like:\n",
    );
    out.push_str("```secondloop_actions\n");
    out.push_str("{\"version\":1,\"suggestions\":[{\"type\":\"todo\",\"title\":\"...\",\"when\":\"...\"}]}\n");
    out.push_str("```\n");
    out.push_str(
        "- `suggestions[].type` must be `todo` or `event`\n- `title` is required\n- `when` is optional natural language (do NOT compute absolute dates)\n- Omit the block entirely if you have no suggestions\n",
    );
    out.push_str("\nQuestion: ");
    out.push_str(question);
    out.push('\n');
    out
}

pub(crate) fn build_prompt(question: &str, contexts: &[String]) -> String {
    build_prompt_with_actions_and_history(question, contexts, None, None, None)
}

#[cfg(test)]
mod tests {
    use super::build_prompt;

    #[test]
    fn build_prompt_includes_message_citation_contract() {
        let prompt = build_prompt("What changed?", &[]);
        assert!(prompt.contains("secondloop://message/<message_id>"));
        assert!(prompt.contains("Do NOT output bare secondloop:// URLs"));
    }
}
