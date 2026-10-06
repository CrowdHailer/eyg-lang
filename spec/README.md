# EYG Spec

Specification of the EYG language.
Includes test suites for features to encourage valid alternative implementations.

## Why "no syntax"

The intermediate representaion of EYG is the stable interface for the language.
There is "no syntax" for the EYG language. This differs from most languages where the surface syntax is the public interface and IR/AST is an implementation detail that is not guaranteed to be stable.

Tools that build on EYG do not have to reimplement parsing before they can work with programs as a structural level.

- Want your own syntax? Build a parser to target the IR and use the rest of the EYG tooling to run it. 
- Need a new runtime? Use the EYG editor and build your own interpreter or compiler.
- Fancy your own type system? Write your own and keep the editor and runtimes.

## Intermediate Representation(IR) in JSON

This section describes the JSON structure of a stored EYG program.
Tests for encoding, decoding and hashing are in [ir_suite.json](./ir_suite.json)

**NOTE:** EYG does not have an official syntax, instead the IR is the front-end for the language tooling.

All valid programs have a single root expression.

The type of each node is identified by a value under the `"0"` key.
Nodes then have additional fields dependent on the type of the node.

*To keep the size of JSON documents small(ish) single letter codes are used when possible.*

All fields specified for a node are required.
There are no optional fields.
To represent an incomplete program use the `vacant` node, which is a valid expression node for hole in the program.

IR's are recursive structures, where a node has child nodes is indicated with the `expression` value.

`label` represent variables, record fields, union variants builtin identifiers and effect identifiers.
The only requirement on label string is that they are nonempty and contain no whitespace charachacters.

