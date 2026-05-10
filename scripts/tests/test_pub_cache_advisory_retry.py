from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
PUB_GET_RETRY_SCRIPT = REPO_ROOT / "scripts/flutter_pub_get_with_retry.sh"


class PubCacheAdvisoryRetryTests(unittest.TestCase):
    def _load_pixi_config(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            return tomllib.load(fh)

    def test_setup_flutter_uses_pub_get_retry_wrapper(self) -> None:
        pixi_config = self._load_pixi_config()

        setup_flutter = pixi_config["tasks"]["setup-flutter"]

        self.assertIn("bash scripts/flutter_pub_get_with_retry.sh", setup_flutter)
        self.assertNotIn("fvm:main flutter pub get", setup_flutter)

    def test_pub_get_retry_wrapper_clears_hosted_advisory_cache(self) -> None:
        script = PUB_GET_RETRY_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("*-advisories.json", script)
        self.assertIn("PUB_CACHE", script)
        self.assertIn("retrying once", script)


if __name__ == "__main__":
    unittest.main()
