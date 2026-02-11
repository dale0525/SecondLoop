#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import textwrap
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from scripts.release_ai_curation import curate_user_facing_changes_with_llm
    from scripts.release_ai_llm import llm_config as _llm_config
    from scripts.release_ai_llm import openai_chat_json as _openai_chat_json
    from scripts.release_ai_release_base import (
        fetch_repo_releases as _fetch_repo_releases,
    )
    from scripts.release_ai_release_base import (
        find_latest_published_semver_tag as _find_latest_published_semver_tag,
    )
    from scripts.release_ai_notes import (
        _change_links_from_facts,
        _default_maintenance_summary,
        _default_section_titles,
        _format_change_refs,
        _locale_headings,
        _select_user_facing_changes,
    )
    from scripts.release_ai_text import _extract_release_notes_section
except ModuleNotFoundError:
    from release_ai_curation import curate_user_facing_changes_with_llm
    from release_ai_llm import llm_config as _llm_config
    from release_ai_llm import openai_chat_json as _openai_chat_json
    from release_ai_release_base import fetch_repo_releases as _fetch_repo_releases
    from release_ai_release_base import (
        find_latest_published_semver_tag as _find_latest_published_semver_tag,
    )
    from release_ai_notes import (
        _change_links_from_facts,
        _default_maintenance_summary,
        _default_section_titles,
        _format_change_refs,
        _locale_headings,
        _select_user_facing_changes,
    )
    from release_ai_text import _extract_release_notes_section

SEMVER_TAG_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
PR_NUMBER_RE = re.compile(r"(?:#|pull request\s+#)(\d+)", re.IGNORECASE)
BREAKING_RE = re.compile(r"\bbreaking(?:\s+change)?\b|!:", re.IGNORECASE)
FEATURE_RE = re.compile(r"\bfeat(?:ure)?\b", re.IGNORECASE)
FIX_RE = re.compile(r"\bfix(?:es|ed)?\b|\bbug\b|\bhotfix\b", re.IGNORECASE)


@dataclass(frozen=True, order=True)
class SemVer:
    major: int
    minor: int
    patch: int

    def __str__(self) -> str:
        return f"v{self.major}.{self.minor}.{self.patch}"


def parse_semver_tag(tag: str) -> SemVer | None:
    match = SEMVER_TAG_RE.fullmatch(tag.strip())
    if not match:
        return None
    return SemVer(int(match.group(1)), int(match.group(2)), int(match.group(3)))


def find_latest_semver_tag(tags: list[str]) -> str | None:
    latest: tuple[SemVer, str] | None = None
    for tag in tags:
        parsed = parse_semver_tag(tag)
        if parsed is None:
            continue
        if latest is None or parsed > latest[0]:
            latest = (parsed, tag)
    return latest[1] if latest else None


def bump_semver(version: SemVer, bump: str) -> SemVer:
    if bump == "major":
        return SemVer(version.major + 1, 0, 0)
    if bump == "minor":
        return SemVer(version.major, version.minor + 1, 0)
    if bump == "patch":
        return SemVer(version.major, version.minor, version.patch + 1)
    raise ValueError(f"unsupported bump '{bump}'")


def classify_change(title: str, body: str, labels: list[str]) -> str:
    text = f"{title}\n{body}".strip().lower()
    lowered_labels = {label.lower() for label in labels}

    if (
        any("breaking" in label or "major" in label for label in lowered_labels)
        or BREAKING_RE.search(text)
    ):
        return "breaking"
    if any(
        marker in label
        for label in lowered_labels
        for marker in ("feature", "enhancement", "feat")
    ) or FEATURE_RE.search(text):
        return "feature"
    if any(marker in label for label in lowered_labels for marker in ("bug", "fix", "hotfix")) or FIX_RE.search(text):
        return "fix"
    return "chore"


