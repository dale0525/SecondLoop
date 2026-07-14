export const OWNER_REQUEST_CHANNEL = "agentweave:owner:request";

export type OwnerOperation =
  | "createDraft"
  | "disable"
  | "listSkills"
  | "principal"
  | "requestActivation"
  | "requestRemoval"
  | "rollback"
  | "skillDetail"
  | "updateDraft"
  | "validateDraft";

export type OwnerIpcRequest = Readonly<{
  input?: unknown;
  operation: OwnerOperation;
}>;

type OwnerMethod = "DELETE" | "GET" | "POST" | "PUT";

const OWNER_ROUTES: Array<{ method: OwnerMethod; path: RegExp }> = [
  { method: "GET", path: /^\/owner\/principal$/ },
  { method: "GET", path: /^\/owner\/skills$/ },
  { method: "GET", path: /^\/owner\/skills\/[A-Za-z0-9._-]+\/detail$/ },
  { method: "POST", path: /^\/owner\/skills\/drafts$/ },
  { method: "PUT", path: /^\/owner\/skills\/drafts\/[0-9a-f-]+$/ },
  { method: "POST", path: /^\/owner\/skills\/drafts\/[0-9a-f-]+\/(validate|activation)$/ },
  { method: "POST", path: /^\/owner\/skills\/[A-Za-z0-9._-]+\/(rollback|disable)$/ },
  { method: "DELETE", path: /^\/owner\/skills\/[A-Za-z0-9._-]+$/ },
];

export function normalizeOwnerRequest(path: string, method: string): string {
  if (!path.startsWith("/") || path.startsWith("//") || path.includes("\\")) {
    throw new Error("Owner request path is not allowed");
  }
  const url = new URL(path, "http://127.0.0.1");
  if (url.origin !== "http://127.0.0.1" || url.username || url.password || url.hash) {
    throw new Error("Owner request path is not allowed");
  }
  const normalizedMethod = method.toUpperCase() as OwnerMethod;
  const matchingPath = OWNER_ROUTES.filter((route) => route.path.test(url.pathname));
  if (matchingPath.length === 0) throw new Error("Owner request path is not allowed");
  if (!matchingPath.some((route) => route.method === normalizedMethod)) {
    throw new Error("Owner request method is not allowed");
  }
  return `${url.pathname}${url.search}`;
}
