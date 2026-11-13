# Gleam Vite

Thin bindings to Vite and vite-gleam. Configuration and plugin decisions live in
Gleam; JavaScript adapts Vite's native objects and callbacks. A config entry file
can import the compiled Gleam `config()` and export its native configuration.
Compile the Gleam package before Vite loads that entry.
