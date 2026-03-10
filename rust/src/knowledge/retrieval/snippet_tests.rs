use super::build_search_snippet;
use super::query::normalized_text_for_matching;

#[test]
fn knowledge_retrieval_build_search_snippet_centers_on_match() {
    let text = format!("{}needle {}", "prefix ".repeat(60), "suffix ".repeat(10));
    let normalized_query = normalized_text_for_matching("needle");

    let snippet = build_search_snippet(&text, &normalized_query);

    assert!(
        snippet.contains("needle"),
        "expected snippet to include match, got: {snippet}"
    );
    assert!(
        snippet.starts_with('…'),
        "expected snippet to start with ellipsis, got: {snippet}"
    );
}
