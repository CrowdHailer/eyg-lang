# EYG in Pi

An extension for Pi 1.2.0, implemented in Gleam with five library bindings and
native re-export entries. Native Pi tools become EYG effects, checked by the
shared policy runtime. --eyg-only hides their declarations while keeping them
callable through EYG. Task subagents retain their restricted policy and report usage.

```sh
bun install
gleam run -m build
gleam test
gleam test --runtime node
```

Run Pi with `pi -e /absolute/path/to/dist/index.mjs --eyg-only`.
Configuration is PI_EYG_CONFIG, .pi/eyg.eyg in the project, or eyg.eyg in Pi's
agent directory, in that order. The default allows computer file operations
within the project. These are the computer ReadFile/WriteFile effects;
Pi's native Read/Write tools require their own gates.

The [guide](../../guides/pi_extension.md) covers setup, the optional bash-only
adapter, policy inheritance and the checked SDK recording. SDK dependencies are
pinned official packages; no Pi source tree is vendored.
The optional bash adapter's integration test invokes the EYG CLI on PATH.
