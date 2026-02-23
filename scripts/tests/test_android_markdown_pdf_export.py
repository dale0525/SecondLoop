from __future__ import annotations

from pathlib import Path
import re
import unittest


class AndroidMarkdownPdfExportTests(unittest.TestCase):
    def _handler_source(self) -> str:
        handler_path = (
            Path(__file__).resolve().parents[2]
            / "android/app/src/main/kotlin/com/secondloop/secondloop/MarkdownPdfExportChannelHandler.kt"
        )
        return handler_path.read_text(encoding="utf-8")

    def test_handler_avoids_hidden_print_callback_constructors(self) -> None:
        source = self._handler_source()

        self.assertIsNone(
            re.search(r"LayoutResultCallback\s*\(\s*\)", source),
            "LayoutResultCallback() constructor is hidden on compileSdkVersion 35",
        )
        self.assertIsNone(
            re.search(r"WriteResultCallback\s*\(\s*\)", source),
            "WriteResultCallback() constructor is hidden on compileSdkVersion 35",
        )


if __name__ == "__main__":
    unittest.main()
