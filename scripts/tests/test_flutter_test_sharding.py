from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SHARD_SCRIPT = REPO_ROOT / "scripts/select_flutter_test_targets.sh"


@unittest.skipUnless(shutil.which("bash"), "bash is required")
class FlutterTestShardingTests(unittest.TestCase):
    def _run_shard(self, repo_root: Path, shard_index: int, shard_count: int) -> list[str]:
        result = subprocess.run(
            [
                "bash",
                SHARD_SCRIPT.as_posix(),
                "--repo-root",
                repo_root.as_posix(),
                "--shard-index",
                str(shard_index),
                "--shard-count",
                str(shard_count),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]

    def test_select_flutter_test_targets_uses_round_robin_shards(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            (repo_root / "integration_test").mkdir(parents=True)
            (repo_root / "test/nested").mkdir(parents=True)
            (repo_root / "test/support").mkdir(parents=True)

            for relative_path in [
                "integration_test/alpha_test.dart",
                "test/beta_test.dart",
                "test/nested/gamma_test.dart",
                "test/support/helper.dart",
            ]:
                (repo_root / relative_path).write_text("// stub\n", encoding="utf-8")

            shard_zero = self._run_shard(repo_root, 0, 2)
            shard_one = self._run_shard(repo_root, 1, 2)

        self.assertEqual(
            shard_zero,
            [
                "integration_test/alpha_test.dart",
                "test/nested/gamma_test.dart",
            ],
        )
        self.assertEqual(shard_one, ["test/beta_test.dart"])

    def test_select_flutter_test_targets_rejects_out_of_range_shard_index(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            (repo_root / "test").mkdir(parents=True)
            (repo_root / "test/sample_test.dart").write_text("// stub\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    SHARD_SCRIPT.as_posix(),
                    "--repo-root",
                    repo_root.as_posix(),
                    "--shard-index",
                    "2",
                    "--shard-count",
                    "2",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shard-index must be between 0 and shard-count - 1", result.stderr)

    def test_select_flutter_test_targets_allows_missing_integration_test_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            (repo_root / "test").mkdir(parents=True)
            (repo_root / "test/sample_test.dart").write_text("// stub\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    SHARD_SCRIPT.as_posix(),
                    "--repo-root",
                    repo_root.as_posix(),
                    "--shard-index",
                    "0",
                    "--shard-count",
                    "1",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.strip(), "test/sample_test.dart")

    def test_select_flutter_test_targets_excludes_test_driver_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            (repo_root / "test").mkdir(parents=True)
            (repo_root / "test_driver").mkdir(parents=True)
            (repo_root / "test/sample_test.dart").write_text("// stub\n", encoding="utf-8")
            (repo_root / "test_driver/integration_test.dart").write_text(
                "// driver\n",
                encoding="utf-8",
            )

            shard_targets = self._run_shard(repo_root, 0, 1)

        self.assertEqual(shard_targets, ["test/sample_test.dart"])


if __name__ == "__main__":
    unittest.main()
