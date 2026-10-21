# website


## Development

```sh
gleam dev
gleam test  # Run the tests
```

## Guide syntax highlighting

Guide code fences are highlighted at build time with Shiki's bundled languages,
including Gleam and Erlang, and the shared EYG grammar from `../vscode-eyg`.
Add a language name to a fence (for example, `gleam`, `erlang`, or `sh`) to enable
highlighting. Unknown languages and unlabelled fences render as plain code.
The generated pages need no browser-side highlighting JavaScript.
