import { fileURLToPath } from "node:url";
import { join, relative } from "node:path";

import { packageMacDesktop } from "../apps/desktop/scripts/package-macos.mjs";
import { resolveAppProject } from "./app-project.mjs";

export function createAppPackagePlan(options = {}) {
  const app = resolveAppProject(options);
  return Object.freeze({
    app,
    input: app.appRoot,
    output: join(app.projectRoot, "dist", "macos", app.outputName),
    overwrite: true,
  });
}

async function runAppPackage() {
  const plan = createAppPackagePlan();
  const result = await packageMacDesktop(plan);
  console.log(`Packaged ${plan.app.displayName} at ${relative(plan.app.projectRoot, result.appPath)}`);
}

if (process.argv.includes("--print-plan")) {
  console.log(JSON.stringify(createAppPackagePlan(), null, 2));
} else if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runAppPackage().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
