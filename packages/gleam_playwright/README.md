# Gleam Playwright

Thin bindings to the Playwright JavaScript library. Browser workflows, assertions,
mock services and video scripts are written in Gleam. Platform APIs belong in
`plinthx`; this package only adapts Playwright calls and promise failures.

Declare `eyg-gleam-playwright` as a local npm dependency in each consumer and
run `bun install` there, so the emitted FFI resolves the pinned Playwright.
Run `bunx playwright install chromium` in that consumer before browser checks. Pass an empty executable path to `launch` for Playwright's browser,
or supply a custom Chromium path. Create a recording context, retain the page's
`video`, and close the context before `save_video` so the video finishes writing.
