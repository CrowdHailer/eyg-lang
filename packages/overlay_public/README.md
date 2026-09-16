# overlay_public

Public instance of overlay_web has development setup

Users choose an Ollama Cloud or Mistral model and provide their own API token.
The selection and token are kept in browser session storage and are cleared when
the tab is closed. Ollama calls use the deployment's fixed same-origin proxy
because Ollama Cloud does not allow browser CORS requests. Mistral calls are made
directly from the browser.

The [artifact proposal and effect contract](../../guides/overlay_artifacts.md)
describe local sandboxed previews, version history, diffs, and EYG tiling layouts.
See [the recorded demo](./demo/README.md) for the shared local-hub modules,
live data sources, and repeatable recording instructions.

## Development

```sh
bun run dev
```

Browser isolation and viewer interaction tests:

```sh
bun x playwright install chromium
bun run test:browser
```
