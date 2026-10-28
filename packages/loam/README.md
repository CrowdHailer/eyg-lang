# loam

The abstraction layer for an application running on a personal computer or server (not browser or embedded).
This package includes a `system.Effect` abstraction that models all side effects as data and allows for safe testing.

## Execution

`loam/execute` evaluates EYG and resolves imports using `system.Effect`.
Run the resulting effect with `system.run` or `sandbox.run`.
`pure_loop` resolves imports but rejects unhandled program effects.
`loam/source.normalize_input` resolves file inputs against an explicit working directory.

## Tracing

`system.span` wraps lazy host work with explicitly nested spans. Run with
`system.run`, or supply per-run settings with `system.run_with_environment`.
`OTEL_EXPORTER_OTLP_ENDPOINT` enables automatic evaluation/effect spans;
`EYG_PROFILE_FILE` writes Chrome trace JSON. `loam/profile.block` adds named
function spans and retains continuation segments. See the
[tracing guide](../../guides/tracing.md) for commands and timing definitions.

## Development

```sh
gleam test
```
