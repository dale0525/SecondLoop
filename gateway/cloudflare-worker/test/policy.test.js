import assert from "node:assert/strict";
import test from "node:test";

import { parseGatewayConfig, validateRuntimeBindings } from "../src/config.js";
import { GatewayError } from "../src/errors.js";
import { prepareModelRequest } from "../src/policy.js";
import { gatewayConfig, runtimeEnv } from "./fixtures.js";

function request(body, {
  path = "/v1/responses",
  method = "POST",
  headers = {},
} = {}) {
  return new Request(`https://gateway.example.test${path}`, {
    method,
    headers: {
      accept: "text/event-stream",
      authorization: "Bearer end-user-token",
      "content-type": "application/json",
      cookie: "private=session",
      "openai-beta": "attacker-controlled-beta",
      ...headers,
    },
    body: method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function rejected(body, code, options) {
  const config = parseGatewayConfig(gatewayConfig());
  await assert.rejects(
    prepareModelRequest(config, request(body, options), "upstream-secret"),
    (error) => error instanceof GatewayError && error.code === code,
  );
}

test("request policy fixes route, upstream, model, token field, and forwarded headers", async () => {
  const config = parseGatewayConfig(gatewayConfig());
  const prepared = await prepareModelRequest(config, request({
    model: "model-small",
    input: [{ role: "user", content: "private prompt" }],
    stream: true,
    tools: [{
      type: "function",
      name: "lookup",
      description: "Look up a value.",
      parameters: {
        type: "object",
        properties: {
          zeta: { type: "string" },
          alpha: { type: "string" },
        },
      },
    }],
  }), "upstream-secret");

  assert.equal(prepared.route.id, "responses");
  assert.equal(prepared.model, "model-small");
  assert.equal(prepared.outputTokenLimit, 1024, "the configured ceiling is injected when absent");
  assert.ok(prepared.reservedUnits > 1024, "request bytes and base units are reserved too");
  assert.equal(prepared.toolCount, 1);
  assert.equal(prepared.upstreamUrl, "https://models.example.test/v1/responses");
  assert.equal(prepared.headers.get("authorization"), "Bearer upstream-secret");
  assert.equal(prepared.headers.get("cookie"), null);
  assert.equal(prepared.headers.get("openai-beta"), "responses=v1", "developer-fixed headers win");
  const forwardedBody = JSON.parse(new TextDecoder().decode(prepared.body));
  assert.equal(forwardedBody.max_output_tokens, 1024);
  assert.deepEqual(forwardedBody.input, [{ role: "user", content: "private prompt" }]);
  assert.deepEqual(
    Object.keys(forwardedBody.tools[0].parameters.properties),
    ["zeta", "alpha"],
    "canonical hashing must not reorder the upstream schema",
  );
});

test("request policy enforces exact path, method, and no query parameters", async () => {
  await rejected({ model: "model-small" }, "route_not_allowed", { path: "/v1/chat/completions" });
  await rejected(null, "method_not_allowed", { method: "GET" });
  await rejected({ model: "model-small" }, "query_not_allowed", { path: "/v1/responses?base_url=https://evil.test" });
});

test("request policy enforces model and explicit upstream override denylist", async () => {
  await rejected({ model: "unpriced-model" }, "model_not_allowed");
  await rejected({ model: "model-small", base_url: "https://evil.test" }, "upstream_override_forbidden");
  await rejected({ model: "model-small", endpoint: "https://evil.test" }, "upstream_override_forbidden");
});

test("Responses wire protocol rejects account-global resources and unknown nested fields", async () => {
  const base = {
    model: "model-small",
    input: [{ role: "user", content: "hello" }],
    tools: [],
    stream: true,
  };
  for (const override of [
    { previous_response_id: "resp_from_another_user" },
    { conversation: "conversation_from_another_user" },
    { prompt: { id: "developer-account-prompt" } },
    { store: true },
    { modalities: ["text", "audio"] },
    { audio: { voice: "alloy" } },
  ]) {
    await rejected({ ...base, ...override }, "wire_shape_not_allowed");
  }
  await rejected({
    ...base,
    input: [{ role: "user", content: "hello", file_id: "file_from_another_user" }],
  }, "wire_shape_not_allowed");
  await rejected({
    ...base,
    input: [{ role: "user", content: [{ type: "input_file", file_id: "file-1" }] }],
  }, "wire_shape_not_allowed");
  await rejected({
    ...base,
    tools: [{
      type: "function",
      name: "lookup",
      description: "Look up a value.",
      parameters: { type: "object" },
      server_url: "https://attacker.test",
    }],
  }, "wire_shape_not_allowed");
});

test("Chat Completions and Completion protocols accept only AgentWeave runtime shapes", async () => {
  const chatRoute = {
    ...gatewayConfig().routes[0],
    id: "chat",
    path: "/v1/chat/completions",
    upstreamPath: "/v1/chat/completions",
    tokenField: "max_completion_tokens",
    wireProtocol: "agentweave_chat_completions_v1",
  };
  const chatConfig = parseGatewayConfig(gatewayConfig({ routes: [chatRoute] }));
  const chat = await prepareModelRequest(chatConfig, request({
    model: "model-small",
    messages: [
      { role: "system", content: "Policy" },
      { role: "user", content: "Look it up" },
      {
        role: "assistant",
        content: "",
        tool_calls: [{
          id: "call.provider:1/segment",
          type: "function",
          function: { name: "lookup", arguments: "{}" },
        }],
      },
      { role: "tool", content: "result", tool_call_id: "call.provider:1/segment" },
    ],
    tools: [{
      type: "function",
      function: {
        name: "lookup",
        description: "Look up a value.",
        parameters: { type: "object" },
      },
    }],
    stream: true,
  }, { path: "/v1/chat/completions" }), "upstream-secret");
  assert.equal(JSON.parse(new TextDecoder().decode(chat.body)).max_completion_tokens, 1024);

  const completionRoute = {
    ...gatewayConfig().routes[0],
    id: "completion",
    path: "/v1/completions",
    upstreamPath: "/v1/completions",
    tokenField: "max_tokens",
    allowedToolTypes: [],
    wireProtocol: "agentweave_completion_v1",
  };
  const completionConfig = parseGatewayConfig(gatewayConfig({ routes: [completionRoute] }));
  const completion = await prepareModelRequest(completionConfig, request({
    model: "model-small",
    prompt: "hello",
    stream: false,
  }, { path: "/v1/completions" }), "upstream-secret");
  assert.equal(JSON.parse(new TextDecoder().decode(completion.body)).max_tokens, 1024);
});

test("request policy enforces body, output token, and tool ceilings", async () => {
  await rejected({ model: "model-small" }, "body_too_large", {
    headers: { "content-length": "4097" },
  });
  await rejected({ model: "model-small", max_output_tokens: 1025 }, "token_limit_exceeded");
  await rejected({ model: "model-small", max_tokens: 12 }, "ambiguous_token_limit");
  await rejected({
    model: "model-small",
    tools: [
      { type: "function" },
      { type: "function" },
      { type: "function" },
      { type: "function" },
    ],
    functions: [{}],
  }, "tool_limit_exceeded");
  await rejected({ model: "model-small", tools: {} }, "invalid_tools");
  await rejected({ model: "model-small", n: 2 }, "generation_multiplier_not_allowed");
  await rejected({ model: "model-small", best_of: 3 }, "generation_multiplier_not_allowed");
  await rejected({
    model: "model-small",
    tools: [{ type: "web_search" }],
  }, "tool_type_not_allowed");
  await rejected({
    model: "model-small",
    tools: [{ type: "mcp", server_url: "https://attacker.test" }],
  }, "tool_type_not_allowed");
  await rejected({ model: "model-small", web_search_options: {} }, "unmetered_feature_not_allowed");
});

test("streamed request bodies are stopped when their actual bytes exceed the limit", async () => {
  const config = parseGatewayConfig(gatewayConfig({ limits: { maxBodyBytes: 32 } }));
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(new TextEncoder().encode('{"model":"model-small","input":"'));
      controller.enqueue(new TextEncoder().encode("x".repeat(64)));
      controller.close();
    },
  });
  const streamed = new Request("https://gateway.test/v1/responses", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: stream,
    duplex: "half",
  });
  await assert.rejects(
    prepareModelRequest(config, streamed, "upstream-secret"),
    (error) => error.code === "body_too_large" && error.status === 413,
  );
});

