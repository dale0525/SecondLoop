import { afterEach, describe, expect, it, vi } from "vitest";

import {
  deleteMailAccountConfiguration,
  getMailAccountConfiguration,
  listMailAccountConfigurations,
  putMailAccountConfiguration,
  type FoundationMailConfigurationInput,
} from "../src/renderer/mailConfigurationApi";

afterEach(() => {
  delete window.agentWeave;
  vi.restoreAllMocks();
});

describe("Mail configuration Renderer API", () => {
  it("uses only the typed trusted bridge operations", async () => {
    const request = vi.fn(async () => ({}));
    window.agentWeave = {
      server: { request },
      owner: {} as NonNullable<Window["agentWeave"]>["owner"],
      approval: { open: vi.fn() },
    };
    const input: FoundationMailConfigurationInput = {
      id: "primary",
      displayName: "Primary Mail",
      primaryName: "Local User",
      primaryAddress: "user@example.test",
      username: "user@example.test",
      password: "transient-app-password",
      imapHost: "imap.example.test",
      imapPort: 993,
      imapTls: "implicit",
      smtpHost: "smtp.example.test",
      smtpPort: 587,
      smtpTls: "start_tls",
    };

    await listMailAccountConfigurations();
    await getMailAccountConfiguration("primary");
    await putMailAccountConfiguration(input);
    await deleteMailAccountConfiguration("primary");

    expect(request.mock.calls).toEqual([
      ["mail.configuration.list", undefined],
      ["mail.configuration.get", { id: "primary" }],
      ["mail.configuration.put", input],
      ["mail.configuration.delete", { id: "primary" }],
    ]);
  });
});
