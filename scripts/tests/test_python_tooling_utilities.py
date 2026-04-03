from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_module(module_name: str, relative_path: str):
    module_path = REPO_ROOT / relative_path
    spec = spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load module from {module_path}")
    module = module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


CHECK_ICON_CORNERS = _load_module("check_icon_corners_tool", "tools/check_icon_corners.py")
ROUND_ICON = _load_module("round_icon_tool", "tools/round_icon.py")
WEEK11_GATEWAY_SMOKE = _load_module("week11_gateway_smoke_tool", "tools/week11_gateway_smoke.py")


class CheckIconCornersTests(unittest.TestCase):
    def test_main_accepts_transparent_corners_and_opaque_center(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            image_path = Path(temp_dir) / "icon.png"
            image = Image.new("RGBA", (8, 8), (0, 0, 0, 255))
            for x, y in [(0, 0), (7, 0), (0, 7), (7, 7)]:
                image.putpixel((x, y), (0, 0, 0, 0))
            image.save(image_path)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch("sys.argv", ["check_icon_corners.py", "--path", image_path.as_posix()]):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    status = CHECK_ICON_CORNERS.main()

        self.assertEqual(status, 0, msg=stderr.getvalue())
        self.assertIn("OK:", stdout.getvalue())

    def test_main_rejects_opaque_corners(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            image_path = Path(temp_dir) / "icon.png"
            image = Image.new("RGBA", (8, 8), (0, 0, 0, 255))
            image.save(image_path)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch("sys.argv", ["check_icon_corners.py", "--path", image_path.as_posix()]):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    status = CHECK_ICON_CORNERS.main()

        self.assertEqual(status, 1)
        self.assertIn("Corners are not transparent enough", stderr.getvalue())


class RoundIconTests(unittest.TestCase):
    def test_main_writes_rounded_output_with_transparent_corners(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.png"
            output_path = Path(temp_dir) / "output.png"
            Image.new("RGBA", (12, 12), (255, 0, 0, 255)).save(input_path)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch(
                "sys.argv",
                [
                    "round_icon.py",
                    "--in",
                    input_path.as_posix(),
                    "--out",
                    output_path.as_posix(),
                    "--radius",
                    "3",
                ],
            ):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    status = ROUND_ICON.main()

            output = Image.open(output_path).convert("RGBA")

        self.assertEqual(status, 0, msg=stderr.getvalue())
        self.assertEqual(output.getpixel((0, 0))[3], 0)
        self.assertGreater(output.getpixel((6, 6))[3], 0)
        self.assertIn("Wrote", stdout.getvalue())

    def test_main_rejects_non_positive_radius(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.png"
            output_path = Path(temp_dir) / "output.png"
            Image.new("RGBA", (12, 12), (255, 0, 0, 255)).save(input_path)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch(
                "sys.argv",
                [
                    "round_icon.py",
                    "--in",
                    input_path.as_posix(),
                    "--out",
                    output_path.as_posix(),
                    "--radius",
                    "0",
                ],
            ):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    status = ROUND_ICON.main()

        self.assertEqual(status, 2)
        self.assertIn("radius must be > 0", stderr.getvalue())


class Week11GatewaySmokeTests(unittest.TestCase):
    def test_resolve_api_key_reads_default_google_services_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            json_path = Path(temp_dir) / "google-services.json"
            json_path.write_text(
                json.dumps({"client": [{"api_key": [{"current_key": "abc123"}]}]}),
                encoding="utf-8",
            )
            args = type("Args", (), {"firebase_api_key": None})()

            with patch.dict(os.environ, {"SECONDLOOP_GOOGLE_SERVICES_JSON": json_path.as_posix()}, clear=False):
                resolved = WEEK11_GATEWAY_SMOKE._resolve_api_key(args)

        self.assertEqual(resolved, "abc123")

    def test_resolve_gateway_base_url_uses_cloud_env_specific_variable(self) -> None:
        args = type("Args", (), {"gateway_base_url": None})()

        with patch.dict(
            os.environ,
            {
                "SECONDLOOP_CLOUD_ENV": "staging",
                "SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING": "https://staging.example.com",
                "SECONDLOOP_CLOUD_GATEWAY_BASE_URL": "",
            },
            clear=False,
        ):
            resolved = WEEK11_GATEWAY_SMOKE._resolve_gateway_base_url(args)

        self.assertEqual(resolved, "https://staging.example.com")

    def test_extract_error_falls_back_to_json_text(self) -> None:
        error = WEEK11_GATEWAY_SMOKE._extract_error(None, '{"error":"gateway denied"}')
        self.assertEqual(error, "gateway denied")
