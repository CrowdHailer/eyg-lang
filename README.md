# Eat Your Greens (EYG)

EYG is an immutable functional language with structural typing and managed effects.
The programming language is for predictable, useful and confident development.

The intermediate representation (IR) of EYG is a minimal tree and is the stable interface for writing EYG programs. Type checking, syntax, evaluation or compilation are optional components built on this foundation.

This repository contains the language definition, implementation, website and package hub.

## Install

Follow the [install from source](./guides/install_from_source.md) guide with instructions to compile and install the EYG CLI.

For the full CLI reference see[`packages/gleam_cli/README.md`](./packages/gleam_cli/README.md).
The language syntax is described in [`guides/simple_syntax.md`](./guides/simple_syntax.md)
and every `!builtin` is catalogued in [`guides/builtins_reference.md`](./guides/builtins_reference.md).

## Run a script

To run scripts from your shell use the [CLI](./packages/gleam_cli/).
checkout the [examples](./packages/gleam_cli/examples/)

Run scripts with `eyg run`.
Use `eyg eval` for evaluating pure values and printing the result.
Both textual and JSON IR source files can be evaluated or run.

Code can be run directly from the shell with `-c <code>` flag.
Code can be read from stdin with `-` or `--stdin`.
The inline source and stdin flags are available for `eyg run`, `eyg eval` and `eyg compile`.

For example:
```sh
eyg run -c 'perform Print("hello")'
eyg eval --code '@standard.integer.add(1, 1)'
printf 'perform Print("hello")' | eyg run -
```

### Effects

The REPL and interpreter implement the following effects to access the host computer:

| Effect | Purpose |
|---|---|
| `Print` | Write a string to stdout |
| `Now` | The current wall-clock time as Unix epoch milliseconds |
| `ReadFile` | Read a byte range of a file |
| `WriteFile` | Overwrite a file with new contents |
| `AppendFile` | Append contents to a file |
| `DeleteFile` | Delete a file |
| `ReadDirectory` | List the entries in a directory |
| `Fetch` | Make an HTTP request |
| `DecodeJSON` | Parse a JSON binary into EYG values |
| `Sleep` | Suspends the script for the given number of milliseconds. |
| `Random` | Returns a uniformly random integer |
| `Env` | Read a process environment variable |

Plus several authenticated service integrations powered by
[spotless](https://hex.pm/packages/spotless), each performing an OAuth flow
on first use:

- `DNSimple`
- `GitHub`
- `Netlify`
- `Vimeo`

For the input / output shape of each effect, see the
[effects reference](../../guides/effects_reference.md).

## Packages

EYG makes it easy to swap out components of the toolchain.
A sensible reason could be to create a runtime with a unique set of effects, i.e. embed EYG in a game or website.
Another reason could be to imagine your own syntax, or even visual editor, and reuse the EYG interpreter and packages.

- [spec](./spec) A JSON spec of all evaluation rules. Compiler and interpreter implementations should use this as their test suite.
- [gleam_analysis](./packages/gleam_analysis/) Type inference for expressions, effects and scope variables in EYG programs.
- [gleam_cli](./packages/gleam_cli/) The CLI for running EYG programs and interacting with the EYG hub.
- [gleam_hub](./packages/gleam_hub/) Schemas, encoders and decoders for the EYG Hub API. (Unpublished)
- [gleam_ir](./packages/gleam_ir/) Data structures for the EYG IR. This is the original implementation of EYG.
- [gleam_interpreter](./packages/gleam_interpreter/) A Gleam interpreter for EYG targeting JavaScript. Runs in the browser and on the server.
- [gleam_parser](./packages/gleam_parser/) Parser for a curly braces syntax for EYG IR.
- [hub](./packages/hub/) Backend application for [eyg.run](https://eyg.run). Stores modules, packages and signatories.
- [morph](./packages/morph/) Higher level AST and transformation functions for structural edits. (Unpublished)
- [touch_grass](./packages/touch_grass/) Common effect definitions (types, decoders and encoders) for your Eat Your Greens (EYG) runtime.
- [untethered](./packages/untethered/) Location independent datastructures to immutably record decisions. Foundation of EYG hub package signing. (Unpublished)
- [website](./packages/website/) Website for documentation, guides and introduction on [eyg.run](https://eyg.run).

## EYG packages
[eyg_packages](./eyg_packages/)

The source for packages maintained as a standard library i.e. `standard` and `json`.
Other packages in this collection are for demo purposes i.e. `catfact`

## Philosophy

**Building better languages and tools; for some measure of better.**

"Eat Your Greens" is a reference to the idea that eating vegetables is good for you, however the benefit is only realised at some later time.

Projects in this repo introduce extra contraints, over regular programming languages and tools. By doing so more guarantees about the system built on them can be given.

### Previous experiments

Over the last few years the Eat Greens Principle to build actor systems, datalog engines.
A record of these experiments is at https://petersaxton.uk/log/.
The code for these experiments is no longer available if you want to ask more about them reach out to me directly
