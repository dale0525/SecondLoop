from __future__ import annotations

import json
from pathlib import Path
from typing import Any

TECHNICAL_LABEL_MARKERS = (
    "ci",
    "chore",
    "build",
    "infra",
    "internal",
    "docs",
    "refactor",
    "test",
)
TECHNICAL_TEXT_MARKERS = (
    "ci",
    "workflow",
    "pipeline",
    "release script",
    "build system",
    "internal",
    "refactor",
    "unit test",
    "integration test",
    "lint",
    "format",
    "dependency",
    "dependencies",
    "readme",
    "documentation",
)
USER_FACING_TEXT_MARKERS = (
    "user",
    "ui",
    "ux",
    "app",
    "screen",
    "dialog",
    "settings",
    "audio",
    "video",
    "transcribe",
    "translate",
    "annotation",
    "chat",
    "sync",
    "performance",
    "stability",
    "crash",
)
LOCALE_LANGUAGE_NAMES = {
    "en": "English",
    "zh": "Chinese",
    "ja": "Japanese",
    "ko": "Korean",
    "fr": "French",
    "de": "German",
    "es": "Spanish",
    "it": "Italian",
    "pt": "Portuguese",
    "ru": "Russian",
}


def _normalize_locale_token(locale: str) -> tuple[str, str]:
    normalized = locale.strip().replace("_", "-")
    parts = [part for part in normalized.split("-") if part]
    language = parts[0].lower() if parts else ""
    region = parts[1].upper() if len(parts) > 1 else ""
    return language, region


def _locale_display_name(locale: str) -> str:
    language, region = _normalize_locale_token(locale)
    language_name = LOCALE_LANGUAGE_NAMES.get(language)
    if not language_name:
        return locale

    if language == "zh":
        if region in {"CN", "SG"}:
            return "Chinese (Simplified)"
        if region in {"TW", "HK", "MO"}:
            return "Chinese (Traditional)"
    return language_name


def _contains_any_marker(text: str, markers: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(marker in lowered for marker in markers)


def _is_user_facing_change(change: dict[str, Any]) -> bool:
    change_type = str(change.get("type", "chore")).strip().lower()
    labels = [str(label).strip().lower() for label in change.get("labels", []) if str(label).strip()]
    text = f"{change.get('title', '')}\n{change.get('description', '')}".lower()

    if change_type == "breaking":
        return True

    has_technical_label = any(
        marker in label
        for label in labels
        for marker in TECHNICAL_LABEL_MARKERS
    )
    has_technical_text = _contains_any_marker(text, TECHNICAL_TEXT_MARKERS)
    has_user_facing_text = _contains_any_marker(text, USER_FACING_TEXT_MARKERS)

    if (has_technical_label or has_technical_text) and not has_user_facing_text:
        return False

    if change_type in {"feature", "fix"}:
        return True

    return has_user_facing_text


def _select_user_facing_changes(changes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [change for change in changes if _is_user_facing_change(change)]


def _default_section_titles(locale: str) -> dict[str, str]:
    if locale.lower().startswith("zh"):
        return {
            "breaking": "破坏性变更",
            "feature": "新功能",
            "fix": "问题修复",
            "chore": "其他更新",
        }
    return {
        "breaking": "Breaking Changes",
        "feature": "New Features",
        "fix": "Fixes",
        "chore": "Other Changes",
    }


def _default_maintenance_summary(locale: str, tag: str) -> str:
    language, _region = _normalize_locale_token(locale)
    if language == "zh":
        return f"{tag} 包含稳定性与维护更新。"
    return f"{tag} includes stability and maintenance updates."


def _change_links_from_facts(facts_path: str) -> dict[str, str]:
    if not facts_path:
        return {}

    facts = json.loads(Path(facts_path).read_text(encoding="utf-8"))
    links: dict[str, str] = {}
    for change in facts.get("changes", []):
        change_id = str(change.get("id", "")).strip()
        url = str(change.get("url", "")).strip()
        if change_id and url:
            links[change_id] = url
    return links


def _format_change_refs(change_ids: Any, links: dict[str, str]) -> str:
    if not isinstance(change_ids, list):
        return ""

    refs: list[str] = []
    for raw_change_id in change_ids:
        change_id = str(raw_change_id).strip()
        if not change_id:
            continue
        url = links.get(change_id, "").strip()
        if url:
            refs.append(f"[{change_id}]({url})")
        else:
            refs.append(f"[{change_id}]")
    return " ".join(refs)


def _locale_headings(locales: list[str]) -> dict[str, str]:
    display_names = {locale: _locale_display_name(locale) for locale in locales}
    counts: dict[str, int] = {}
    for name in display_names.values():
        counts[name] = counts.get(name, 0) + 1

    headings: dict[str, str] = {}
    for locale in locales:
        display_name = display_names[locale]
        if counts.get(display_name, 0) > 1:
            headings[locale] = f"{display_name} ({locale})"
        else:
            headings[locale] = display_name
    return headings
