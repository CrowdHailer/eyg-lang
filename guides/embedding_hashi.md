---
name: Playing Hashi through EYG
description: Give a puzzle shell and an agent only the original game's operations.
---

# Playing Hashi through EYG

[examples/hashi](../examples/hashi/) adapts the public game API of
[Giacomo Cavalieri's Hashi](https://github.com/giacomocavalieri/hashi), pinned
to commit 6ad02b9ad90490a9cf05ade95beb97814f19c511. The upstream project supplies
puzzle generation, the board view, move rules, history and completion checks.
The adapter builds a bridge by sending the same pair of island presses as a
person. Refused moves discard the intermediate selection.

The typed interface offers ListIslands, ListBridges, AddBridge, RemoveBridge,
Undo, Redo, IsSolved and Print. Moves take `{from: {x, y}, to: {x, y}}` and
return Ok({}) or Error with NoIsland, NotReachable, Full, NoBridge or
AlreadySolved. Coordinates start at zero in the top left. Upstream rules
reject crossing bridges and more than two bridges between a pair of islands.

From examples/hashi, run `gleam test` and `gleam test --runtime node`.
The board tests exercise actual upstream transitions, crossing and invalid
endpoints, double bridges, removal, undo/redo and solved-board refusal.

## Retained shell and solver

`hashi/play.start(library)` creates a shell with the game effects and the
[library](../examples/hashi/library.eyg) in scope as `hashi`. Keep the returned
shell and board after each `play.run`; variables persist between runs.
The library has no package references, so these programs make no hub requests.
Keeping the shell retains its checked functions and values; recreating it
rechecks them. The host owns this lifetime.

```eyg
let islands = hashi.unfinished({})
hashi.map(islands, (island) -> { {x: island.x, y: island.y, missing: hashi.missing(island)} })
```

The helpers query islands and neighbours, count existing bridges and connect
or disconnect pairs. Game refusals are ordinary tagged results. Type errors,
including unavailable effects, stop the whole program before any move.

Run [solver.eyg](../examples/hashi/solver.eyg) in the shell to retain `solve`,
then run `solve({})`. It repeatedly adds bridges forced by the numbers and
stops when no more are forced, returning IsSolved. It does not guess or search:
the tests solve seed 1 and verify a partial, unsolved result on seed 2.

## Browser shell and agent

From examples/hashi:

```sh
eyg script bin/fetch_style.eyg
gleam test
gleam run -m dev
```

Open http://127.0.0.1:7822/?seed=1. The fetch script gets the upstream CSS
from the same pinned commit into ignored vendor/. The Gleam tools build and
serve the page, library and syntax guide. The seed query selects a reproducible
board; it defaults to 1. New puzzle generates a random seed.

Run `hashi.with_target(6)`. An island with target six and three neighbours
needs two bridges to each. This program adds them:

```eyg
let big = hashi.with_target(6)
hashi.each(big, (island) -> {
  hashi.each(hashi.neighbours(island), (other) -> {
    let _ = hashi.connect(island, other)
    hashi.connect(island, other)
  })
})
```

Paste solver.eyg, run it, then run `solve({})`. The board shows Solved!
Control/Command+Enter submits the editor. The Agent tab gives a model one run
tool against the same shell and board. Pointer messages from the board view
are ignored, so its changes come only through the game interface.
OLLAMA_ORIGIN configures the model proxy, default http://127.0.0.1:11434;
the page also offers Mistral. Rebuild and restart after changing source.

The browser integration check solves seed 1
from the shell and seed 3 through an explicitly scripted model fixture. It
checks type rejection, correction of a misspelled field, retained solver
bindings and the original game's completion state. It makes no live model call.
Recreate it from packages/tracing with
`EYG_BIN=/path/to/eyg CHROME_BIN=/path/to/chromium gleam run -m tracing/hashi_demo`.
The driver fetches the pinned style, builds the app and stops its local services.
