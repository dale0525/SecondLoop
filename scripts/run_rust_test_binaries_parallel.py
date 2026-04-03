from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


_PRIORITY_TESTS = [
    "sync_managed_vault_embedding_artifact_roundtrip",
    "sync_managed_vault_smoke",
    "todo_followup_suggestions_smoke",
    "sync_managed_vault_pull_bin_smoke",
    "recurring_todo_sync",
    "sync_managed_vault_push_conflict_rebase",
    "embedding_probe_caching",
]


@dataclass(frozen=True)
class RustTestBinary:
    name: str
    executable: str


def load_test_binaries(jsonl_path: Path) -> list[RustTestBinary]:
    seen_paths: set[str] = set()
    binaries: list[RustTestBinary] = []

    with jsonl_path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue

            if payload.get("reason") != "compiler-artifact":
                continue
            if not payload.get("profile", {}).get("test", False):
                continue

            executable = payload.get("executable")
            target = payload.get("target") or {}
            name = target.get("name")
            if not isinstance(executable, str) or not executable:
                continue
            if not isinstance(name, str) or not name:
                continue
            if executable in seen_paths:
                continue

            seen_paths.add(executable)
            binaries.append(RustTestBinary(name=name, executable=executable))

    return binaries


def prioritize_test_binaries(
    binaries: list[RustTestBinary],
) -> list[RustTestBinary]:
    priority_index = {name: index for index, name in enumerate(_PRIORITY_TESTS)}
    return sorted(
        binaries,
        key=lambda binary: (priority_index.get(binary.name, len(priority_index)), binary.name),
    )


def _run_binary(binary: RustTestBinary) -> tuple[RustTestBinary, float, int, str, str]:
    start = time.perf_counter()
    completed = subprocess.run(
        [binary.executable],
        capture_output=True,
        text=True,
        errors="replace",
        env=os.environ.copy(),
    )
    duration = time.perf_counter() - start
    return binary, duration, completed.returncode, completed.stdout, completed.stderr


def run_test_binaries(
    binaries: list[RustTestBinary],
    *,
    jobs: int,
) -> int:
    failures: list[tuple[RustTestBinary, float, int, str, str]] = []

    with ThreadPoolExecutor(max_workers=max(1, jobs)) as executor:
        futures = {}
        for binary in binaries:
            print(f"rust-test: starting {binary.name}", flush=True)
            futures[executor.submit(_run_binary, binary)] = binary

        for future in as_completed(futures):
            binary, duration, return_code, stdout_text, stderr_text = future.result()
            print(
                f"rust-test: finished {binary.name} in {duration:.1f}s (exit={return_code})",
                flush=True,
            )
            if return_code != 0:
                failures.append((binary, duration, return_code, stdout_text, stderr_text))

    if not failures:
        return 0

    for binary, duration, return_code, stdout_text, stderr_text in failures:
        print(
            f"rust-test: failure {binary.name} in {duration:.1f}s (exit={return_code})",
            file=sys.stderr,
        )
        if stdout_text.strip():
            print(stdout_text, file=sys.stderr, end="" if stdout_text.endswith("\n") else "\n")
        if stderr_text.strip():
            print(stderr_text, file=sys.stderr, end="" if stderr_text.endswith("\n") else "\n")

    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--max-binaries", type=int, default=0)
    args = parser.parse_args(argv)

    binaries = prioritize_test_binaries(load_test_binaries(Path(args.jsonl)))
    if args.max_binaries > 0:
        binaries = binaries[: args.max_binaries]

    if not binaries:
        print("rust-test: no test binaries discovered", flush=True)
        return 0

    return run_test_binaries(binaries, jobs=args.jobs)


if __name__ == "__main__":
    raise SystemExit(main())