test("configuration fails closed for unapproved base URLs and forwarding headers", () => {
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      upstream: { allowedBaseUrls: ["https://different.example.test"] },
    })),
    (error) => error.code === "gateway_misconfigured",
  );
  for (const header of [
    "authorization",
    "x-api-key",
    "api-key",
    "idempotency-key",
    "x-agentweave-request-id",
  ]) {
    assert.throws(
      () => parseGatewayConfig(gatewayConfig({
        upstream: { requestHeaders: [header] },
      })),
      (error) => error.code === "gateway_misconfigured",
    );
  }
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      upstream: { staticHeaders: { authorization: "embedded-secret" } },
    })),
    (error) => error.code === "gateway_misconfigured",
  );
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      upstream: {
        requestHeaders: ["openai-beta"],
        staticHeaders: { "openai-beta": "fixed" },
      },
    })),
    (error) => error.code === "gateway_misconfigured",
  );
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      upstream: {
        baseUrl: "http://models.example.test",
        allowedBaseUrls: ["http://models.example.test"],
      },
    })),
    (error) => error.code === "gateway_misconfigured",
  );
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      routes: [{
        ...gatewayConfig().routes[0],
        allowedToolTypes: ["function", "web_search"],
      }],
    })),
    (error) => error.code === "gateway_misconfigured",
  );
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      routes: [{
        ...gatewayConfig().routes[0],
        tokenField: "max_tokens",
      }],
    })),
    (error) => error.code === "gateway_misconfigured",
  );
});

