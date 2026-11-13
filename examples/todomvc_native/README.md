# TodoMVC through the standalone API

This Gleam host consumes the actual `packages/embed_js/dist/eyg.mjs` bundle
through native methods and plain objects. It ports the TypeScript example's
task callbacks, retained shell and one-tool agent to Gleam. The view uses Lustre.

Build the SDK first from packages/embed_js with `bun install` and
`gleam run -m build`. Install the shared CSS from examples/todomvc_lustre with
`bun install`. Then, from this directory:

```sh
gleam test
gleam run -m dev
```

Open http://127.0.0.1:7821. EYG_HUB, OLLAMA_ORIGIN and PORT configure the Gleam
development server. Rebuild and restart after editing source.
The [guide](../../guides/embedding_native_todomvc.md) explains the API boundary,
cache ownership and reproducible browser recording.