def validate_locale_notes(
    notes: dict[str, Any],
    *,
    expected_locale: str,
    expected_version: str,
    required_change_ids: list[str],
) -> set[str]:
    if notes.get("locale") != expected_locale:
        raise ValueError(
            f"locale mismatch: expected {expected_locale}, got {notes.get('locale')}"
        )
    if notes.get("version") != expected_version:
        raise ValueError(
            f"version mismatch: expected {expected_version}, got {notes.get('version')}"
        )

    sections = notes.get("sections")
    if not isinstance(sections, list):
        raise ValueError("notes sections must be a list")
    if required_change_ids and not sections:
        raise ValueError("notes must contain non-empty sections when releasable changes exist")

    covered: set[str] = set()
    valid_ids = set(required_change_ids)
    for section in sections:
        items = section.get("items")
        if not isinstance(items, list):
            raise ValueError("section items must be a list")
        for item in items:
            text = item.get("text")
            if not isinstance(text, str) or not text.strip():
                raise ValueError("item text must be non-empty")
            change_ids = item.get("change_ids")
            if not isinstance(change_ids, list) or not change_ids:
                raise ValueError("item change_ids must be a non-empty list")
            for change_id in change_ids:
                if change_id not in valid_ids:
                    raise ValueError(f"unknown change id '{change_id}'")
                covered.add(change_id)

    missing = set(required_change_ids) - covered
    if missing:
        missing_list = ", ".join(sorted(missing))
        raise ValueError(f"missing change ids: {missing_list}")
    return covered


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def _die(message: str) -> None:
    print(f"release-ai: {message}", file=sys.stderr)
    raise SystemExit(1)


def _run_git(args: list[str]) -> str:
    cmd = ["git", *args]
    completed = subprocess.run(
        cmd,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git command failed ({' '.join(cmd)}): {completed.stderr.strip() or completed.stdout.strip()}"
        )
    return completed.stdout


def _infer_repo_slug() -> str | None:
    try:
        url = _run_git(["remote", "get-url", "origin"]).strip()
    except RuntimeError:
        return None

    https_match = re.match(r"https://github\.com/([^/]+/[^/]+?)(?:\.git)?$", url)
    if https_match:
        return https_match.group(1)

    ssh_match = re.match(r"git@github\.com:([^/]+/[^/]+?)(?:\.git)?$", url)
    if ssh_match:
        return ssh_match.group(1)
    return None


def _extract_pr_numbers(subject: str, body: str) -> list[int]:
    numbers = {int(match.group(1)) for match in PR_NUMBER_RE.finditer(f"{subject}\n{body}")}
    return sorted(numbers)


def _github_token() -> str | None:
    for key in ("GITHUB_TOKEN", "GH_TOKEN"):
        value = os.getenv(key, "").strip()
        if value:
            return value
    return None


def _github_get(path: str, *, token: str | None) -> Any:
    url = f"https://api.github.com{path}"
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "secondloop-release-ai",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(url=url, headers=headers, method="GET")
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = response.read().decode("utf-8")
    return json.loads(payload)


def _fetch_pull_request(repo: str, number: int, *, token: str | None) -> dict[str, Any] | None:
    if not repo:
        return None
    try:
        return _github_get(f"/repos/{repo}/pulls/{number}", token=token)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
        return None


def _latest_semver_before(head_ref: str, *, exclude_tag: str | None) -> str | None:
    tags = _run_git(["tag", "--merged", head_ref]).splitlines()
    semver_tags = [tag.strip() for tag in tags if parse_semver_tag(tag.strip())]
    if exclude_tag and parse_semver_tag(exclude_tag):
        semver_tags = [tag for tag in semver_tags if tag != exclude_tag]
    return find_latest_semver_tag(semver_tags)


