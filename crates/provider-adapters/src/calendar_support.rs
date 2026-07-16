pub(crate) const UNTITLED_EVENT_TITLE: &str = "(No title)";

pub(crate) fn normalize_provider_event_title(title: String) -> String {
    if title.trim().is_empty() {
        UNTITLED_EVENT_TITLE.into()
    } else {
        title
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_event_titles_only_replace_blank_values() {
        assert_eq!(
            normalize_provider_event_title(String::new()),
            UNTITLED_EVENT_TITLE
        );
        assert_eq!(
            normalize_provider_event_title(" \t ".into()),
            UNTITLED_EVENT_TITLE
        );
        assert_eq!(
            normalize_provider_event_title("Planning".into()),
            "Planning"
        );
    }
}
