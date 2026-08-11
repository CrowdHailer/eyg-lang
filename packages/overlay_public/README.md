# overlay_public

Public instance of overlay_web has development setup

Users choose an Ollama Cloud or Mistral model and provide their own API token.
The selection and token are kept in browser session storage and are cleared when
the tab is closed. Ollama calls use the deployment's fixed same-origin proxy
because Ollama Cloud does not allow browser CORS requests. Mistral calls are made
directly from the browser.

## Development

```sh
bun run dev
```