def find_latest_published_semver_tag(
    releases: list[dict[str, Any]],
    *,
    head_tag: str,
    exclude_tag: str | None = None,
    allowed_tags: set[str] | None = None,
) -> str | None:
    return _find_latest_published_semver_tag(
        releases,
        head_tag=head_tag,
        parse_semver_tag=parse_semver_tag,
        exclude_tag=exclude_tag,
        allowed_tags=allowed_tags,
    )


def _latest_published_release_before(
    repo: str,
    head_ref: str,
    *,
    exclude_tag: str | None,
    token: str | None,
) -> str | None:
    merged_tags = _run_git(["tag", "--merged", head_ref]).splitlines()
    merged_semver_tags = {tag.strip() for tag in merged_tags if parse_semver_tag(tag.strip())}

    try:
        releases = _fetch_repo_releases(
            repo,
            github_get=lambda path: _github_get(path, token=token),
        )
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot fetch GitHub releases for {repo}: {exc}") from exc

    return find_latest_published_semver_tag(
        releases,
        head_tag=head_ref,
        exclude_tag=exclude_tag,
        allowed_tags=merged_semver_tags,
    )


def _collect_commits(range_expr: str) -> list[dict[str, str]]:
    output = _run_git([
        "log",
        "--reverse",
        "--format=%H%x1f%s%x1f%b%x1e",
        range_expr,
    ])

    commits: list[dict[str, str]] = []
    for raw_entry in output.split("\x1e"):
        entry = raw_entry.strip("\n")
        if not entry:
            continue
        parts = entry.split("\x1f")
        if len(parts) < 3:
            continue
        sha, subject, body = parts[0].strip(), parts[1].strip(), parts[2].strip()
        commits.append({"sha": sha, "subject": subject, "body": body})
    return commits


def _command_collect_facts(args: argparse.Namespace) -> None:
    head_ref = args.head_tag or args.head
    try:
        head_sha = _run_git(["rev-parse", head_ref]).strip()
    except RuntimeError as exc:
        _die(str(exc))

    repo = args.repo or _infer_repo_slug()
    token = _github_token()
    base_tag = args.base_tag
    auto_base_source = args.auto_base_source
    if base_tag == "auto":
        if auto_base_source == "github-releases":
            if not repo:
                _die("auto base source 'github-releases' requires --repo or an origin GitHub remote")
            try:
                base_tag = _latest_published_release_before(
                    repo,
                    head_ref,
                    exclude_tag=args.head_tag,
                    token=token,
                )
            except RuntimeError as exc:
                _die(str(exc))
        else:
            base_tag = _latest_semver_before(head_ref, exclude_tag=args.head_tag)

    range_expr = f"{base_tag}..{head_ref}" if base_tag else head_ref

    try:
        commits = _collect_commits(range_expr)
    except RuntimeError as exc:
        _die(str(exc))

    commit_to_prs: dict[str, list[int]] = {}
    pr_to_commits: dict[int, list[dict[str, str]]] = {}
    for commit in commits:
        pr_numbers = _extract_pr_numbers(commit["subject"], commit["body"])
        commit_to_prs[commit["sha"]] = pr_numbers
        for pr_number in pr_numbers:
            pr_to_commits.setdefault(pr_number, []).append(commit)

    changes: list[dict[str, Any]] = []
    covered_commits: set[str] = set()
    for pr_number in sorted(pr_to_commits):
        linked_commits = pr_to_commits[pr_number]
        for commit in linked_commits:
            covered_commits.add(commit["sha"])

        pull_request = _fetch_pull_request(repo, pr_number, token=token) if repo else None
        if pull_request:
            labels = [label.get("name", "") for label in pull_request.get("labels", [])]
            title = str(pull_request.get("title", f"PR #{pr_number}")).strip()
            body = str(pull_request.get("body") or "")
            url = str(pull_request.get("html_url") or "")
            author = str((pull_request.get("user") or {}).get("login") or "")
            merged_at = str(pull_request.get("merged_at") or "")
        else:
            labels = []
            title = linked_commits[-1]["subject"]
            body = "\n\n".join(commit["body"] for commit in linked_commits if commit["body"]).strip()
            url = f"https://github.com/{repo}/pull/{pr_number}" if repo else ""
            author = ""
            merged_at = ""

        description = _extract_release_notes_section(body)
        if not description:
            description = "; ".join(commit["subject"] for commit in linked_commits)

        change_type = classify_change(title=title, body=body, labels=labels)
        changes.append(
            {
                "id": f"pr#{pr_number}",
                "source": "pull_request",
                "type": change_type,
                "title": title,
                "description": description,
                "labels": labels,
                "pr_number": pr_number,
                "url": url,
                "author": author,
                "merged_at": merged_at,
                "commit_shas": [commit["sha"] for commit in linked_commits],
            }
        )

    for commit in commits:
        if commit["sha"] in covered_commits:
            continue
        body = commit["body"]
        description = _extract_release_notes_section(body)
        if not description:
            description = commit["subject"]
        change_type = classify_change(
            title=commit["subject"],
            body=body,
            labels=[],
        )
        changes.append(
            {
                "id": f"commit:{commit['sha'][:7]}",
                "source": "commit",
                "type": change_type,
                "title": commit["subject"],
                "description": description,
                "labels": [],
                "commit_sha": commit["sha"],
                "url": f"https://github.com/{repo}/commit/{commit['sha']}" if repo else "",
            }
        )

    facts = {
        "schema_version": 1,
        "generated_at": _now_iso(),
        "repository": repo,
        "base_tag": base_tag,
        "head": head_ref,
        "head_sha": head_sha,
        "compare_range": range_expr,
        "changes": changes,
        "stats": {
            "change_count": len(changes),
            "pull_request_count": sum(1 for change in changes if change.get("source") == "pull_request"),
            "direct_commit_count": sum(1 for change in changes if change.get("source") == "commit"),
        },
    }
    _write_json(Path(args.output), facts)
    print(f"release-ai: wrote facts -> {args.output} ({len(changes)} change(s))")


