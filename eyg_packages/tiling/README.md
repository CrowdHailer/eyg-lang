# Tiling functions

These modules describe layout; Overlay implements placement via `Show`.
Both modules expose a `readme` string so an agent can discover their API by
content reference. No package registration or global latest-version lookup is
needed.

```eyg
let dwindle = import "./dwindle.eyg"
let main_stack = import "./main_stack.eyg"
let bounds = {origin: {x: 0, y: 0}, size: {x: 1000, y: 1000}}
let items = [Artifact("map"), Artifact("buses"), History("map")]
main_stack.show(main_stack.layout(items, bounds, 600))
```

- `dwindle.layout(items, bounds)` alternates left/right and top/bottom splits.
- `dwindle.tree(items, bounds)` exposes the binary tree as preorder nodes
  indexed by `root`, `root/0`, `root/1`, etc. This preserves explicit tree
  structure without requiring recursive EYG data types.
- `main_stack.layout(items, bounds, main_size)` assigns `main_size / 1000`
  of the width to the first item, and tiles the rest in a vertical stack.
- Both export `show(placements)`, which calls `Show` in list order and aborts
  on the first failure. Layout itself is pure for valid inputs; invalid or
  exhausted integer dimensions raise `Abort`.

Integer rounding leaves no gaps. Empty layouts have no tiles; singleton layouts
fill all available space. Dimensions and every resulting tile must be positive.
The functions accept any item type, so they also work with diffs and history.

Test: `eyg script eyg_packages/tiling/entry.eyg` from the repository root.
Share: `EYG_ORIGIN=http://localhost:8001 eyg share eyg_packages/tiling/dwindle.eyg`
(and likewise for `main_stack.eyg`). Use the returned `#<cid>` in agent programs.
