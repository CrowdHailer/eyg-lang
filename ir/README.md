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

`bytes` are base64 encoded.

```js
// variable
{"0": "v", "l": label}
// lambda(label, body)
{"0": "f", "l": label, "b": expression}
// apply(function, argument)
{"0": "a", "f": expression, "a": expression}
// let(label, value, then)
{"0": "l", "l": label, "v": expression, "t": expression}
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
// reference(label)
{"0": "#", "l": label}
```
