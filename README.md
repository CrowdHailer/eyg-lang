# Eat Your Greens (EYG)

A programming language for predictable, useful and confident development.
EYG is an immutable functional language with structural typing and managed effects.

The intermediate representation (IR) of EYG is a minimal tree and is the stable interface for writing EYG programs. Type checking, syntax, evaluation or compilation are optional components built on this foundation.

## Get started

To run scripts from your shell use the [CLI](./packages/gleam_cli/).
checkout the [examples](./packages/gleam_cli/examples/)

The CLI implements effects for:
- `Fetch` make HTTP request
- `Read` read a file on the file system
- `DecodeJSON` Decode JSON using the host language.

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
- [morph](./packages/morph/) Higher level AST and transformation functions for structural edits. (Unpublished)
- [touch_grass](./packages/touch_grass/) Common effect definitions (types, decoders and encoders) for your Eat Your Greens (EYG) runtime.
- [untethered](./packages/untethered/) Location independent datastructures to immutably record decisions. Foundation of EYG hub package signing. (Unpublished)

## Philosophy

**Building better languages and tools; for some measure of better.**

"Eat Your Greens" is a reference to the idea that eating vegetables is good for you, however the benefit is only realised at some later time.

Projects in this repo introduce extra contraints, over regular programming languages and tools. By doing so more guarantees about the system built on them can be given.

### Previous experiments

Over the last few years the Eat Greens Principle to build actor systems, datalog engines.
A record of these experiments is at https://petersaxton.uk/log/.
The code for these experiments is no longer available if you want to ask more about them reach out to me directly
