# EYG for JavaScript hosts

The standalone `dist/eyg.mjs` exports `createShell(options)`. Its wrapper,
retained state, host callback routing, build tooling and tests are Gleam.
The native entry only re-exports the API; consumers need no Gleam runtime.

```sh
bun install
gleam run -m build
gleam test --runtime bun
gleam test --runtime node
```

Copy the bundle and its TypeScript declarations into the host application.
See the [guide](../../guides/embedding_javascript.md) for methods, effect types,
cache ownership and async ordering. The Gleam browser client consumes the actual
bundle; `gleam run -m browser_check` checks it in Chromium. Set CHROME_BIN to
use an existing executable.
