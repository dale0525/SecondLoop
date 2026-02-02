#!/usr/bin/env python3
import argparse
import getpass
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

_DEFAULT_USER_AGENT = os.getenv("SECONDLOOP_SMOKE_UA", "").strip() or "curl/8.4.0"


@dataclass(frozen=True)
class FirebaseSession:
    email: str
    uid: str
    id_token: str


def _read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _resolve_api_key(args: argparse.Namespace) -> str:
    if args.firebase_api_key:
        return args.firebase_api_key

    from_env = os.getenv("SECONDLOOP_FIREBASE_WEB_API_KEY", "").strip()
    if from_env:
        return from_env

    default_path = os.getenv("SECONDLOOP_GOOGLE_SERVICES_JSON", ".tool/firebase/google-services.json")
    try:
        cfg = _read_json(default_path)
        key = (
            cfg.get("client", [{}])[0]
            .get("api_key", [{}])[0]
            .get("current_key", "")
        )
        key = str(key).strip()
        if key:
            return key
    except Exception:
        pass

    raise SystemExit(
        "Missing firebase web api key. Set SECONDLOOP_FIREBASE_WEB_API_KEY or pass --firebase-api-key."
    )


def _resolve_gateway_base_url(args: argparse.Namespace) -> str:
    if args.gateway_base_url:
        return args.gateway_base_url
    from_env = os.getenv("SECONDLOOP_CLOUD_GATEWAY_BASE_URL", "").strip()
    if from_env:
        return from_env
    cloud_env = os.getenv("SECONDLOOP_CLOUD_ENV", "").strip().lower()
    if cloud_env:
        if cloud_env == "staging":
            derived = os.getenv("SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING", "").strip()
        elif cloud_env == "prod":
            derived = os.getenv("SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD", "").strip()
        else:
            derived = ""
        if derived:
            return derived
    raise SystemExit(
        "Missing gateway base url. Set SECONDLOOP_CLOUD_GATEWAY_BASE_URL or pass --gateway-base-url."
    )


def _post_json(url: str, payload: dict[str, Any], headers: dict[str, str] | None = None) -> tuple[int, dict[str, Any] | None, str]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "content-type": "application/json",
            "accept": "application/json",
            "user-agent": _DEFAULT_USER_AGENT,
            **(headers or {}),
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode("utf-8", errors="replace")
            return resp.status, _try_parse_json(text), text
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", errors="replace")
        return e.code, _try_parse_json(text), text


def _post_json_partial(
    url: str,
    payload: dict[str, Any],
    *,
    max_bytes: int,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, Any] | None, str]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "content-type": "application/json",
            "accept": "application/json",
            "user-agent": _DEFAULT_USER_AGENT,
            **(headers or {}),
        },
        method="POST",
    )

    max_bytes = max(1, int(max_bytes))

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            blob = resp.read(max_bytes)
            text = blob.decode("utf-8", errors="replace")
            return resp.status, _try_parse_json(text), text
    except urllib.error.HTTPError as e:
        blob = e.read(max_bytes)
        text = blob.decode("utf-8", errors="replace")
        return e.code, _try_parse_json(text), text