def _summarize_changes_for_prompt(facts: dict[str, Any]) -> list[dict[str, Any]]:
    summary: list[dict[str, Any]] = []
    for change in facts.get("changes", []):
        summary.append(
            {
                "id": change.get("id"),
                "type": change.get("type"),
                "title": change.get("title"),
                "description": change.get("description"),
                "labels": change.get("labels", []),
                "source": change.get("source"),
            }
        )
    return summary


def _command_decide_bump(args: argparse.Namespace) -> None:
    facts = _read_json(Path(args.facts))
    changes = facts.get("changes", [])
    has_breaking = any(change.get("type") == "breaking" for change in changes)

    config = _llm_config()
    payload = {
        "base_tag": facts.get("base_tag"),
        "head": facts.get("head"),
        "stats": facts.get("stats", {}),
        "changes": _summarize_changes_for_prompt(facts),
    }

    system_prompt = textwrap.dedent(
        """
        You are a release manager.
        Decide semantic version bump for the next release.
        Return strict JSON with keys:
        - bump: one of major, minor, patch, none
        - reason: short string
        - confidence: float between 0 and 1
        - evidence_change_ids: array of change IDs that justify the decision

        Rules:
        - breaking changes => major
        - new user-facing feature(s) => at least minor
        - only fixes/chore => patch
        - no releasable change => none
        """
    ).strip()
    user_prompt = json.dumps(payload, ensure_ascii=False)
    decision_raw = _openai_chat_json(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        config=config,
    )

    bump = str(decision_raw.get("bump", "")).strip().lower()
    if bump not in {"major", "minor", "patch", "none"}:
        raise RuntimeError(f"invalid bump from LLM: {bump!r}")

    if has_breaking and bump != "major":
        raise RuntimeError("rule violation: breaking change requires major bump")
    if not changes and bump != "none":
        raise RuntimeError("rule violation: no changes requires bump=none")
    if changes and bump == "none":
        raise RuntimeError("rule violation: non-empty changes cannot use bump=none")

    decision = {
        "schema_version": 1,
        "generated_at": _now_iso(),
        "bump": bump,
        "reason": str(decision_raw.get("reason", "")).strip(),
        "confidence": float(decision_raw.get("confidence", 0.0)),
        "evidence_change_ids": decision_raw.get("evidence_change_ids", []),
        "has_breaking_change": has_breaking,
        "change_count": len(changes),
    }
    _write_json(Path(args.output), decision)
    print(f"release-ai: wrote bump decision -> {args.output} ({bump})")


