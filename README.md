# Eat Your Greens (EYG)

A programming language for predictable, useful and confident development.
EYG is an immutable functional language with structural typing and managed effects.

The intermediate representation (IR) of EYG is a minimal tree and is the stable interface for writing EYG programs. Type checking, syntax, evaluation or compilation are optional components built on this foundation.

## Packages

- [spec](./spec) A JSON spec of all evaluation rules. Compiler and interpreter implementations should use this as their test suite.
- [gleam_ir](./packages/gleam_ir) Data structures for the EYG IR. This is the original implementation of EYG.

## Philosophy

**Building better languages and tools; for some measure of better.**

"Eat Your Greens" is a reference to the idea that eating vegetables is good for you, however the benefit is only realised at some later time.

Projects in this repo introduce extra contraints, over regular programming languages and tools. By doing so more guarantees about the system built on them can be given.

### Previous experiments

Over the last few years the Eat Greens Principle to build actor systems, datalog engines.
A record of these experiments is at https://petersaxton.uk/log/.
The code for these experiments is no longer available if you want to ask more about them reach out to me directly
