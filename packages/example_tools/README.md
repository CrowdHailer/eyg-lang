# Browser example tools

Gleam tooling shared by the embedding examples. Requires Bun and Gleam.

- `build(entry, output)` bundles a compiled Gleam module for browsers.
  HTML calls the exported entry; startup glue can stay two lines.
- `file(route, path, content_type)` reads one explicit static asset.
- `serve(options, assets)` binds localhost and serves only registered routes.
  Hub paths `/packages/` and `/modules/` proxy to the configured hub; `/api/`
  proxies to the configured model origin, preserving method, headers and body.
- `environment(default_port)` reads PORT, EYG_HUB and OLLAMA_ORIGIN. Defaults
  are eyg.run and local Ollama; a walkthrough can supply local fixture origins.

Run `gleam test` here to check actual static bytes and proxy HTTP behavior.
Consumers retain the returned server and stop it when their walkthrough ends.
Rebuild and restart after editing assets; no separate Vite configuration or
JavaScript build script is needed.
