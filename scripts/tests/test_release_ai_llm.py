import io
import json
import os
import unittest
import urllib.error
from unittest import mock

from scripts.release_ai_llm import llm_config, openai_chat_json


class _FakeResponse:
    def __init__(self, payload: dict[str, object]) -> None:
        self._payload = payload

    def __enter__(self) -> "_FakeResponse":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:  # type: ignore[no-untyped-def]
        return False

    def read(self) -> bytes:
        return json.dumps(self._payload).encode("utf-8")


class ReleaseAiLlmTests(unittest.TestCase):
    def test_llm_config_reads_optional_endpoint_and_auth(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "RELEASE_LLM_API_KEY": "k-test",
                "RELEASE_LLM_MODEL": "gpt-test",
                "RELEASE_LLM_BASE_URL": "https://gateway.example/v1/",
                "RELEASE_LLM_ENDPOINT": "https://gateway.example/v1/chat/completions",
                "RELEASE_LLM_AUTH_HEADER": "x-token",
                "RELEASE_LLM_AUTH_SCHEME": "",
                "RELEASE_LLM_TIMEOUT_SECONDS": "45",
                "RELEASE_LLM_MAX_RETRIES": "4",
            },
            clear=False,
        ):
            config = llm_config()

        self.assertEqual(config["base_url"], "https://gateway.example/v1")
        self.assertEqual(config["endpoint"], "https://gateway.example/v1/chat/completions")
        self.assertEqual(config["auth_header"], "x-token")
        self.assertEqual(config["auth_scheme"], "")
        self.assertEqual(config["timeout_seconds"], 45)
        self.assertEqual(config["retries"], 4)

    def test_llm_config_uses_300s_default_timeout(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "RELEASE_LLM_API_KEY": "k-test",
                "RELEASE_LLM_MODEL": "gpt-test",
            },
            clear=False,
        ):
            config = llm_config()

        self.assertEqual(config["timeout_seconds"], 300)

    def test_llm_config_normalizes_literal_secret_values(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "RELEASE_LLM_API_KEY": "RELEASE_LLM_API_KEY='k-test'",
                "RELEASE_LLM_MODEL": "RELEASE_LLM_MODEL=\"gpt-test\"",
                "RELEASE_LLM_BASE_URL": "RELEASE_LLM_BASE_URL=https://gateway.example/v1/",
                "RELEASE_LLM_ENDPOINT": "RELEASE_LLM_ENDPOINT='https://gateway.example/v1/chat/completions'",
            },
            clear=False,
        ):
            config = llm_config()

        self.assertEqual(config["api_key"], "k-test")
        self.assertEqual(config["model"], "gpt-test")
        self.assertEqual(config["base_url"], "https://gateway.example/v1")
        self.assertEqual(config["endpoint"], "https://gateway.example/v1/chat/completions")

    def test_openai_chat_json_fallbacks_to_responses_and_api_key(self) -> None:
        calls: list[tuple[str, dict[str, str], dict[str, object]]] = []

        def fake_urlopen(request, **_kwargs):  # type: ignore[no-untyped-def]
            headers = {key.lower(): value for key, value in request.header_items()}
            payload = json.loads(request.data.decode("utf-8"))
            calls.append((request.full_url, headers, payload))

            if request.full_url.endswith("/chat/completions"):
                body = io.BytesIO(b'{"error":{"message":"forbidden"}}')
                raise urllib.error.HTTPError(request.full_url, 403, "Forbidden", hdrs=None, fp=body)

            if request.full_url.endswith("/responses") and "api-key" in headers:
                return _FakeResponse(
                    {
                        "output_text": "{\"bump\":\"patch\",\"reason\":\"fallback\",\"confidence\":0.9,\"evidence_change_ids\":[]}",
                    }
                )

            body = io.BytesIO(b'{"error":{"message":"forbidden"}}')
            raise urllib.error.HTTPError(request.full_url, 403, "Forbidden", hdrs=None, fp=body)

        config = {
            "api_key": "k-test",
            "model": "gpt-test",
            "base_url": "https://gateway.example/v1",
            "endpoint": "",
            "timeout_seconds": 10,
            "retries": 0,
            "ca_bundle": "",
            "insecure_skip_verify": False,
            "auth_header": "",
            "auth_scheme": "Bearer",
        }

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            result = openai_chat_json(
                messages=[
                    {"role": "system", "content": "sys"},
                    {"role": "user", "content": "user"},
                ],
                config=config,
            )

        self.assertEqual(result["bump"], "patch")

        chat_calls = [entry for entry in calls if entry[0].endswith("/chat/completions")]
        response_calls = [entry for entry in calls if entry[0].endswith("/responses")]
        self.assertGreaterEqual(len(chat_calls), 1)
        self.assertGreaterEqual(len(response_calls), 1)

        for _, _, payload in chat_calls:
            self.assertIn("messages", payload)
            self.assertNotIn("input", payload)

        used_api_key = any("api-key" in headers for _, headers, _ in response_calls)
        self.assertTrue(used_api_key)
        for _, _, payload in response_calls:
            self.assertIn("input", payload)
            self.assertNotIn("messages", payload)

    def test_openai_chat_json_supports_custom_auth_header(self) -> None:
        def fake_urlopen(request, **_kwargs):  # type: ignore[no-untyped-def]
            headers = {key.lower(): value for key, value in request.header_items()}
            self.assertEqual(request.full_url, "https://gateway.example/custom-endpoint")
            self.assertEqual(headers.get("x-token"), "token-123")
            self.assertNotIn("authorization", headers)
            payload = json.loads(request.data.decode("utf-8"))
            self.assertIn("messages", payload)
            return _FakeResponse(
                {
                    "choices": [
                        {
                            "message": {
                                "content": "{\"bump\":\"minor\",\"reason\":\"custom\",\"confidence\":0.8,\"evidence_change_ids\":[\"pr#1\"]}",
                            }
                        }
                    ]
                }
            )

        config = {
            "api_key": "token-123",
            "model": "gpt-test",
            "base_url": "https://unused.example/v1",
            "endpoint": "https://gateway.example/custom-endpoint",
            "timeout_seconds": 10,
            "retries": 0,
            "ca_bundle": "",
            "insecure_skip_verify": False,
            "auth_header": "x-token",
            "auth_scheme": "",
        }

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            result = openai_chat_json(
                messages=[{"role": "user", "content": "hello"}],
                config=config,
            )

        self.assertEqual(result["bump"], "minor")


if __name__ == "__main__":
    unittest.main()