def _get_json(url: str, headers: dict[str, str] | None = None) -> tuple[int, dict[str, Any] | None, str]:
    req = urllib.request.Request(
        url,
        headers={
            "accept": "application/json",
            "user-agent": _DEFAULT_USER_AGENT,
            **(headers or {}),
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode("utf-8", errors="replace")
            return resp.status, _try_parse_json(text), text
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", errors="replace")
        return e.code, _try_parse_json(text), text


def _try_parse_json(text: str) -> dict[str, Any] | None:
    try:
        value = json.loads(text)
        if isinstance(value, dict):
            return value
        return None
    except Exception:
        return None


def _firebase_sign_in(api_key: str, email: str, password: str) -> FirebaseSession:
    status, body, text = _post_json(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={api_key}",
        {
            "email": email,
            "password": password,
            "returnSecureToken": True,
        },
    )
    if status != 200 or body is None:
        raise RuntimeError(f"firebase signInWithPassword failed: HTTP {status} {text[:300]}")

    id_token = body.get("idToken")
    uid = body.get("localId")
    if not isinstance(id_token, str) or not id_token.strip():
        raise RuntimeError("firebase signInWithPassword: missing idToken")
    if not isinstance(uid, str) or not uid.strip():
        raise RuntimeError("firebase signInWithPassword: missing localId")

    return FirebaseSession(email=email, uid=uid, id_token=id_token)


def _firebase_lookup(api_key: str, id_token: str) -> tuple[str | None, bool | None]:
    status, body, text = _post_json(
        f"https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={api_key}",
        {"idToken": id_token},
    )
    if status != 200 or body is None:
        raise RuntimeError(f"firebase lookup failed: HTTP {status} {text[:300]}")

    users = body.get("users")
    if isinstance(users, list) and users:
        first = users[0]
        if isinstance(first, dict):
            email = first.get("email")
            email_verified = first.get("emailVerified")
            return (
                email if isinstance(email, str) and email.strip() else None,
                email_verified if isinstance(email_verified, bool) else None,
            )

    return (None, None)


def _firebase_send_verify_email(api_key: str, id_token: str) -> None:
    status, body, text = _post_json(
        f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={api_key}",
        {"requestType": "VERIFY_EMAIL", "idToken": id_token},
    )
    if status != 200:
        raise RuntimeError(f"firebase sendOobCode failed: HTTP {status} {text[:300]}")
    _ = body


def _gateway_health(base: str) -> tuple[int, dict[str, Any] | None, str]:
    return _get_json(f"{base.rstrip('/')}/health")


def _gateway_subscription(base: str, id_token: str) -> tuple[int, dict[str, Any] | None, str]:
    return _get_json(
        f"{base.rstrip('/')}/v1/subscription",
        headers={"authorization": f"Bearer {id_token}"},
    )

def _gateway_geo_reverse(
    base: str,
    id_token: str,
    *,
    lat: float,
    lon: float,
    lang: str,
) -> tuple[int, dict[str, Any] | None, str]:
    from urllib.parse import urlencode

    query = urlencode({"lat": lat, "lon": lon, "lang": lang})
    return _get_json(
        f"{base.rstrip('/')}/v1/geo/reverse?{query}",
        headers={"authorization": f"Bearer {id_token}"},
    )


def _gateway_chat(
    base: str,
    id_token: str,
    prompt: str,
    *,
    stream: bool,
    read_bytes: int,
) -> tuple[int, dict[str, Any] | None, str]:
    payload = {
        "model": "some-expensive-model",
        "stream": stream,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 16,
    }

    accept = "text/event-stream" if stream else "application/json"
    headers = {"authorization": f"Bearer {id_token}", "accept": accept}

    if stream:
        return _post_json_partial(
            f"{base.rstrip('/')}/v1/chat/completions",
            payload,
            max_bytes=read_bytes,
            headers=headers,
        )

    return _post_json(
        f"{base.rstrip('/')}/v1/chat/completions",
        payload,
        headers=headers,
    )


def _extract_error(body: dict[str, Any] | None, fallback_text: str) -> str | None:
    if body and isinstance(body.get("error"), str):
        return body["error"]
    match = None
    try:
        import re

        match = re.search(r'"error"\\s*:\\s*"([^"]+)"', fallback_text)
    except Exception:
        match = None
    return match.group(1) if match else None


def _resolve_account_from_env_or_prompt(prefix: str) -> tuple[str, str]:
    email = os.getenv(f"{prefix}_EMAIL", "").strip()
    password = os.getenv(f"{prefix}_PASSWORD", "")
    if email and password:
        return email, password

    if not email:
        email = input(f"{prefix}_EMAIL: ").strip()
    if not password:
        password = getpass.getpass(f"{prefix}_PASSWORD: ")
    if not email or not password:
        raise SystemExit(f"Missing {prefix} credentials")
    return email, password


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Week11 staging smoke checks: Firebase REST sign-in + AI Gateway /health,/v1/subscription,/v1/geo/reverse,/v1/chat/completions",
    )
    parser.add_argument("--gateway-base-url", help="e.g. https://...workers.dev")
    parser.add_argument("--firebase-api-key", help="Firebase web api key (Identity Toolkit)")
    parser.add_argument(
        "--send-verify-email",
        action="store_true",
        help="If emailVerified=false, send a verification email via Identity Toolkit",
    )
    parser.add_argument(
        "--chat-stream",
        action="store_true",
        help="Use stream=true for /v1/chat/completions (reads only first bytes)",
    )
    parser.add_argument(
        "--chat-read-bytes",
        type=int,
        default=2048,
        help="Max bytes to read from /v1/chat/completions response in stream mode",
    )
    parser.add_argument(
        "--geo-lat",
        type=float,
        default=None,
        help="If set, also call GET /v1/geo/reverse with this latitude",
    )
    parser.add_argument(
        "--geo-lon",
        type=float,
        default=None,
        help="If set, also call GET /v1/geo/reverse with this longitude",
    )
    parser.add_argument(
        "--geo-lang",
        default="en",
        help="Language tag for /v1/geo/reverse (default: en)",
    )
    parser.add_argument(
        "--geo-print-json",
        action="store_true",
        help="Print full JSON payload for /v1/geo/reverse",
    )
    args = parser.parse_args()

    api_key = _resolve_api_key(args)
    gateway = _resolve_gateway_base_url(args)

    health_status, health_body, health_text = _gateway_health(gateway)
    if health_status == 200 and health_body is not None and health_body.get("ok") is True:
        print("gateway /health: ok")
    else:
        # Some deployments only route the worker under `/v1/*` on a custom domain,
        # so `/health` might be handled by a different upstream (and may 403).
        print(f"gateway /health: HTTP {health_status} (skipped)")

    accounts = [
        ("ACCOUNT1",) + _resolve_account_from_env_or_prompt("ACCOUNT1"),
        ("ACCOUNT2",) + _resolve_account_from_env_or_prompt("ACCOUNT2"),
    ]

    for label, email, password in accounts:
        print(f"\n== {label} ==")
        session = _firebase_sign_in(api_key, email, password)
        lookup_email, email_verified = _firebase_lookup(api_key, session.id_token)
        print(f"firebase: uid={session.uid} email={lookup_email or email} emailVerified={email_verified}")

        if email_verified is False and args.send_verify_email:
            try:
                _firebase_send_verify_email(api_key, session.id_token)
                print("firebase: verification email sent")
            except Exception as e:
                print(f"firebase: verification email send failed: {e}")

        status, body, text = _gateway_subscription(gateway, session.id_token)
        if status == 200 and body is not None:
            print(f"gateway /v1/subscription: HTTP 200 active={body.get('active')} entitlement_id={body.get('entitlement_id')}")
        else:
            err = _extract_error(body, text) or text[:200]
            print(f"gateway /v1/subscription: HTTP {status} error={err}")

        if args.geo_lat is not None or args.geo_lon is not None:
            if args.geo_lat is None or args.geo_lon is None:
                raise SystemExit("--geo-lat and --geo-lon must be set together")

            status, body, text = _gateway_geo_reverse(
                gateway,
                session.id_token,
                lat=float(args.geo_lat),
                lon=float(args.geo_lon),
                lang=str(args.geo_lang or "en"),
            )
            if status == 200 and body is not None:
                display_name = body.get("display_name")
                city_name = None
                district_name = None
                city = body.get("city")
                district = body.get("district")
                if isinstance(city, dict):
                    city_name = city.get("name")
                if isinstance(district, dict):
                    district_name = district.get("name")

                print(
                    "gateway /v1/geo/reverse: HTTP 200 "
                    f"display_name={repr(display_name)} "
                    f"district={repr(district_name)} city={repr(city_name)}"
                )
                if args.geo_print_json:
                    print(json.dumps(body, ensure_ascii=False, indent=2))
            else:
                err = _extract_error(body, text) or text[:200]
                print(f"gateway /v1/geo/reverse: HTTP {status} error={err}")

        status, body, text = _gateway_chat(
            gateway,
            session.id_token,
            "ping",
            stream=args.chat_stream,
            read_bytes=args.chat_read_bytes,
        )
        if status == 200:
            suffix = " (stream)" if args.chat_stream else ""
            print(f"gateway /v1/chat/completions: HTTP 200{suffix} (ok)")
        else:
            err = _extract_error(body, text) or text[:200]
            print(f"gateway /v1/chat/completions: HTTP {status} error={err}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
