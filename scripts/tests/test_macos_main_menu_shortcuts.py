from __future__ import annotations

from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parents[2]
MAIN_MENU_XIB = REPO_ROOT / "macos/Runner/Base.lproj/MainMenu.xib"


class MacOsMainMenuShortcutTests(unittest.TestCase):
    def _find_menu_item(self, title: str) -> ET.Element:
        tree = ET.parse(MAIN_MENU_XIB)
        root = tree.getroot()
        for menu_item in root.iter("menuItem"):
            if menu_item.attrib.get("title") == title:
                return menu_item
        self.fail(f"Unable to find menu item: {title}")

    def test_select_all_uses_command_a_shortcut(self) -> None:
        menu_item = self._find_menu_item("Select All")

        self.assertEqual(menu_item.attrib.get("keyEquivalent"), "a")

        modifier_mask = menu_item.find("modifierMask")
        self.assertIsNotNone(modifier_mask)
        assert modifier_mask is not None
        self.assertEqual(
            modifier_mask.attrib.get("key"),
            "keyEquivalentModifierMask",
        )
        self.assertEqual(modifier_mask.attrib.get("command"), "YES")
        self.assertNotEqual(modifier_mask.attrib.get("option"), "YES")
        self.assertNotEqual(modifier_mask.attrib.get("control"), "YES")


if __name__ == "__main__":
    unittest.main()
