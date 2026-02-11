from __future__ import annotations

from typing import Any, Callable


ParseSemVerFn = Callable[[str], Any | None]
GitHubGetFn = Callable[[str], Any]


def find_latest_published_semver_tag(
    releases: list[dict[str, Any]],
    *,
    head_tag: str,
    parse_semver_tag: ParseSemVerFn,
    exclude_tag: str | None = None,
    allowed_tags: set[str] | None = None,
) -> str | None:
    parsed_head = parse_semver_tag(head_tag)
    latest: tuple[Any, str] | None = None

    for release in releases:
        if release.get("draft") is True or release.get("prerelease") is True:
            continue

        tag = str(release.get("tag_name", "")).strip()
        parsed = parse_semver_tag(tag)
        if parsed is None:
            continue
        if exclude_tag and tag == exclude_tag:
            continue
        if parsed_head is not None and parsed >= parsed_head:
            continue
        if allowed_tags is not None and tag not in allowed_tags:
            continue

        if latest is None or parsed > latest[0]:
            latest = (parsed, tag)

    return latest[1] if latest else None


def fetch_repo_releases(
    repo: str,
    *,
    github_get: GitHubGetFn,
    max_pages: int = 10,
) -> list[dict[str, Any]]:
    releases: list[dict[str, Any]] = []
    page = 1

    while page <= max_pages:
        path = f"/repos/{repo}/releases?per_page=100&page={page}"
        payload = github_get(path)

        if not isinstance(payload, list):
            if isinstance(payload, dict) and "message" in payload:
                raise RuntimeError(f"GitHub API error for {repo}: {payload.get('message')}")
            raise RuntimeError(
                f"unexpected GitHub releases response type: {type(payload).__name__}"
            )

        page_items = [item for item in payload if isinstance(item, dict)]
        releases.extend(page_items)
        if len(payload) < 100:
            break
        page += 1

    return releases
