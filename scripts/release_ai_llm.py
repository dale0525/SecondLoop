#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import ssl
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def _normalize_env_value(name: str, default: str = "") -> str:
    value = os.getenv(name, default).strip()
    if not value:
        return ""

    prefix = f"{name}="
    if value.startswith(prefix):
        value = value[len(prefix) :].strip()

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1].strip()

    return value


def llm_config() -> dict[str, Any]:
    api_key = _normalize_env_value("RELEASE_LLM_API_KEY")
    model = _normalize_env_value("RELEASE_LLM_MODEL")
    base_url = _normalize_env_value("RELEASE_LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    endpoint = _normalize_env_value("RELEASE_LLM_ENDPOINT")
    timeout_seconds = int(_normalize_env_value("RELEASE_LLM_TIMEOUT_SECONDS", "60") or "60")
    retries = int(_normalize_env_value("RELEASE_LLM_MAX_RETRIES", "2") or "2")
    ca_bundle = _normalize_env_value("RELEASE_LLM_CA_BUNDLE")
    insecure_skip_verify = _normalize_env_value("RELEASE_LLM_INSECURE_SKIP_VERIFY", "0").lower() in {"1", "true", "yes", "on"}
    auth_header = _normalize_env_value("RELEASE_LLM_AUTH_HEADER")
    auth_scheme = _normalize_env_value("RELEASE_LLM_AUTH_SCHEME", "Bearer")

    if not api_key:
        raise RuntimeError("missing RELEASE_LLM_API_KEY")
    if not model:
        raise RuntimeError("missing RELEASE_LLM_MODEL")
    if ca_bundle and not Path(ca_bundle).is_file():
        raise RuntimeError(f"RELEASE_LLM_CA_BUNDLE does not exist: {ca_bundle}")

    return {
        "api_key": api_key,
        "model": model,
        "base_url": base_url,
        "endpoint": endpoint,
        "timeout_seconds": timeout_seconds,
        "retries": retries,
        "ca_bundle": ca_bundle,
        "insecure_skip_verify": insecure_skip_verify,
        "auth_header": auth_header,
        "auth_scheme": auth_scheme,
    }


def _extract_json_object(raw_text: str) -> dict[str, Any]:
    stripped = raw_text.strip()
    if stripped.startswith("{") and stripped.endswith("}"):
        return json.loads(stripped)

    start = stripped.find("{")
    end = stripped.rfind("}")
    if start >= 0 and end > start:
        candidate = stripped[start : end + 1]
        return json.loads(candidate)
    raise ValueError("LLM response does not contain a JSON object")


def _stringify_content(content: Any) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        out: list[str] = []
        for item in content:
            if isinstance(item, str):
                out.append(item)
            elif isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str) and text.strip():
                    out.append(text)
                    continue
                nested = _stringify_content(item.get("content"))
                if nested:
                    out.append(nested)
        return "".join(out).strip()
    if isinstance(content, dict):
        text = content.get("text")
        if isinstance(text, str):
            return text.strip()
        return _stringify_content(content.get("content"))
    return ""


def _extract_content(parsed: dict[str, Any]) -> str:
    choices = parsed.get("choices")
    if isinstance(choices, list) and choices:
        message = choices[0].get("message", {})
        if isinstance(message, dict):
            text = _stringify_content(message.get("content"))
            if text:
                return text

    output_text = parsed.get("output_text")
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()

    output = parsed.get("output")
    if isinstance(output, list):
        parts: list[str] = []
        for item in output:
            if not isinstance(item, dict):
                continue
            content_items = item.get("content")
            if not isinstance(content_items, list):
                continue
            for content_item in content_items:
                text = _stringify_content(content_item)
                if text:
                    parts.append(text)
        if parts:
            return "".join(parts).strip()

    return ""


def _auth_header_variants(config: dict[str, Any]) -> list[dict[str, str]]:
    api_key = str(config["api_key"])
    auth_header = str(config.get("auth_header", "")).strip()
    auth_scheme = str(config.get("auth_scheme", "")).strip()

    variants: list[dict[str, str]] = []
    if auth_header:
        prefix = f"{auth_scheme} " if auth_scheme else ""
        variants.append({auth_header: f"{prefix}{api_key}"})
    else:
        variants.extend(
            [
                {"Authorization": f"Bearer {api_key}"},
                {"api-key": api_key},
                {"x-api-key": api_key},
            ]
        )

    unique: list[dict[str, str]] = []
    seen: set[tuple[tuple[str, str], ...]] = set()
    for variant in variants:
        normalized = tuple(sorted((key.lower(), value) for key, value in variant.items()))
        if normalized in seen:
            continue
        seen.add(normalized)
        unique.append(variant)
    return unique


