// @vitest-environment node

import { describe, expect, it } from "vitest";

import { sanitizedPackagingEnvironment } from "../src/main/developerPackager";

describe("developer packager", () => {
  it("starts packaging without developer control-plane or ambient credentials", () => {
    const env = sanitizedPackagingEnvironment({
      PATH: "/usr/bin",
      HOME: "/home/developer",
      AGENTWEAVE_DEV_API: "1",
      AGENTWEAVE_CLOUDFLARE_OAUTH_CLIENT_ID: "public-client",
      AGENTWEAVE_CLOUDFLARE_GATEWAY_ARTIFACT: "/private/gateway.mjs",
      OPENAI_API_KEY: "model-secret",
      ENTITLEMENT_SERVICE_TOKEN: "entitlement-secret",
      SSH_AUTH_SOCK: "/private/ssh-agent.sock",
    }, "/project/app");

    expect(env).toEqual({
      PATH: "/usr/bin",
      HOME: "/home/developer",
      AGENTWEAVE_APP_ROOT: "/project/app",
    });
  });
});
