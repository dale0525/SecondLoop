import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const qualityWorkflow = readFileSync(
  new URL("../.github/workflows/secondloop-quality.yml", import.meta.url),
  "utf8",
);
const packageWorkflow = readFileSync(
  new URL("../.github/workflows/macos-desktop-package.yml", import.meta.url),
  "utf8",
);

test("SecondLoop quality gate covers product and shared runtime changes", () => {
  for (const requiredPath of [
    "products/secondloop/**",
    "apps/desktop/**",
    "crates/**",
    "scripts/**",
  ]) {
    assert.match(qualityWorkflow, new RegExp(escapeRegex(requiredPath)));
  }
  for (const requiredCheck of [
    "validate-secondloop",
    "cargo fmt --all -- --check",
    "cargo clippy --workspace --all-targets -- -D warnings",
    "cargo test --workspace",
    "npm --prefix apps/desktop test",
    "tsconfig.vitest.json",
    "source-lines",
  ]) {
    assert.match(qualityWorkflow, new RegExp(escapeRegex(requiredCheck)));
  }
});

test("macOS package matrix includes the SecondLoop product root", () => {
  assert.match(packageWorkflow, /app: secondloop/);
  assert.match(packageWorkflow, /input: products\/secondloop/);
  assert.match(packageWorkflow, /--input \$\{\{ matrix\.input \}\}/);
  assert.match(packageWorkflow, /"products\/\*\*"/);
});

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
