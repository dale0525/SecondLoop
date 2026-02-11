from __future__ import annotations

import json
import textwrap
from typing import Any, Callable


def curate_user_facing_changes_with_llm(
    *,
    changes: list[dict[str, Any]],
    tag: str,
    config: dict[str, Any],
    llm_call: Callable[..., dict[str, Any]],
) -> list[dict[str, Any]]:
    if not changes:
        return []

    payload = {
        "release_tag": tag,
        "changes": [
            {
                "change_id": str(change.get("id", "")).strip(),
                "type": str(change.get("type", "chore")).strip().lower(),
                "title": str(change.get("title", "")).strip(),
                "description": str(change.get("description", "")).strip(),
                "labels": [str(label).strip() for label in change.get("labels", [])],
            }
            for change in changes
        ],
    }

    system_prompt = textwrap.dedent(
        """
        You classify release changes for end-user release notes.
        Return strict JSON with key:
        - items: array of {change_id, include, type, reason}

        Rules:
        - include=true only for user-facing changes that matter to typical app users
        - technical-only items (CI/build/refactor/internal tooling/docs-only) => include=false
        - build pipeline, compiler, headers, artifact naming, packaging, and release workflow changes are technical unless they directly change user experience
        - breaking is only for user-visible incompatibility (removed behavior, migration required, API/format change users notice)
        - if included, set type to one of: breaking, feature, fix, chore
        - do not invent change IDs
        - include every input change_id exactly once in items
        """
    ).strip()

    response = llm_call(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        config=config,
    )

    raw_items = response.get("items")
    if not isinstance(raw_items, list):
        raise RuntimeError("LLM curation output missing items list")

    decisions: dict[str, tuple[bool, str]] = {}
    for item in raw_items:
        change_id = str(item.get("change_id", "")).strip()
        include = bool(item.get("include", False))
        curated_type = str(item.get("type", "chore")).strip().lower()
        if curated_type not in {"breaking", "feature", "fix", "chore"}:
            curated_type = "chore"
        if change_id:
            decisions[change_id] = (include, curated_type)

    curated_changes: list[dict[str, Any]] = []
    missing_ids: list[str] = []
    for change in changes:
        change_id = str(change.get("id", "")).strip()
        decision = decisions.get(change_id)
        if decision is None:
            missing_ids.append(change_id)
            continue

        include, curated_type = decision
        if not include:
            continue

        copied = dict(change)
        copied["type"] = curated_type
        curated_changes.append(copied)

    if missing_ids:
        missing_text = ", ".join(change_id for change_id in missing_ids if change_id)
        raise RuntimeError(f"LLM curation missing change ids: {missing_text}")

    return curated_changes