def _command_compute_tag(args: argparse.Namespace) -> None:
    facts = _read_json(Path(args.facts))
    decision = _read_json(Path(args.decision))

    bump = str(decision.get("bump", "")).lower().strip()
    if bump == "none":
        raise RuntimeError("bump decision is 'none'; refusing to create release tag")

    base_tag = facts.get("base_tag")
    parsed_base = parse_semver_tag(str(base_tag)) if base_tag else None
    base_version = parsed_base or SemVer(0, 0, 0)

    next_version = bump_semver(base_version, bump)
    tag = str(next_version)
    if parse_semver_tag(tag) is None:
        raise RuntimeError(f"computed invalid tag: {tag}")

    payload = {
        "schema_version": 1,
        "generated_at": _now_iso(),
        "base_tag": str(base_tag or ""),
        "base_version": str(base_version),
        "bump": bump,
        "tag": tag,
    }
    _write_json(Path(args.output), payload)
    print(f"release-ai: wrote next tag -> {args.output} ({tag})")


def _translate_notes_with_llm(
    *,
    locale: str,
    tag: str,
    sections: dict[str, list[dict[str, Any]]],
    config: dict[str, Any],
) -> dict[str, Any]:
    source_items: list[dict[str, Any]] = []
    for key, items in sections.items():
        for item in items:
            source_items.append(
                {
                    "change_id": item["change_id"],
                    "type": key,
                    "source_text": item["source_text"],
                }
            )

    prompt = {
        "target_locale": locale,
        "version": tag,
        "items": source_items,
        "instructions": {
            "translate": "Translate each source_text to target locale.",
            "keep_meaning": True,
            "return_json_only": True,
            "must_keep_change_id": True,
        },
    }

    system_prompt = textwrap.dedent(
        """
        You localize release notes.
        Return strict JSON with keys:
        - summary: string
        - items: array of {change_id, text}
        - section_titles: object with keys breaking, feature, fix, chore
        - highlights: array of {text, change_ids}

        Constraints:
        - include every provided change_id exactly once in items
        - do not invent change IDs
        - keep text concise and user-facing
        """
    ).strip()

    return _openai_chat_json(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(prompt, ensure_ascii=False)},
        ],
        config=config,
    )


