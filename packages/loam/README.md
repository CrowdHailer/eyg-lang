# loam

The abstraction layer for an application running on a personal computer or server (not browser or embedded).
This package includes a `system.Effect` abstraction that models all side effects as data and allows for safe testing.

## Execution

`loam/execute` evaluates EYG and resolves imports using `system.Effect`.
Run the resulting effect with `system.run` or `sandbox.run`.
`pure_loop` resolves imports but rejects unhandled program effects.
`loam/source.normalize_input` resolves file inputs against an explicit working directory.

## Development

```sh
gleam test
```