The IR structure is a valid [dag-json](https://ipld.io/docs/codecs/known/dag-json/) structure.
Bytes are encoded according to the DAG JSON Spec. 
References are encoded as Content IDentifiers (CIDs).

```js
// variable
{"0": "v", "l": label}
// lambda(label, body)
{"0": "f", "l": label, "b": expression}
// apply(function, argument)
{"0": "a", "f": expression, "a": expression}
// let(label, value, then)
{"0": "a", "l": label, "v": expression, "t": expression}
// b already taken when adding binary
// binary(value)
{"0": "x", "v": bytes}
// integer(value)
{"0": "i", "v": integer}
// string(value)
{"0": "s", "v": string}
// tail
{"0": "ta"}
// cons
{"0": "c"}
// vacant(comment)
{"0": "z", "c": string}
// empty
{"0": "u"}
// extend(label)
{"0": "e", "l": label}
// select(label)
{"0": "g", "l": label}
// overwrite(label)
{"0": "o", "l": label}
// tag(label)
{"0": "t", "l": label}
// case(label)
{"0": "m", "l": label}
// nocases
{"0": "n"}
// perform(label)
{"0": "p", "l": label}
// handle(label)
{"0": "h", "l": label}
// shallow(label)
{"0": "hs", "l": label}
// mask(label)
{"0": "hm", "l": label}
// builtin(label)
{"0": "b", "l": label}
// empty table
{"0": "q0"}
// fact constructor: value -> Table(Relation(value))
{"0": "qf", "l": label}
// lazy rule constructor: (Table(rows) -> Table(rows)) -> Table(rows)
{"0": "qr"}
// table combination: Table(rows) -> Table(rows) -> Table(rows)
{"0": "qm"}
// resolve: Table(Relation(value), rows) -> List(value)
{"0": "qs", "l": label}
// reference(identifier)
{"0": "#", "l": cid}
// release(project,release,identifer)
{"0": "#", "p": string, "r": integer, "l": cid}
```

## Handler semantics

`Handle(label)` (`h`) is a curried two-argument primitive: operation callback,
then body thunk. The body is called with `{}`. On a matching effect the callback
receives the payload and a deep continuation. That continuation includes the
matching delimiter. The callback runs outside it; normal body return passes
through unchanged.

`Mask(label)` (`hm`) takes one body thunk. Operations crossing its boundary skip
one enclosing matching handler; newly installed inner handlers still apply.
Mask frames remain in captured resumptions. An operation with an outstanding
mask at the host boundary fails with `MaskedEffect`, not platform dispatch.
Its type is `({} -> e A) -> <E(P,Q) | e> A`, with independent skipped-handler
request and reply types. Duplicate labels are scoped, not set-unioned.

`!pure(f)` returns a wrapper that installs a purity boundary for each application.
Dispatch reaching that boundary fails with `ImpureEffect` before any outer
handler or the host runs. Inner handlers are allowed; the guard is not inherited
by functions returned from the application. Non-functions are rejected.
These rules apply with or without type checking. Shared positive and negative
fixtures are in `masking.json` and `masking_errors.json`.

`Shallow(label)` (`hs`) takes operation callback, normal-return callback, then
body thunk. It captures the suspended computation **without** its matching
delimiter or return callback. Normal completion under the delimiter calls the
return callback; an operation callback's answer bypasses it. Both callbacks run
outside the delimiter. The raw body result and handled answer can have different
types. A raw continuation retains the body's effects, including the handled label.

Both primitives capture intervening inner handlers but not outer delimiters.
Both permit abandoning or repeatedly resuming immutable continuations.
See [the shallow guide](../guides/shallow_effect_handlers.md) for the type rule
and its conservative scoped-row restriction.

The source fixtures in [shallow_handlers.json](./shallow_handlers.json) are
shared by the parser-backed inference, interpreter, and compiler tests.
The existing JSON IR fixtures and their content identifiers remain compatible;
`ir_suite.json` includes the separate `hs` encoding.

## Values

### Records

A record is a map from label to value, the same structure a dag-json map has,
so a record has at most one field for any label.
`extend` on a record that already has the label replaces the value.

A record type must not name the same label twice.
A type such as `{a: Integer, a: String}` describes a value that cannot be
built, and every operation on the record reaches the first of the two, so the
second is a promise nothing can keep.
The analysis rejects programs where such a type is inferred.

### Unions

A union value is one tag and one value, and `case` peels one row at a time, so
a union type may name the same label more than once.
In `[Ok: Integer | Ok: String]` the second row is the type of the value the
`otherwise` branch of a match on `Ok` receives.

### Recursion

`fix` takes a constructor and passes it the function being built.
Applying that self reference runs the constructor again, so:

- the constructor must return a function, the self reference is always one
- the constructor must be pure, otherwise its effects are performed again on
  every recursive call, somewhere the type of the built function cannot
  describe

Work that only needs doing once belongs outside `fix`.

## Builtins

Query operations are atoms applied with ordinary `apply` nodes. A rule stores a
pure function over a table of facts. Resolution starts with all input facts,
calls every rule with the same snapshot, unions the returned facts, and repeats
until no new facts appear. Equality gives set semantics. Rule functions must
return facts, and effects cannot escape a rule to its caller or host runtime.
The text parser lowers joins to list folds over the snapshot and pattern
constraints to pure equality tests. This keeps rule expressions available to
tree traversal, sharing, and closure capture without a second expression AST.

Tables contain a row of named relations; table combination unifies these rows.
The empty table and each fact have an open relation row so independent tables
can be combined. An absent relation resolves to an empty list. Recursive rules
with value-generating expressions need a finite bound to reach a fixed point.

Builtins must behave the same way for all implementations.
There is a test suite available in this repo that for checking the behaviour of all builtins.

The set of builtins is as small as possible so consistency accross implementations is achievable.
Builtins should not be considered the EYG standard library.
A larger library of functionality is maintained and available under the `@standard` package.

Functionality like inspecting terms should be implemented as effects.
This allows implementations of the `Debug` effect to differ.
Any inconsistency in result is completly tracked in the behaviour of the Debug effect.

Some builtins create new records/unions, i.e. `int_compare` or `list_pop`
There is also a `fix` builtin that introduces recursion.
This means there are no guarantees about memory usage of a general EYG program.

It is possible to track use of builtins if you want these gurantees.
Absence of `fix` alone does not prove termination: unchecked self-application,
effect handlers, imports, and external waits must also be considered.
Both `fix` and recursive queries can express nonterminating computations.
It is a non-goal of the eyg libraries to support all these usecases.
However if you have a need for them please reach out.
