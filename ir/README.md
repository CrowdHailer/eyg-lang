# EYG Intermediate Representation(IR) in JSON

This document describes the JSON structure of an EYG program.
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
// builtin(label)
{"0": "b", "l": label}
// reference(identifier)
{"0": "#", "l": cid}
// release(project,release,identifer)
{"0": "#", "p": string, "r": integer, "l": cid}
```

## Builtins

Builtins must behave the same way for all implementations.
There is a test suite available in this repo that for checking the behaviour of all builtins.

The set of builtins is as small as possible so consistency accross implementations is achievable.
Builtins should not be considered the EYG standard library.
A larger library of functionality is maintained and available under the `@stdlib` package.

Functionality like inspecting terms should be implemented as effects.
This allows implementations of the `Debug` effect to differ.
Any inconsistency in result is completly tracked in the behaviour of the Debug effect.

Some builtins create new records/unions, i.e. `int_compare` or `list_pop`
There is also a `fix` builtin that introduces recursion.
This means there are no guarantees about memory usage of a general EYG program.

It is possible to track use of builtins if you want these gurantees.
For example a program without `fix` is total an guaranteed to terminate.
It is a non-goal of the eyg libraries to support all these usecases.
However if you have a need for them please reach out.

## Legacy 