def _endpoint_variants(config: dict[str, Any]) -> list[str]:
    endpoint = str(config.get("endpoint", "")).strip()
    if endpoint:
        return [endpoint]

    base_url = str(config["base_url"]).rstrip("/")
    if base_url.endswith("/chat/completions") or base_url.endswith("/responses"):
        return [base_url]
    return [f"{base_url}/chat/completions", f"{base_url}/responses"]


def _payload_for_endpoint(messages: list[dict[str, str]], *, config: dict[str, Any], endpoint: str) -> dict[str, Any]:
    normalized = endpoint.split("?", maxsplit=1)[0].rstrip("/")
    if normalized.endswith("/responses"):
        return {
            "model": config["model"],
            "temperature": 0,
            "input": messages,
        }
    return {
        "model": config["model"],
        "temperature": 0,
        "messages": messages,
    }


def _http_error_message(exc: urllib.error.HTTPError) -> str:
    detail = str(exc)
    try:
        body = exc.read().decode("utf-8", errors="replace").strip()
    except Exception:  # noqa: BLE001
        body = ""
    finally:
        try:
            exc.close()
        except Exception:  # noqa: BLE001
            pass

    if not body:
        return detail

    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        text = body
    else:
        if isinstance(parsed, dict):
            error = parsed.get("error")
            if isinstance(error, dict):
                text = str(error.get("message") or error.get("code") or body)
            else:
                text = str(parsed.get("message") or body)
        else:
            text = body

    if len(text) > 400:
        text = text[:400].rstrip() + "..."
    return text


def openai_chat_json(messages: list[dict[str, str]], *, config: dict[str, Any]) -> dict[str, Any]:
    urlopen_kwargs: dict[str, Any] = {"timeout": config["timeout_seconds"]}
    ca_bundle = str(config.get("ca_bundle", "")).strip()
    if bool(config.get("insecure_skip_verify")):
        urlopen_kwargs["context"] = ssl._create_unverified_context()
    elif ca_bundle:
        urlopen_kwargs["context"] = ssl.create_default_context(cafile=ca_bundle)

    failures: list[str] = []
    retries = int(config.get("retries", 0))
    endpoints = _endpoint_variants(config)
    auth_headers = _auth_header_variants(config)

    for _attempt in range(retries + 1):
        for endpoint in endpoints:
            payload = _payload_for_endpoint(messages, config=config, endpoint=endpoint)
            body = json.dumps(payload).encode("utf-8")
            for auth_header in auth_headers:
                headers = {
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "User-Agent": "secondloop-release-ai",
                    **auth_header,
                }
                request = urllib.request.Request(
                    url=endpoint,
                    data=body,
                    headers=headers,
                    method="POST",
                )
                try:
                    with urllib.request.urlopen(request, **urlopen_kwargs) as response:
                        raw = response.read().decode("utf-8")
                    parsed = json.loads(raw)
                    content = _extract_content(parsed)
                    if not content:
                        raise RuntimeError("empty LLM response")
                    return _extract_json_object(content)
                except urllib.error.HTTPError as exc:
                    status = int(exc.code)
                    message = _http_error_message(exc)
                    failures.append(f"HTTP {status} @ {endpoint}: {message}")
                    if status in {401, 403, 404, 405}:
                        continue
                    if status >= 500:
                        continue
                    raise RuntimeError(f"LLM call failed: HTTP {status}: {message}") from exc
                except Exception as exc:  # noqa: BLE001
                    text = str(exc)
                    if "CERTIFICATE_VERIFY_FAILED" in text:
                        hint = "Set RELEASE_LLM_CA_BUNDLE (or SSL_CERT_FILE) to a trusted CA bundle. For local dry-run only, use RELEASE_LLM_INSECURE_SKIP_VERIFY=1."
                        raise RuntimeError(f"LLM TLS certificate verify failed: {exc}. {hint}") from exc
                    failures.append(f"{endpoint}: {text}")
                    continue

    if failures:
        brief = " | ".join(failures[-4:])
        raise RuntimeError(f"LLM call failed after retries: {brief}")
    raise RuntimeError("LLM call failed")
