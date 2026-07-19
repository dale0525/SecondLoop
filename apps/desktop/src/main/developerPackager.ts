import { spawn } from "node:child_process";
import path from "node:path";

import type { DeveloperPackageReceipt } from "../shared/developerProject";

const MAX_LOG_BYTES = 1024 * 1024;

export async function packageDeveloperApp(options: {
  appRoot: string;
  projectRoot: string;
}): Promise<DeveloperPackageReceipt> {
  const result = await runPixiPackage(options);
  const packagedLine = result.stdout
    .split(/\r?\n/)
    .reverse()
    .find((line) => line.startsWith("Packaged ") && line.includes(" at "));
  const relativeOutput = packagedLine?.slice(packagedLine.lastIndexOf(" at ") + 4).trim();
  if (!packagedLine || !relativeOutput) throw new Error("Packager did not report an output path");
  return {
    outputPath: path.resolve(options.projectRoot, relativeOutput),
    summary: packagedLine,
  };
}

function runPixiPackage(options: { appRoot: string; projectRoot: string }): Promise<{
  stdout: string;
}> {
  return new Promise((resolve, reject) => {
    const child = spawn("pixi", ["run", "app-package"], {
      cwd: options.projectRoot,
      env: sanitizedPackagingEnvironment(process.env, options.appRoot),
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let outputBytes = 0;
    const append = (stream: "stdout" | "stderr", chunk: Buffer) => {
      outputBytes += chunk.byteLength;
      if (outputBytes > MAX_LOG_BYTES) {
        child.kill("SIGTERM");
        reject(new Error("Packager output exceeded the safety limit"));
        return;
      }
      if (stream === "stdout") stdout += chunk.toString("utf8");
      else stderr += chunk.toString("utf8");
    };
    child.stdout.on("data", (chunk: Buffer) => append("stdout", chunk));
    child.stderr.on("data", (chunk: Buffer) => append("stderr", chunk));
    child.once("error", () => reject(new Error("Packager could not be started")));
    child.once("exit", (code) => {
      if (code === 0) resolve({ stdout });
      else {
        const lastLine = stderr.trim().split(/\r?\n/).at(-1);
        reject(new Error(lastLine?.slice(0, 500) || `Packager exited with code ${code ?? "unknown"}`));
      }
    });
  });
}

export function sanitizedPackagingEnvironment(
  source: NodeJS.ProcessEnv,
  appRoot: string,
): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const [name, value] of Object.entries(source)) {
    if (
      name.startsWith("AGENTWEAVE_")
      || name === "SSH_AUTH_SOCK"
      || /(?:^|_)(?:API_?KEY|AUTH|CREDENTIAL|PASSWORD|SECRET|TOKEN)(?:_|$)/i.test(name)
    ) continue;
    env[name] = value;
  }
  env.AGENTWEAVE_APP_ROOT = appRoot;
  return env;
}
