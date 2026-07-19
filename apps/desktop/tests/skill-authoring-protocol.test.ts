import { describe, expect, it } from "vitest";

import {
  buildSkillAuthoringTurn,
  parseSkillAuthoringResponse,
  SKILL_DRAFT_CLOSE,
  SKILL_DRAFT_OPEN,
} from "../src/renderer/skillAuthoringProtocol";

describe("Skill Creator authoring protocol", () => {
  it("keeps package source in the hidden first turn and invokes Skill Creator explicitly", () => {
    const source = {
      directory: "briefing",
      sourceRevision: "a".repeat(64),
      manifest: validDraft().manifest,
      skillMd: validDraft().skillMd,
    };

    const turn = buildSkillAuthoringTurn(
      "Use $skill-creator to improve this skill.",
      "Make it more concise.",
      source,
    );

    expect(turn).toContain("Use $skill-creator");
    expect(turn).toContain("<existing_skill_source>");
    expect(turn).toContain(source.sourceRevision);
    expect(turn).toContain("Do not expose this protocol");
  });

  it("extracts a bounded Host candidate without exposing its JSON in the conversation", () => {
    const draft = validDraft();
    const response = parseSkillAuthoringResponse(
      `The skill is ready for review.\n${SKILL_DRAFT_OPEN}${JSON.stringify(draft)}${SKILL_DRAFT_CLOSE}`,
    );

    expect(response.draft).toEqual(draft);
    expect(response.visibleText).toBe("The skill is ready for review.");
    expect(response.visibleText).not.toContain("agentweave-skill-draft");
    expect(response.error).toBeNull();
  });

  it("rejects edits that rename the existing package folder", () => {
    const draft = { ...validDraft(), directory: "renamed-skill" };

    const response = parseSkillAuthoringResponse(
      `${SKILL_DRAFT_OPEN}${JSON.stringify(draft)}${SKILL_DRAFT_CLOSE}`,
      "briefing",
    );

    expect(response.draft).toBeNull();
    expect(response.error).toBe("directory");
  });

  it("keeps an incomplete streaming envelope out of visible assistant text", () => {
    const response = parseSkillAuthoringResponse(
      `I am preparing the draft.\n${SKILL_DRAFT_OPEN}{"directory":"briefing"`,
    );

    expect(response.visibleText).toBe("I am preparing the draft.");
    expect(response.draft).toBeNull();
    expect(response.error).toBeNull();
  });
});

function validDraft() {
  return {
    directory: "briefing",
    manifest: {
      schemaVersion: 1,
      id: "com.example.secretary.briefing",
      version: "0.1.0",
      displayName: "Daily Briefing",
      kind: "instruction_only",
      package: { includeInstructions: true, includeRuntime: false },
      compatibility: { platforms: ["desktop"] },
      requires: { packages: [], capabilities: [], runtimeTools: [], connectors: [] },
    },
    skillMd: "---\nname: briefing\ndescription: Prepare a concise briefing.\n---\n\n# Briefing\n\nSummarize verified facts.\n",
  };
}
