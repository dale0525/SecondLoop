export type Locale = "en" | "zh";

export const siteOrigin = "https://agentweave.secondloop.app";
export const repositoryUrl = "https://github.com/dale0525/agentweave";
export const contactEmail = "a@secondloop.app";

export function localizedPath(locale: Locale, path: string): string {
  const clean = path.startsWith("/") ? path : `/${path}`;
  if (locale === "en") return clean;
  if (clean === "/") return "/zh/";
  return `/zh${clean}`;
}

export function alternatePath(locale: Locale, path: string): string {
  if (locale === "en") return localizedPath("zh", path);
  const withoutLocale = path.replace(/^\/zh(?=\/|$)/, "");
  return withoutLocale || "/";
}
