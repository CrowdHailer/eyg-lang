# Integration and trace tools

This package contains reproducible local checks and the offline performance viewer. Browser drivers use the local Playwright binding: run `bun install --frozen-lockfile` here, then `bunx playwright install chromium`, or set `CHROME_BIN` to an existing Chromium binary.

Run `gleam test --runtime bun` for trace layout and codec checks. `gleam run -- render` builds the offline presentation from `presentation/captures.json` and `presentation/profiles.json`; `gleam run -m tracing/performance_demo` checks its controls in Chromium.

`gleam run -m tracing/artifact_check` owns a hub and Vite server, uses a caller-configured PostgreSQL instance, runs both real artifact workflows, and cleans up its process groups. See the [artifact guide](../../guides/overlay_artifacts.md) for setup. Other checks include `tracing/sandbox_demo`, `tracing/todo_demo`, `tracing/todo_native_demo`, `tracing/hashi_demo`, `tracing/openai_check` and `tracing/codex_config_check`.

Generated media, exports and diagnostics stay in ignored `recordings`, `.recordings` and presentation output files. The runnable checks are the source of fresh evidence.
