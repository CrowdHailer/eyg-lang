# TodoMVC with an EYG shell

The Lustre page and EYG programs share one task model. The typed interface
offers list, create, rename and completion operations; deletion stays in the UI.
The shell retains variables, and the agent uses that same shell through run.

```sh
bun install
gleam test
gleam run -m dev
```

Open http://127.0.0.1:7820. The Gleam server bundles the page and proxies hub
and Ollama requests. EYG_HUB and OLLAMA_ORIGIN override their origins; PORT
changes the listening port. Rebuild and restart after editing source.

See the [guide](../../guides/embedding_todomvc.md) for the pinned package,
capabilities, cache ownership and checked browser recording. The recording
uses local protocol fixtures and starts and stops its own services.
