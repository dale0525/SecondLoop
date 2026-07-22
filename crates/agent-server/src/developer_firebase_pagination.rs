use crate::developer_firebase_models::{internal, remote_protocol};
use agent_devkit::DevkitResult;
use std::collections::BTreeSet;
use url::Url;

pub(crate) fn paginated_url(
    base_url: &str,
    fixed_query: &[(&str, &str)],
    page_token: Option<&str>,
) -> DevkitResult<String> {
    let mut url = Url::parse(base_url).map_err(|_| internal())?;
    {
        let mut query = url.query_pairs_mut();
        for (name, value) in fixed_query {
            query.append_pair(name, value);
        }
        if let Some(token) = page_token {
            query.append_pair("pageToken", token);
        }
    }
    Ok(url.into())
}

pub(crate) fn checked_next_page_token(
    token: Option<String>,
    seen: &mut BTreeSet<String>,
) -> DevkitResult<Option<String>> {
    match token {
        Some(token)
            if token.is_empty()
                || token.len() > 4096
                || token.chars().any(char::is_control)
                || !seen.insert(token.clone()) =>
        {
            Err(remote_protocol())
        }
        value => Ok(value),
    }
}
