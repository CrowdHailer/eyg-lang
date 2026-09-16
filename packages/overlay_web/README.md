# overlay_web

The state, view model, and tool implementation for the overlay agent.
`overlay_public` runs this state machine in the browser.

## Context

Every overlay session runs with a context module. A record can provide a string
`readme` field explaining its typed API. The readme is given to the agent as part
of the system prompt and the module is in scope, as `context`, for every program
the run tool executes.

Modules without a string `readme` are also accepted. Their instructions use the
default context text with the module's inferred type appended. An orange dot
beside the context name indicates that no readme was provided; green means a
readme is available, and red means the context could not be loaded.

The browser deployment reads the requested module from the page query:

| query | selected module |
| --- | --- |
| `?reference=<cid>` | module with that content ID |
| `?package=<name>` | latest release of the package |
| `?package=<name>&version=<n>` | positive release `n` |

A session that asks for none, or for one that cannot be loaded, runs against the
built-in default module, whose readme describes the overlay agent itself. A
request that could not be met is
shown on the page with its reason, rather than the session starting as though
nothing had been asked for.

The page refuses prompts while a requested module is still being looked up.

## Development

```sh
gleam test
```

To use a context in the browser, run the public page against a hub:

```sh
cd ../overlay_public
EYG_HUB=http://localhost:8001 bun run dev
```

Open [localhost:5173/overlay/](http://localhost:5173/overlay/).
`EYG_HUB` selects the hub proxied by the development server for module and package lookups.
It defaults to `https://eyg.run`.
