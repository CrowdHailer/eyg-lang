# Hashi through EYG

The original pinned Hashi game runs unchanged as a Gleam dependency. The page
shows its board beside an EYG shell and one-tool agent. Only EYG changes this
board; pointer messages from the view are ignored.

```sh
eyg script bin/fetch_style.eyg
gleam test
gleam run -m dev
```

Open http://127.0.0.1:7822/?seed=1. The EYG script fetches the original CSS
from the same pinned upstream commit into ignored vendor/. Gleam tools build
and serve the page; OLLAMA_ORIGIN configures the model proxy and PORT the port.
Rebuild and restart after editing source.

The [guide](../../guides/embedding_hashi.md) covers the game's effects,
retained solver, package lifetime and checked browser recording.