def _build_notes_for_locale(
    *,
    facts: dict[str, Any],
    locale: str,
    tag: str,
    config: dict[str, Any],
) -> dict[str, Any]:
    selected_changes = list(facts.get("changes", [])) if bool(facts.get("changes_curated")) else _select_user_facing_changes(list(facts.get("changes", [])))
    required_change_ids = [str(change["id"]) for change in selected_changes]

    if not selected_changes:
        notes = {
            "schema_version": 1,
            "generated_at": _now_iso(),
            "locale": locale,
            "version": tag,
            "summary": _default_maintenance_summary(locale, tag),
            "highlights": [],
            "sections": [],
        }
        validate_locale_notes(
            notes,
            expected_locale=locale,
            expected_version=tag,
            required_change_ids=[],
        )
        return notes

    grouped: dict[str, list[dict[str, Any]]] = {
        "breaking": [],
        "feature": [],
        "fix": [],
        "chore": [],
    }
    for change in selected_changes:
        key = str(change.get("type", "chore"))
        if key not in grouped:
            key = "chore"
        grouped[key].append(
            {
                "change_id": str(change["id"]),
                "source_text": str(change.get("title") or change.get("description") or "").strip(),
            }
        )

    localized = _translate_notes_with_llm(
        locale=locale,
        tag=tag,
        sections=grouped,
        config=config,
    )

    translated_items = localized.get("items")
    if not isinstance(translated_items, list):
        raise RuntimeError("LLM note output missing items list")
    translated_by_id: dict[str, str] = {}
    for entry in translated_items:
        change_id = str(entry.get("change_id", "")).strip()
        text = str(entry.get("text", "")).strip()
        if not change_id or not text:
            raise RuntimeError("LLM note output has empty change_id or text")
        translated_by_id[change_id] = text

    section_titles = _default_section_titles(locale)
    llm_titles = localized.get("section_titles")
    if isinstance(llm_titles, dict):
        for key in section_titles:
            value = llm_titles.get(key)
            if isinstance(value, str) and value.strip():
                section_titles[key] = value.strip()

    sections_output: list[dict[str, Any]] = []
    for section_key in ("breaking", "feature", "fix", "chore"):
        items_payload: list[dict[str, Any]] = []
        for source_item in grouped[section_key]:
            change_id = source_item["change_id"]
            translated_text = translated_by_id.get(change_id)
            if not translated_text:
                raise RuntimeError(f"LLM note output missing change_id '{change_id}'")
            items_payload.append({"text": translated_text, "change_ids": [change_id]})

        if not items_payload:
            continue
        sections_output.append(
            {
                "key": section_key,
                "title": section_titles[section_key],
                "items": items_payload,
            }
        )

    summary = str(localized.get("summary", "")).strip()
    if not summary:
        summary = f"{len(selected_changes)} user-facing update(s) in {tag}."

    raw_highlights = localized.get("highlights")
    highlights: list[dict[str, Any]] = []
    if isinstance(raw_highlights, list):
        for highlight in raw_highlights:
            text = str(highlight.get("text", "")).strip()
            change_ids = highlight.get("change_ids")
            if text and isinstance(change_ids, list) and change_ids:
                highlights.append(
                    {
                        "text": text,
                        "change_ids": [str(change_id) for change_id in change_ids],
                    }
                )

    if not highlights:
        for section in sections_output:
            if not section["items"]:
                continue
            item = section["items"][0]
            highlights.append(
                {
                    "text": item["text"],
                    "change_ids": item["change_ids"],
                }
            )
            if len(highlights) >= 3:
                break

    notes = {
        "schema_version": 1,
        "generated_at": _now_iso(),
        "locale": locale,
        "version": tag,
        "summary": summary,
        "highlights": highlights,
        "sections": sections_output,
    }

    validate_locale_notes(
        notes,
        expected_locale=locale,
        expected_version=tag,
        required_change_ids=required_change_ids,
    )
    return notes


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_obj:
        while True:
            chunk = file_obj.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _command_generate_notes(args: argparse.Namespace) -> None:
    facts = _read_json(Path(args.facts))
    tag = args.tag
    if parse_semver_tag(tag) is None:
        raise RuntimeError(f"invalid release tag '{tag}': expected vX.Y.Z")

    locales = [locale.strip() for locale in args.locales.split(",") if locale.strip()]
    if not locales:
        raise RuntimeError("locales cannot be empty")

    config = _llm_config()

    curated_changes = curate_user_facing_changes_with_llm(
        changes=list(facts.get("changes", [])),
        tag=tag,
        config=config,
        llm_call=_openai_chat_json,
    )
    curated_facts = dict(facts)
    curated_facts["changes"] = curated_changes
    curated_facts["changes_curated"] = True

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    note_files: list[dict[str, str]] = []
    for locale in locales:
        notes = _build_notes_for_locale(
            facts=curated_facts,
            locale=locale,
            tag=tag,
            config=config,
        )
        file_name = f"release-notes-{tag}-{locale}.json"
        file_path = output_dir / file_name
        _write_json(file_path, notes)
        note_files.append(
            {
                "locale": locale,
                "file": file_name,
                "sha256": _sha256(file_path),
            }
        )

    default_locale = "en-US" if "en-US" in locales else locales[0]
    manifest = {
        "schema_version": 1,
        "generated_at": _now_iso(),
        "version": tag,
        "default_locale": default_locale,
        "supported_locales": locales,
        "included_change_ids": [str(change.get("id", "")).strip() for change in curated_changes if str(change.get("id", "")).strip()],
        "notes": note_files,
    }
    manifest_path = output_dir / f"release-notes-{tag}-manifest.json"
    _write_json(manifest_path, manifest)
    print(f"release-ai: wrote notes -> {output_dir}")