test("configuration uses strict booleans, collection types, and local-only HTTP", () => {
  for (const override of [
    { rateLimit: { required: false } },
    { rateLimit: { required: "true" } },
    { auth: { providers: [{ ...gatewayConfig().auth.providers[0], requireNbf: "true" }] } },
    { upstream: { secretPrefix: 42 } },
    { auth: { providers: {} } },
    { routes: {} },
    { controls: { modelRequestsEnabled: "false" } },
  ]) {
    assert.throws(
      () => parseGatewayConfig(gatewayConfig(override)),
      (error) => error.code === "gateway_misconfigured",
    );
  }

  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      environment: "staging",
      upstream: {
        baseUrl: "http://127.0.0.1:8788",
        allowedBaseUrls: ["http://127.0.0.1:8788"],
      },
    })),
    (error) => error.code === "gateway_misconfigured",
  );
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      environment: "development",
      upstream: {
        baseUrl: "http://models.example.test",
        allowedBaseUrls: ["http://models.example.test"],
      },
    })),
    (error) => error.code === "gateway_misconfigured",
  );

  const local = parseGatewayConfig(gatewayConfig({
    environment: "development",
    upstream: {
      baseUrl: "http://127.0.0.1:8788",
      allowedBaseUrls: ["http://127.0.0.1:8788"],
    },
  }));
  assert.equal(local.upstream.baseUrl, "http://127.0.0.1:8788");
  assert.throws(
    () => validateRuntimeBindings(local, runtimeEnv(gatewayConfig()), { remoteRequest: true }),
    (error) => error.code === "gateway_misconfigured",
  );
});
