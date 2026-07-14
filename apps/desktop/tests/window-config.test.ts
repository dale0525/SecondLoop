import { describe, expect, it } from "vitest";

import { getDesktopWindowConfig } from "../src/main";

describe("Desktop window configuration", () => {
  it("allows responsive Agent Apps to reach a narrow window viewport", () => {
    const config = getDesktopWindowConfig();

    expect(config.minWidth).toBeLessThanOrEqual(390);
    expect(config.width).toBeGreaterThan(config.minWidth);
  });
});