def _command_validate_notes(args: argparse.Namespace) -> None:
    facts = _read_json(Path(args.facts))
    tag = args.tag
    locales = [locale.strip() for locale in args.locales.split(",") if locale.strip()]
    output_dir = Path(args.notes_dir)

    manifest_path = output_dir / f"release-notes-{tag}-manifest.json"
    if not manifest_path.exists():
        raise RuntimeError(f"missing manifest: {manifest_path}")
    manifest = _read_json(manifest_path)

    included_change_ids = manifest.get("included_change_ids")
    if isinstance(included_change_ids, list):
        required_change_ids = [str(change_id).strip() for change_id in included_change_ids if str(change_id).strip()]
    else:
        required_change_ids = [str(change["id"]) for change in _select_user_facing_changes(list(facts.get("changes", [])))]

    for locale in locales:
        note_path = output_dir / f"release-notes-{tag}-{locale}.json"
        if not note_path.exists():
            raise RuntimeError(f"missing notes file: {note_path}")
        notes = _read_json(note_path)
        validate_locale_notes(
            notes,
            expected_locale=locale,
            expected_version=tag,
            required_change_ids=required_change_ids,
        )

    if manifest.get("version") != tag:
        raise RuntimeError("manifest version mismatch")

    notes_entries = manifest.get("notes")
    if not isinstance(notes_entries, list):
        raise RuntimeError("manifest notes must be list")

    for entry in notes_entries:
        file_name = str(entry.get("file", "")).strip()
        if not file_name:
            raise RuntimeError("manifest entry missing file")
        note_path = output_dir / file_name
        if not note_path.exists():
            raise RuntimeError(f"manifest file not found: {note_path}")
        expected_sha = str(entry.get("sha256", "")).strip().lower()
        actual_sha = _sha256(note_path)
        if expected_sha != actual_sha:
            raise RuntimeError(f"sha256 mismatch for {file_name}")

    print(f"release-ai: notes validation passed ({', '.join(locales)})")


