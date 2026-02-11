import argparse
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.release_ai import (
    _command_collect_facts,
    SemVer,
    bump_semver,
    classify_change,
    find_latest_published_semver_tag,
    find_latest_semver_tag,
    parse_semver_tag,
    validate_locale_notes,
)


class SemVerTests(unittest.TestCase):
    def test_parse_semver_tag(self) -> None:
        self.assertEqual(parse_semver_tag("v1.2.3"), SemVer(1, 2, 3))
        self.assertIsNone(parse_semver_tag("v1.2"))
        self.assertIsNone(parse_semver_tag("v1.2.3.4"))

    def test_find_latest_semver_tag(self) -> None:
        tags = ["v0.1.9", "desktop-runtime-v1.2.3", "v1.2.0", "v1.1.99"]
        self.assertEqual(find_latest_semver_tag(tags), "v1.2.0")

    def test_bump_semver(self) -> None:
        base = SemVer(1, 2, 3)
        self.assertEqual(bump_semver(base, "patch"), SemVer(1, 2, 4))
        self.assertEqual(bump_semver(base, "minor"), SemVer(1, 3, 0))
        self.assertEqual(bump_semver(base, "major"), SemVer(2, 0, 0))


class ClassificationTests(unittest.TestCase):
    def test_classify_change_prefers_breaking(self) -> None:
        classification = classify_change(
            title="feat!: remove legacy auth",
            body="BREAKING CHANGE: old tokens removed",
            labels=["feature", "breaking"],
        )
        self.assertEqual(classification, "breaking")

    def test_classify_change_feature_and_fix(self) -> None:
        self.assertEqual(
            classify_change(
                title="feat(settings): add cloud sync",
                body="",
                labels=["enhancement"],
            ),
            "feature",
        )
        self.assertEqual(
            classify_change(
                title="fix(sync): retry uploads",
                body="",
                labels=["bug"],
            ),
            "fix",
        )


class ValidationTests(unittest.TestCase):
    def test_validate_locale_notes_requires_full_coverage(self) -> None:
        notes = {
            "locale": "en-US",
            "version": "v1.2.3",
            "sections": [
                {
                    "key": "feature",
                    "title": "New",
                    "items": [
                        {"text": "Added X", "change_ids": ["pr#1"]},
                    ],
                }
            ],
        }
        self.assertEqual(
            validate_locale_notes(
                notes,
                expected_locale="en-US",
                expected_version="v1.2.3",
                required_change_ids=["pr#1"],
            ),
            {"pr#1"},
        )

        with self.assertRaisesRegex(ValueError, "missing change ids"):
            validate_locale_notes(
                notes,
                expected_locale="en-US",
                expected_version="v1.2.3",
                required_change_ids=["pr#1", "pr#2"],
            )


class PublishedReleaseBaseTests(unittest.TestCase):
    def test_find_latest_published_semver_tag_skips_current_draft_and_prerelease(self) -> None:
        releases = [
            {"tag_name": "v0.4.1", "draft": False, "prerelease": False},
            {"tag_name": "v0.4.0", "draft": False, "prerelease": False},
            {"tag_name": "v0.3.9", "draft": False, "prerelease": True},
            {"tag_name": "v0.3.8", "draft": True, "prerelease": False},
            {"tag_name": "desktop-runtime-v0.1.0", "draft": False, "prerelease": False},
        ]

        self.assertEqual(
            find_latest_published_semver_tag(releases, head_tag="v0.4.1"),
            "v0.4.0",
        )

    @mock.patch("scripts.release_ai._github_token", return_value="token")
    @mock.patch("scripts.release_ai._latest_published_release_before", return_value="v0.3.0")
    @mock.patch("scripts.release_ai._collect_commits", return_value=[])
    @mock.patch("scripts.release_ai._run_git", return_value="deadbeef\n")
    def test_collect_facts_uses_published_release_base_when_requested(
        self,
        mock_run_git: mock.Mock,
        mock_collect_commits: mock.Mock,
        mock_latest_release_base: mock.Mock,
        mock_token: mock.Mock,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            output = Path(tmp_dir) / "facts.json"
            args = argparse.Namespace(
                repo="acme/secondloop",
                base_tag="auto",
                auto_base_source="github-releases",
                head="HEAD",
                head_tag="v0.4.1",
                output=str(output),
            )

            _command_collect_facts(args)

            payload = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(payload["base_tag"], "v0.3.0")
        self.assertEqual(payload["compare_range"], "v0.3.0..v0.4.1")
        mock_latest_release_base.assert_called_once_with(
            "acme/secondloop",
            "v0.4.1",
            exclude_tag="v0.4.1",
            token="token",
        )
        mock_collect_commits.assert_called_once_with("v0.3.0..v0.4.1")
        mock_run_git.assert_called_once_with(["rev-parse", "v0.4.1"])
        mock_token.assert_called_once()


if __name__ == "__main__":
    unittest.main()
