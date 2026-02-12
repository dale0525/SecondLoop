import argparse
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.release_ai import (
    _build_notes_for_locale,
    _command_collect_facts,
    _command_decide_bump,
    _command_generate_notes,
    _command_render_markdown,
    _command_validate_notes,
    _select_user_facing_changes,
    SemVer,
    bump_semver,
    classify_change,
    find_latest_published_semver_tag,
    find_latest_semver_tag,
    parse_semver_tag,
    validate_locale_notes,
)

from scripts.release_ai_release_base import fetch_repo_releases
from scripts.release_ai_curation import curate_user_facing_changes_with_llm


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

    def test_classify_change_ignores_negative_breaking_checklist(self) -> None:
        classification = classify_change(
            title="chore(release): refresh release checklist",
            body="Breaking changes: no\nQA complete: yes",
            labels=[],
        )
        self.assertEqual(classification, "chore")

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


class DecideBumpTests(unittest.TestCase):
    @mock.patch("scripts.release_ai._llm_config", return_value={"model": "gpt-test"})
    @mock.patch(
        "scripts.release_ai._openai_chat_json",
        return_value={
            "bump": "minor",
            "reason": "Internal pipeline breaking label should not force major.",
            "confidence": 0.95,
            "evidence_change_ids": ["pr#24"],
        },
    )
    def test_decide_bump_allows_llm_minor_when_breaking_label_exists(
        self,
        _mock_openai_chat_json: mock.Mock,
        _mock_llm_config: mock.Mock,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            facts_path = Path(tmp_dir) / "facts.json"
            output_path = Path(tmp_dir) / "decision.json"
            facts_path.write_text(
                json.dumps(
                    {
                        "base_tag": "v0.1.0",
                        "head": "HEAD",
                        "stats": {"change_count": 1},
                        "changes": [
                            {
                                "id": "pr#24",
                                "type": "breaking",
                                "title": "fix(release): internal pipeline cleanup",
                                "description": "Non-user-facing release infra change",
                                "labels": ["breaking"],
                                "source": "pull_request",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            _command_decide_bump(
                argparse.Namespace(
                    facts=str(facts_path),
                    output=str(output_path),
                )
            )

            decision = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(decision["bump"], "minor")
        self.assertTrue(decision["has_breaking_change"])

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


class ReleaseFetchTests(unittest.TestCase):
    def test_fetch_repo_releases_handles_pagination(self) -> None:
        calls: list[str] = []

        def github_get(path: str) -> object:
            calls.append(path)
            if path.endswith("page=1"):
                return [
                    {
                        "tag_name": f"v0.1.{index}",
                        "draft": False,
                        "prerelease": False,
                    }
                    for index in range(100)
                ]
            if path.endswith("page=2"):
                return [
                    {"tag_name": "v0.2.0", "draft": False, "prerelease": False},
                    {"tag_name": "v0.2.1", "draft": False, "prerelease": False},
                ]
            self.fail(f"unexpected path: {path}")

        releases = fetch_repo_releases("acme/secondloop", github_get=github_get)

        self.assertEqual(len(releases), 102)
        self.assertEqual(
            calls,
            [
                "/repos/acme/secondloop/releases?per_page=100&page=1",
                "/repos/acme/secondloop/releases?per_page=100&page=2",
            ],
        )

    def test_fetch_repo_releases_surfaces_github_api_error(self) -> None:
        def github_get(_: str) -> object:
            return {"message": "Forbidden"}

        with self.assertRaisesRegex(
            RuntimeError,
            "GitHub API error for acme/secondloop: Forbidden",
        ):
            fetch_repo_releases("acme/secondloop", github_get=github_get)

    def test_fetch_repo_releases_rejects_unexpected_payload_type(self) -> None:
        def github_get(_: str) -> object:
            return "invalid"

        with self.assertRaisesRegex(
            RuntimeError,
            "unexpected GitHub releases response type: str",
        ):
            fetch_repo_releases("acme/secondloop", github_get=github_get)


class RenderMarkdownTests(unittest.TestCase):
    def test_render_markdown_uses_language_name_and_reference_links(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            notes_dir = Path(tmp_dir)
            note_path = notes_dir / "release-notes-v1.2.3-en_US.json"
            note_path.write_text(
                json.dumps(
                    {
                        "locale": "en_US",
                        "version": "v1.2.3",
                        "summary": "Summary text",
                        "highlights": [
                            {
                                "text": "Highlight text",
                                "change_ids": ["pr#1"],
                            }
                        ],
                        "sections": [
                            {
                                "key": "fix",
                                "title": "Fixes",
                                "items": [
                                    {
                                        "text": "Fixed crash",
                                        "change_ids": ["commit:c6b1cc9"],
                                    }
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            facts_path = notes_dir / "facts.json"
            facts_path.write_text(
                json.dumps(
                    {
                        "changes": [
                            {
                                "id": "pr#1",
                                "url": "https://github.com/acme/secondloop/pull/1",
                            },
                            {
                                "id": "commit:c6b1cc9",
                                "url": "https://github.com/acme/secondloop/commit/c6b1cc9deadbeef",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            output_path = notes_dir / "release-notes.md"
            args = argparse.Namespace(
                tag="v1.2.3",
                locales="en_US",
                notes_dir=str(notes_dir),
                output=str(output_path),
                facts=str(facts_path),
            )

            _command_render_markdown(args)
            content = output_path.read_text(encoding="utf-8")

        self.assertIn("## English", content)
        self.assertNotIn("## en_US", content)
        self.assertIn("[pr#1](https://github.com/acme/secondloop/pull/1)", content)
        self.assertIn("[commit:c6b1cc9](https://github.com/acme/secondloop/commit/c6b1cc9deadbeef)", content)


class UserFacingSelectionTests(unittest.TestCase):
    def test_select_user_facing_changes_excludes_technical_only_items(self) -> None:
        changes = [
            {
                "id": "pr#1",
                "type": "fix",
                "title": "fix(ci): stabilize release workflow",
                "description": "Adjust CI timeout and workflow details",
                "labels": ["ci", "infrastructure"],
            },
            {
                "id": "pr#2",
                "type": "feature",
                "title": "feat(app): add release notes dialog",
                "description": "Show release notes to users after update",
                "labels": ["feature"],
            },
        ]

        selected = _select_user_facing_changes(changes)
        self.assertEqual([change["id"] for change in selected], ["pr#2"])

    def test_build_notes_skips_llm_when_no_user_facing_changes(self) -> None:
        facts = {
            "changes": [
                {
                    "id": "pr#9",
                    "type": "fix",
                    "title": "fix(ci): release workflow retry logic",
                    "description": "Internal pipeline tuning",
                    "labels": ["ci"],
                }
            ]
        }

        with mock.patch("scripts.release_ai._translate_notes_with_llm") as mock_translate:
            notes = _build_notes_for_locale(
                facts=facts,
                locale="en-US",
                tag="v1.2.3",
                config={"api_key": "k", "model": "m"},
            )

        mock_translate.assert_not_called()
        self.assertEqual(notes["sections"], [])
        self.assertEqual(notes["highlights"], [])
        self.assertIn("maintenance", notes["summary"].lower())



class NotesManifestCurationTests(unittest.TestCase):
    def test_generate_notes_records_curated_change_ids(self) -> None:
        facts = {
            "changes": [
                {
                    "id": "pr#20",
                    "type": "breaking",
                    "title": "fix(windows): WinRT header and artifact naming",
                    "description": "Internal Windows build fix",
                    "labels": ["ci", "build"],
                },
                {
                    "id": "pr#21",
                    "type": "feature",
                    "title": "feat(app): first launch release notes dialog",
                    "description": "Show update notes after app update",
                    "labels": ["feature"],
                },
            ]
        }

        with tempfile.TemporaryDirectory() as tmp_dir:
            facts_path = Path(tmp_dir) / "facts.json"
            facts_path.write_text(json.dumps(facts), encoding="utf-8")

            output_dir = Path(tmp_dir) / "notes"
            args = argparse.Namespace(
                facts=str(facts_path),
                tag="v1.0.1",
                locales="en-US",
                output_dir=str(output_dir),
            )

            def fake_build_notes_for_locale(*, facts, locale, tag, config):  # type: ignore[no-untyped-def]
                self.assertTrue(facts.get("changes_curated"))
                self.assertEqual([change["id"] for change in facts["changes"]], ["pr#21"])
                self.assertEqual(locale, "en-US")
                self.assertEqual(tag, "v1.0.1")
                self.assertEqual(config["model"], "gpt-test")
                return {
                    "locale": "en-US",
                    "version": "v1.0.1",
                    "summary": "Summary",
                    "highlights": [],
                    "sections": [
                        {
                            "key": "feature",
                            "title": "New Features",
                            "items": [{"text": "Show update notes", "change_ids": ["pr#21"]}],
                        }
                    ],
                }

            with (
                mock.patch("scripts.release_ai._llm_config", return_value={"model": "gpt-test"}),
                mock.patch(
                    "scripts.release_ai.curate_user_facing_changes_with_llm",
                    return_value=[dict(facts["changes"][1])],
                ),
                mock.patch(
                    "scripts.release_ai._build_notes_for_locale",
                    side_effect=fake_build_notes_for_locale,
                ),
            ):
                _command_generate_notes(args)

            manifest_path = output_dir / "release-notes-v1.0.1-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

        self.assertEqual(manifest["included_change_ids"], ["pr#21"])

    def test_validate_notes_prefers_manifest_included_change_ids(self) -> None:
        facts = {
            "changes": [
                {
                    "id": "pr#1",
                    "type": "feature",
                    "title": "feat(app): add release notes dialog",
                    "description": "Show release notes to users after update",
                    "labels": ["feature"],
                },
                {
                    "id": "pr#2",
                    "type": "feature",
                    "title": "feat(app): add premium banner",
                    "description": "Show premium upsell to users",
                    "labels": ["feature"],
                },
            ]
        }

        notes = {
            "locale": "en-US",
            "version": "v1.0.1",
            "summary": "Summary",
            "highlights": [],
            "sections": [
                {
                    "key": "feature",
                    "title": "New Features",
                    "items": [{"text": "Added release notes dialog", "change_ids": ["pr#1"]}],
                }
            ],
        }

        with tempfile.TemporaryDirectory() as tmp_dir:
            notes_dir = Path(tmp_dir)
            facts_path = notes_dir / "facts.json"
            facts_path.write_text(json.dumps(facts), encoding="utf-8")

            note_path = notes_dir / "release-notes-v1.0.1-en-US.json"
            note_path.write_text(json.dumps(notes), encoding="utf-8")
            note_sha = hashlib.sha256(note_path.read_bytes()).hexdigest()

            manifest_path = notes_dir / "release-notes-v1.0.1-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "version": "v1.0.1",
                        "included_change_ids": ["pr#1"],
                        "notes": [{"file": note_path.name, "sha256": note_sha}],
                    }
                ),
                encoding="utf-8",
            )

            args = argparse.Namespace(
                facts=str(facts_path),
                tag="v1.0.1",
                locales="en-US",
                notes_dir=str(notes_dir),
            )

            _command_validate_notes(args)


class LlmCurationTests(unittest.TestCase):
    def test_llm_curation_filters_technical_breaking_change(self) -> None:
        changes = [
            {
                "id": "pr#20",
                "type": "breaking",
                "title": "fix(windows): WinRT header and artifact naming",
                "description": "Internal Windows build fix",
                "labels": ["ci", "build"],
            },
            {
                "id": "pr#21",
                "type": "feature",
                "title": "feat(app): first launch release notes dialog",
                "description": "Show update notes after app update",
                "labels": ["feature"],
            },
        ]

        def fake_llm_call(messages, *, config):  # type: ignore[no-untyped-def]
            self.assertEqual(config["model"], "gpt-test")
            self.assertTrue(messages)
            return {
                "items": [
                    {"change_id": "pr#20", "include": False, "type": "chore"},
                    {"change_id": "pr#21", "include": True, "type": "feature"},
                ]
            }

        curated = curate_user_facing_changes_with_llm(
            changes=changes,
            tag="v1.0.1",
            config={"model": "gpt-test"},
            llm_call=fake_llm_call,
        )

        self.assertEqual([change["id"] for change in curated], ["pr#21"])
        self.assertEqual(curated[0]["type"], "feature")



if __name__ == "__main__":
    unittest.main()
