![penelopea mascot for EYG](https://eyg.run/assets/pea.8C463682609CAA4A5A638D66BAA7C5F8115EB83B6ED1D7FA3DE7ABC8F2CAB5AA.webp)

Source code for the EYG language and Overlay harness.

Try them out on the [website](https://eyg.run) or install the CLI locally:

```sh
curl -fsSL https://eyg.run/install | bash
```

Join the discussion on [discord](https://discord.gg/e4Js8xH7H)

## Philosophy

**Building better languages and tools; for some measure of better.**

"Eat Your Greens" is a reference to the idea that eating vegetables is good for you, however the benefit is only realised at some later time.

All the projects in this repository exist to increase the guarantees available when you build on them. 

Projects in this repo introduce extra contraints, over regular programming languages and tools. By doing so more guarantees about the system built on them can be given.

## Resources

- For the full CLI reference see [`packages/gleam_cli/README.md`](./packages/gleam_cli/README.md).
- To create, protect, and use publishing identities see [`guides/managing_signatories.md`](./guides/managing_signatories.md).
- The language syntax is described in [`guides/syntax.md`](./guides/syntax.md).
- Every `!builtin` is catalogued in [`guides/builtins_reference.md`](./guides/builtins_reference.md).
- Full effect reference is in [`./guides/cli_effects_reference.md`](./guides/cli_effects_reference.md).
- File and import path resolution is explained in [`guides/file_resolution.md`](./guides/file_resolution.md).
- To install from source see [`./guides/install_from_source.md`](./guides/install_from_source.md).

## Packages

The intermediate representation (IR) of EYG is a minimal tree and is the stable interface for writing EYG programs. 
Type checking, syntax, evaluation or compilation are optional components built on this foundation.

This repository contains the language definition, implementation, website and package hub.

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
- [vscode-eyg](./packages/vscode-eyg/) VS Code extension and canonical TextMate grammar, also used by the web guides.
- [website](./packages/website/) Website for documentation, guides and introduction on [eyg.run](https://eyg.run).

## EYG packages
[eyg_packages](./eyg_packages/)

The source for packages maintained as a standard library i.e. `standard` and `json`.
The [`overlay`](./eyg_packages/overlay/) package contains policy and skills helpers for overlay agents.
Other packages in this collection are for demo purposes i.e. `catfact`

### Previous experiments

Over the last few years the Eat Greens Principle to build actor systems, datalog engines.
A record of these experiments is at https://petersaxton.uk/log/.
The code for these experiments is no longer available if you want to ask more about them reach out to me in the [discord](https://discord.gg/e4Js8xH7H)
