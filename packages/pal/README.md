# Platform Abstraction Layer (PAL)

A Gleam flavour of Rust's Hardware Abstraction Layer (HAL).

This package is not a perfect reflection of the ideas below.
Potentially the harness for the Web CLI should be defined independently as it is the interface.
The harness could be defined in another package or part of touch_grass, it is runtime independent.
The remaining code, Gleam bindings to the browser and an implementation of the web cli interface are both browser and JS specific.
They belong together but perhaps pal is not a good package name as that is the general concept

## Abstractions

Application code relies on interfaces not concrete implementations.
An application will rely on many interfaces that are bundled into a specific platform.
Certain components will rely on a subset of interfaces in a platform.
It is possible for an interface to be impersonated by a platform as long as the contract holds.
The most obvious reason for impersonating interfaces is testing.

### Capabilities

An effect represents a platform capability such as `Now` for access to time or `ReadFile`.
A feature of a platform is an informal grouping of capabilities.
For example the file system exposes multiple effects; `ReadFile`, `WriteFile` and more operations.
However each effect can be implemented individually and it is possible for a platform to expose readonly file systems.
The `touch_grass` package describes individual effects.
For each effect it provides a canonical label, type specs and encoder/decoder for values supplied by and returned to the application.

*A capability trait describes the interface for a hardware feature and is analagous to an effect.*

### Harness

An EYG harness is the set of effects available to an EYG program.
The harness is the only interface into a platform for the EYG code.
EYG has no assumed effects. Therefore any capability outside the program must be part of the harness.
In this package `pal/harness` describes the Web CLI harness.
This is a general harness that is designed to expose most of the browsers capabilities
The module `pal/browser` defines all the Gleam access to the browser.

*A Rust applications trait bounds are equivalent to an EYG harness*

### Runner

The runner is a platform specific implementation of the harness.
It is the runner's responsibility to fetch and cache modules/package lookup.

*In the rust ecosystem an MCU is the runner*

## Development

```sh
gleam test
```
