# loam

The abstraction layer for an application running on a personal computer or server (not browser or embedded).
This package includes a `system.Effect` abstraction that models all side effects as data and allows for safe testing.

## Execution

`loam/execute` evaluates EYG and resolves imports using `system.Effect`.
Run the resulting effect with `system.run` or `sandbox.run`.
`pure_loop` resolves imports but rejects unhandled program effects.
`loam/source.normalize_input` resolves file inputs against an explicit working directory.

## Interactive input

`system.prompt(text)` displays a prompt and reads terminal input using the `input`
driver. This is a separate effect from `system.stdin()`, which reads the whole
stream until EOF and therefore cannot support an interactive question-and-answer
loop. It can be used by REPLs and other terminal applications.

In the sandbox, queue results with `sandbox.with_prompt_response`. Prompts are
captured in stdout, and responses are independent of `sandbox.with_stdin`.
An empty response queue models EOF (`Ok("")`); `Error(Nil)` models a read failure.

## Development

```sh
gleam test
```
