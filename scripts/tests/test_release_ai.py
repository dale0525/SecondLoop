import unittest

from scripts.release_ai import (
    SemVer,
    bump_semver,
    classify_change,
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


if __name__ == "__main__":
    unittest.main()
