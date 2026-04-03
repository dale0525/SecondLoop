from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.run_rust_test_binaries_parallel import (
    RustTestBinary,
    load_test_binaries,
    prioritize_test_binaries,
)


class RunRustTestBinariesParallelTests(unittest.TestCase):
    def test_load_test_binaries_filters_and_deduplicates(self) -> None:
        payloads = [
            {
                "reason": "compiler-artifact",
                "profile": {"test": True},
                "target": {"name": "sync_managed_vault_smoke"},
                "executable": "C:/tmp/test-sync.exe",
            },
            {
                "reason": "compiler-artifact",
                "profile": {"test": True},
                "target": {"name": "duplicate-name-ignored"},
                "executable": "C:/tmp/test-sync.exe",
            },
            {
                "reason": "compiler-artifact",
                "profile": {"test": False},
                "target": {"name": "not-a-test"},
                "executable": "C:/tmp/not-a-test.exe",
            },
            {
                "reason": "build-script-executed",
                "linked_libs": [],
            },
            {
                "reason": "compiler-artifact",
                "profile": {"test": True},
                "target": {"name": "todo_followup_suggestions_smoke"},
                "executable": "C:/tmp/todo.exe",
            },
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            jsonl_path = Path(temp_dir) / "cargo-test.jsonl"
            jsonl_path.write_text(
                "\n".join(json.dumps(payload) for payload in payloads),
                encoding="utf-8",
            )

            binaries = load_test_binaries(jsonl_path)

        self.assertEqual(
            binaries,
            [
                RustTestBinary(
                    name="sync_managed_vault_smoke",
                    executable="C:/tmp/test-sync.exe",
                ),
                RustTestBinary(
                    name="todo_followup_suggestions_smoke",
                    executable="C:/tmp/todo.exe",
                ),
            ],
        )

    def test_prioritize_test_binaries_puts_known_slow_suites_first(self) -> None:
        binaries = [
            RustTestBinary(name="zeta_suite", executable="/tmp/zeta"),
            RustTestBinary(
                name="todo_followup_suggestions_smoke",
                executable="/tmp/todo",
            ),
            RustTestBinary(name="alpha_suite", executable="/tmp/alpha"),
            RustTestBinary(
                name="sync_managed_vault_embedding_artifact_roundtrip",
                executable="/tmp/roundtrip",
            ),
        ]

        prioritized = prioritize_test_binaries(binaries)

        self.assertEqual(
            [binary.name for binary in prioritized],
            [
                "sync_managed_vault_embedding_artifact_roundtrip",
                "todo_followup_suggestions_smoke",
                "alpha_suite",
                "zeta_suite",
            ],
        )


if __name__ == "__main__":
    unittest.main()
