// @vitest-environment node

import { describe, expect, it } from "vitest";

import { subscriptionMessage } from "../src/renderer/components/SettingsBilling";
import type { BillingStatus } from "../src/shared/commerce";

describe("billing subscription messages", () => {
  it.each(["refunded", "disputed"])("renders %s as revoked even before the revoked flag refreshes", (status) => {
    const billing: BillingStatus = {
      mode: "commerce_provider",
      plan: null,
      subscription: {
        status,
        paidThrough: null,
        periodStart: null,
        periodEnd: null,
        revoked: false,
      },
      customerBound: true,
      availablePlans: [],
    };

    expect(subscriptionMessage(billing, (key) => key)).toBe("settings.billing.revoked");
  });
});
