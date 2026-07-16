import { describe, expect, it } from "vitest";

import {
  draftFromDevSkillSource,
  emptyDevSkillDraft,
  prepareDevSkillSource,
  suggestedDirectory,
  suggestedPackageId,
  validateDevSkillDraft,
} from "../src/renderer/devSkillEditorModel";

describe("Dev Skill editor model", () => {
  it("builds an instruction-only package from simple form fields", () => {
    const draft = {
      ...emptyDevSkillDraft("com.example.secretary"),
      description: "Prepare a concise briefing.",
      directory: "daily-briefing",
      displayName: "Daily Briefing",
      instructions: "# Daily briefing\n\nUse verified sources.",
      packageId: "com.example.secretary.daily-briefing",
      skillName: "daily-briefing",
    };

    expect(validateDevSkillDraft(draft)).toEqual([]);
    const prepared = prepareDevSkillSource(draft);
    expect(prepared.manifest).toMatchObject({
      id: "com.example.secretary.daily-briefing",
      kind: "instruction_only",
      package: { includeInstructions: true, includeRuntime: false },
      requires: { connectors: [], runtimeTools: [] },
    });
    expect(prepared.skillMd).toContain('description: "Prepare a concise briefing."');
    expect(prepared.skillMd).toContain("Use verified sources.");
  });

  it("preserves unedited manifest requirements and front-matter aliases", () => {
    const source = {
      directory: "calendar-helper",
      sourceRevision: "a".repeat(64),
      manifest: {
        schemaVersion: 1,
        id: "com.example.calendar.helper",
        version: "0.2.0",
        displayName: "Calendar Helper",
        kind: "host_tools_only",
        package: { includeInstructions: true, includeRuntime: false },
        compatibility: { platforms: ["desktop"] },
        requires: {
          packages: ["agentweave.foundation.calendar"],
          capabilities: ["calendar"],
          runtimeTools: ["calendar_events_list"],
          connectors: ["agentweave-calendar"],
        },
      },
      skillMd: "---\nname: calendar-helper\ndescription: 'Help with calendars.'\naliases:\n  - agenda\n---\n\n# Calendar helper\n",
    };
    const draft = draftFromDevSkillSource(source);
    const prepared = prepareDevSkillSource({ ...draft, description: "Plan calendars safely." }, source);

    expect(prepared.manifest).toMatchObject({
      version: "0.2.0",
      requires: {
        packages: ["agentweave.foundation.calendar"],
        capabilities: ["calendar"],
        runtimeTools: ["calendar_events_list"],
        connectors: ["agentweave-calendar"],
      },
    });
    expect(prepared.skillMd).toContain("aliases:\n  - agenda");
    expect(prepared.skillMd).toContain('description: "Plan calendars safely."');
  });

  it("requires a Host Tool or Connector for host-tools-only packages", () => {
    const draft = {
      ...emptyDevSkillDraft(),
      description: "Use a host capability.",
      directory: "host-helper",
      displayName: "Host Helper",
      instructions: "Use the host safely.",
      kind: "host_tools_only" as const,
      packageId: "app.local.host-helper",
      skillName: "host-helper",
    };
    expect(validateDevSkillDraft(draft)).toContain("hostRequirements");
  });

  it("derives safe project identifiers from display input", () => {
    expect(suggestedDirectory(" Daily Briefing! ")).toBe("daily-briefing");
    expect(suggestedPackageId("Com.Example.Secretary", "daily-briefing"))
      .toBe("com.example.secretary.daily-briefing");
  });
});