def _command_render_markdown(args: argparse.Namespace) -> None:
    output_dir = Path(args.notes_dir)
    tag = args.tag
    locales = [locale.strip() for locale in args.locales.split(",") if locale.strip()]
    locale_headings = _locale_headings(locales)
    links = _change_links_from_facts(str(args.facts).strip())

    lines: list[str] = [f"# Release {tag}"]
    for locale in locales:
        note_path = output_dir / f"release-notes-{tag}-{locale}.json"
        notes = _read_json(note_path)
        lines.append("")
        lines.append(f"## {locale_headings.get(locale, locale)}")
        summary = str(notes.get("summary", "")).strip()
        if summary:
            lines.append(summary)
            lines.append("")

        highlights = notes.get("highlights")
        if isinstance(highlights, list) and highlights:
            lines.append("### Highlights")
            for highlight in highlights:
                text = str(highlight.get("text", "")).strip()
                if not text:
                    continue
                refs = _format_change_refs(highlight.get("change_ids", []), links)
                lines.append(f"- {text} {refs}".rstrip())

        sections = notes.get("sections")
        if isinstance(sections, list):
            for section in sections:
                title = str(section.get("title", "")).strip()
                items = section.get("items", [])
                if not title or not items:
                    continue
                lines.append("")
                lines.append(f"### {title}")
                for item in items:
                    text = str(item.get("text", "")).strip()
                    refs = _format_change_refs(item.get("change_ids", []), links)
                    lines.append(f"- {text} {refs}".rstrip())

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"release-ai: wrote markdown -> {output_path}")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="release_ai.py",
        description="AI-assisted release helper for facts collection, bump decision, and multilingual notes.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    collect = subparsers.add_parser("collect-facts", help="Collect release facts from git + GitHub PR metadata")
    collect.add_argument("--repo", default="", help="GitHub repo slug (owner/repo). Auto-detect from origin when omitted.")
    collect.add_argument("--base-tag", default="auto", help="Base tag for compare range. Use 'auto' to detect latest semver tag.")
    collect.add_argument(
        "--auto-base-source",
        default="git-tags",
        choices=["git-tags", "github-releases"],
        help="When --base-tag=auto, choose baseline from git tags or published GitHub releases.",
    )
    collect.add_argument("--head", default="HEAD", help="Git ref used as compare range head when --head-tag is not provided.")
    collect.add_argument("--head-tag", default="", help="Semver tag used as compare range head (for CI tag release jobs).")
    collect.add_argument("--output", required=True, help="Output JSON path.")
    collect.set_defaults(func=_command_collect_facts)

    decide = subparsers.add_parser("decide-bump", help="Use LLM to decide semantic version bump")
    decide.add_argument("--facts", required=True, help="Facts JSON path.")
    decide.add_argument("--output", required=True, help="Output decision JSON path.")
    decide.set_defaults(func=_command_decide_bump)

    compute = subparsers.add_parser("compute-tag", help="Compute next semver tag from facts + bump decision")
    compute.add_argument("--facts", required=True, help="Facts JSON path.")
    compute.add_argument("--decision", required=True, help="Decision JSON path.")
    compute.add_argument("--output", required=True, help="Output computed-tag JSON path.")
    compute.set_defaults(func=_command_compute_tag)

    generate = subparsers.add_parser("generate-notes", help="Generate multilingual release note assets")
    generate.add_argument("--facts", required=True, help="Facts JSON path.")
    generate.add_argument("--tag", required=True, help="Release tag (vX.Y.Z).")
    generate.add_argument("--locales", default="zh-CN,en-US", help="Comma-separated locales.")
    generate.add_argument("--output-dir", required=True, help="Output directory for note assets.")
    generate.set_defaults(func=_command_generate_notes)

    validate = subparsers.add_parser("validate-notes", help="Validate note assets and manifest")
    validate.add_argument("--facts", required=True, help="Facts JSON path.")
    validate.add_argument("--tag", required=True, help="Release tag (vX.Y.Z).")
    validate.add_argument("--locales", default="zh-CN,en-US", help="Comma-separated locales.")
    validate.add_argument("--notes-dir", required=True, help="Directory containing generated note assets.")
    validate.set_defaults(func=_command_validate_notes)

    render = subparsers.add_parser("render-markdown", help="Render release notes markdown from note assets")
    render.add_argument("--tag", required=True, help="Release tag (vX.Y.Z).")
    render.add_argument("--locales", default="zh-CN,en-US", help="Comma-separated locales.")
    render.add_argument("--notes-dir", required=True, help="Directory containing generated note assets.")
    render.add_argument("--facts", default="", help="Optional facts JSON path for rendering linked references.")
    render.add_argument("--output", required=True, help="Output markdown path.")
    render.set_defaults(func=_command_render_markdown)

    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
    except RuntimeError as exc:
        _die(str(exc))


if __name__ == "__main__":
    main()
