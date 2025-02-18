# Morph

For manipulating programs in more semantic units.

Defines:

- `Editable` as a user friendly representation of program AST's.
It introduces the ability to have multi argument functions, patterns and other constructs.

- `Projection` as an inverted view of program focusing on a specific node and it's surrounding context.

breaks was one of the names of the list of paths
could be context or base as in base of cone
// scope is too near variable scope
// focus as center and context
// zoom has focus and breaks
// loci
target and base
projection
transpose
 path is the list of ints
project onto a surface
target/situation surroundsing
environs/locallity,perifery
district/situation

### Non goals

- inference, loading, running, undo, redo, no mapping from text to position, suggestions, autocomplete
- key bindins to given transforms

## Questions

How to link to type information.
The tree could be enhanced with meta data or we need to map to a plain AST concept of a path

## Morph/Lustre

Render `Editable` code and `Projection`s into HTML using Lustre elements.

The projections are built into a set of nested frames,
indicating in the printed output is single line or multiline.
This abstraction might match the formatting libraries that already exist and is so using one of them might be a good idea.

Rendering something at the focus of a projection can be done by using the `projection_frame` function

## Paths

Each node in the Editable tree can be found by a path to it.
The path is a list of integers where each integer identifies the child of a node to step to to continue the path.

## Projections

