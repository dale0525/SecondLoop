#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.request
from typing import Any


SOURCE_FILE_SUFFIX = ".i18n.json"
LANGUAGE_CODE_PATTERN = re.compile(r"^[a-z]{2,3}$")
SCRIPT_CODE_PATTERN = re.compile(r"^[A-Z][a-z]{3}$")
REGION_CODE_PATTERN = re.compile(r"^(?:[A-Z]{2}|[0-9]{3})$")
VARIANT_CODE_PATTERN = re.compile(r"^(?:[A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3})$")


def _iter_string_leaves(node: Any, path: list[str] | None = None):
    if path is None:
        path = []

    if isinstance(node, dict):
        for key, value in node.items():
            yield from _iter_string_leaves(value, [*path, str(key)])
        return

    if isinstance(node, list):
        for index, value in enumerate(node):
            yield from _iter_string_leaves(value, [*path, str(index)])
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
    with open(path, "r", encoding="utf-8") as file_handle:
        data = json.load(file_handle)
    if not isinstance(data, dict):
        raise TypeError(f"{path} must be a JSON object at root")
    return data


def _write_json(path: str, data: dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as file_handle:
        json.dump(data, file_handle, ensure_ascii=False, indent=2)
        file_handle.write("\n")


def _normalize_locale_tag(locale: str) -> str:
    return locale.replace("-", "_")


def _is_probable_locale_tag(locale: str) -> bool:
    parts = _normalize_locale_tag(locale).split("_")
    if not parts or not LANGUAGE_CODE_PATTERN.fullmatch(parts[0]):
        return False

    for part in parts[1:]:
        if SCRIPT_CODE_PATTERN.fullmatch(part):
            continue
        if REGION_CODE_PATTERN.fullmatch(part):
            continue
        if VARIANT_CODE_PATTERN.fullmatch(part):
            continue
        return False

    return True


def _split_namespace_and_locale(base_name: str, source_locale: str) -> tuple[str, str]:
    normalized_source_locale = _normalize_locale_tag(source_locale)
    candidates: list[tuple[str, str]] = []

    for index, char in enumerate(base_name):
        if char not in {"_", "-"}:
            continue

        namespace = base_name[:index]
        locale = base_name[index + 1 :]
        if not namespace or not locale:
            continue

        normalized_locale = _normalize_locale_tag(locale)
        if _is_probable_locale_tag(normalized_locale):
            candidates.append((namespace, normalized_locale))

    if not candidates:
        return base_name, normalized_source_locale

    source_locale_matches = [candidate for candidate in candidates if candidate[1] == normalized_source_locale]
    if source_locale_matches:
        return max(source_locale_matches, key=lambda candidate: len(candidate[0]))

    return max(candidates, key=lambda candidate: len(candidate[1]))


def _parse_translation_file_name(
    path: Path,
    *,
    source_locale: str,
) -> tuple[str, str]:
    if not path.name.endswith(SOURCE_FILE_SUFFIX):
        raise ValueError(f"{path} is not a supported translation file")

    base_name = path.name[: -len(SOURCE_FILE_SUFFIX)]
    namespace, locale = _split_namespace_and_locale(base_name, source_locale)
    if not namespace:
        raise ValueError(f"Unsupported translation file name: {path.name}")

    return namespace, locale


def discover_translation_pairs(
    root: Path,
    *,
    source_locale: str = "en",
    target_locale: str = "zh_CN",
) -> list[tuple[Path, Path]]:
    normalized_source_locale = _normalize_locale_tag(source_locale)
    normalized_target_locale = _normalize_locale_tag(target_locale)
    source_files: dict[str, Path] = {}
    target_files: dict[str, Path] = {}

    for file_path in sorted(root.glob(f"*{SOURCE_FILE_SUFFIX}")):
        namespace, locale = _parse_translation_file_name(
            file_path,
            source_locale=normalized_source_locale,
        )
        if locale == normalized_source_locale:
            source_files[namespace] = file_path
        elif locale == normalized_target_locale:
            target_files[namespace] = file_path

    pairs: list[tuple[Path, Path]] = []
    for namespace, source_path in sorted(source_files.items()):
        target_path = target_files.get(namespace)
        if target_path is None:
            target_path = source_path.with_name(
                f"{namespace}_{normalized_target_locale}{SOURCE_FILE_SUFFIX}"
            )
        pairs.append((source_path, target_path))

    return pairs


def _extract_json(text: str) -> dict[str, str]:
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return {str(key): str(value) for key, value in parsed.items()}
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Gemini response is not JSON")

    parsed = json.loads(text[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("Gemini response JSON root is not object")
    return {str(key): str(value) for key, value in parsed.items()}


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
        '- Keep product names (e.g. "SecondLoop") unchanged.\n'
        "- Return ONLY a valid minified JSON object mapping the same keys to translated strings.\n"
        f"JSON:\n{json.dumps(flat, ensure_ascii=False)}"
    )

    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
        },
    }

    request = urllib.request.Request(
        url=url,
        method="POST",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gemini HTTP {exc.code}: {detail}") from exc

    try:
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as exc:  # noqa: BLE001 - best-effort parsing
        raise RuntimeError(f"Unexpected Gemini response shape: {payload}") from exc

    return _extract_json(str(text))


def translate_pair(
    source: Path,
    target: Path,
    *,
    force: bool,
    dry_run: bool,
) -> int:
    source_data = _load_json(str(source))
    target_data = _load_json(str(target)) if target.exists() else {}

    if not isinstance(target_data, dict):
        raise TypeError(f"{target} must be a JSON object at root")

    missing: dict[str, str] = {}
    for dotted_path, en_value in _iter_string_leaves(source_data):
        existing = _get_by_path(target_data, dotted_path)
        if force or existing is None or (isinstance(existing, str) and not existing.strip()):
            missing[dotted_path] = en_value

    if not missing:
        print(f"No missing keys for {source.name}. Nothing to translate.")
        return 0

    api_key = os.environ.get("GEMINI_API_KEY")
    batch_size = int(os.environ.get("GEMINI_BATCH_SIZE", "40"))

    translated: dict[str, str] = {}
    if api_key:
        items = list(missing.items())
        for start_index in range(0, len(items), batch_size):
            batch = dict(items[start_index : start_index + batch_size])
            print(f"Translating {len(batch)} strings for {source.name} via Gemini...")
            translated.update(_gemini_translate_flat_map(batch))
            time.sleep(0.2)
    else:
        print(
            f"GEMINI_API_KEY not set; using English as fallback for missing keys in {source.name}."
        )
        translated = dict(missing)

    for dotted_path, value in translated.items():
        _set_by_path(target_data, dotted_path, value)

    if dry_run:
        print(f"Dry-run complete. Would write {len(translated)} strings to {target}.")
        return 0

    _write_json(str(target), target_data)
    print(f"Wrote {len(translated)} strings to {target}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Translate i18n json via Gemini.")
    parser.add_argument(
        "--input-directory",
        help="Directory mode: translate all locale namespace pairs inside this folder.",
    )
    parser.add_argument(
        "--source",
        help="Source i18n json (English) for single-file mode.",
    )
    parser.add_argument(
        "--target",
        help="Target i18n json (zh-CN) for single-file mode.",
    )
    parser.add_argument(
        "--source-locale",
        default="en",
        help="Source locale used by directory mode.",
    )
    parser.add_argument(
        "--target-locale",
        default="zh_CN",
        help="Target locale used by directory mode.",
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

    single_file_mode = args.source is not None or args.target is not None
    if args.input_directory and single_file_mode:
        parser.error("--input-directory cannot be combined with --source/--target")

    if single_file_mode:
        if args.source is None or args.target is None:
            parser.error("--source and --target must be provided together")
        return translate_pair(
            Path(args.source),
            Path(args.target),
            force=args.force,
            dry_run=args.dry_run,
        )

    input_directory = args.input_directory or "lib/i18n"
    pairs = discover_translation_pairs(
        Path(input_directory),
        source_locale=args.source_locale,
        target_locale=args.target_locale,
    )
    if not pairs:
        print(f"No translation pairs found under {input_directory}.")
        return 0

    exit_code = 0
    for source, target in pairs:
        exit_code |= translate_pair(
            source,
            target,
            force=args.force,
            dry_run=args.dry_run,
        )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
