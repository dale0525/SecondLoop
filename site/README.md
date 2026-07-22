# AgentWeave website

Static Astro website for `https://agentweave.secondloop.app`.

## Local development

Use the repository Pixi environment so the Node version remains reproducible:

```bash
pixi run npm --prefix site ci
pixi run npm --prefix site run check
pixi run npm --prefix site run dev
```

## Cloudflare Pages

- Project: `agentweave`
- Production branch: `main`
- Build output: `site/dist`
- Custom domain: `agentweave.secondloop.app`

An authenticated maintainer can deploy the current checkout with:

```bash
pixi run npm --prefix site run deploy
```

The site does not use analytics, cookies, remote fonts, or a server-side data store.
