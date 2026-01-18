#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any


def _iter_string_leaves(node: Any, path: list[str] | None = None):
    if path is None:
        path = []

    if isinstance(node, dict):
        for k, v in node.items():
            yield from _iter_string_leaves(v, [*path, str(k)])
        return

    if isinstance(node, list):
        for idx, v in enumerate(node):
            yield from _iter_string_leaves(v, [*path, str(idx)])
        return

    if isinstance(node, str):
        yield ".".join(path), node


def _get_by_path(root: dict[str, Any], dotted_path: str) -> Any:
    cur: Any = root
    for part in dotted_path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def _set_by_path(root: dict[str, Any], dotted_path: str, value: Any) -> None:
    cur: Any = root
    parts = dotted_path.split(".")
    for part in parts[:-1]:
        if not isinstance(cur, dict):
            raise TypeError(f"Path {dotted_path} expects dict at {part}")
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    if not isinstance(cur, dict):
        raise TypeError(f"Path {dotted_path} expects dict at leaf parent")
    cur[parts[-1]] = value


def _load_json(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise TypeError(f"{path} must be a JSON object at root")
    return data


def _write_json(path: str, data: dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _extract_json(text: str) -> dict[str, str]:
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return {str(k): str(v) for k, v in parsed.items()}
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Gemini response is not JSON")

    parsed = json.loads(text[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("Gemini response JSON root is not object")
    return {str(k): str(v) for k, v in parsed.items()}


def _gemini_translate_flat_map(flat: dict[str, str]) -> dict[str, str]:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("Missing env GEMINI_API_KEY")

    model = os.environ.get("GEMINI_MODEL", "gemini-1.5-flash-latest")
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )

    prompt = (
        "Translate the following UI strings from English to Simplified Chinese (zh-CN).\n"
        "- Keep JSON keys unchanged.\n"
        "- Keep product names (e.g. \"SecondLoop\") unchanged.\n"
        "- Return ONLY a valid minified JSON object mapping the same keys to translated strings.\n"
        f"JSON:\n{json.dumps(flat, ensure_ascii=False)}"
    )

    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
        },
    }

    req = urllib.request.Request(
        url=url,
        method="POST",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gemini HTTP {e.code}: {detail}") from e

    try:
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:  # noqa: BLE001 - best-effort parsing
        raise RuntimeError(f"Unexpected Gemini response shape: {payload}") from e

    return _extract_json(str(text))


def main() -> int:
    parser = argparse.ArgumentParser(description="Translate i18n json via Gemini.")
    parser.add_argument(
        "--source",
        default="lib/i18n/strings_en.i18n.json",
        help="Source i18n json (English).",
    )
    parser.add_argument(
        "--target",
        default="lib/i18n/strings_zh_CN.i18n.json",
        help="Target i18n json (zh-CN).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Translate all strings (not just missing keys).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write target file; print summary only.",
    )
    args = parser.parse_args()

    src = _load_json(args.source)
    dst = _load_json(args.target) if os.path.exists(args.target) else {}

    if not isinstance(dst, dict):
        raise TypeError(f"{args.target} must be a JSON object at root")

    missing: dict[str, str] = {}
    for dotted, en_value in _iter_string_leaves(src):
        existing = _get_by_path(dst, dotted)
        if args.force or existing is None or (isinstance(existing, str) and not existing.strip()):
            missing[dotted] = en_value

    if not missing:
        print("No missing keys. Nothing to translate.")
        return 0

    api_key = os.environ.get("GEMINI_API_KEY")
    batch_size = int(os.environ.get("GEMINI_BATCH_SIZE", "40"))

    translated: dict[str, str] = {}
    if api_key:
        items = list(missing.items())
        for i in range(0, len(items), batch_size):
            batch = dict(items[i : i + batch_size])
            print(f"Translating {len(batch)} strings via Gemini...")
            translated.update(_gemini_translate_flat_map(batch))
            time.sleep(0.2)
    else:
        print("GEMINI_API_KEY not set; using English as fallback for missing keys.")
        translated = dict(missing)

    for dotted, value in translated.items():
        _set_by_path(dst, dotted, value)

    if args.dry_run:
        print(f"Dry-run complete. Would write {len(translated)} strings to {args.target}.")
        return 0

    _write_json(args.target, dst)
    print(f"Wrote {len(translated)} strings to {args.target}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

