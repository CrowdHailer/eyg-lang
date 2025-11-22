# eyg_analysis

Type inference for EYG.
Uses algorithm J with levels https://okmij.org/ftp/ML/generalization.html as a basis.
Records, Unions and Effects are all implemented as row types.

[![Package Version](https://img.shields.io/hexpm/v/eyg_analysis)](https://hex.pm/packages/eyg_analysis)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eyg_analysis/)

## Usage

Analysing an EYG program completly infers the type of every node.
Type information includes the following for every node:
- The type of the expression
- Any type errors
- Any effects raised by evaluating the expression
- The type of all variables in scope for that expression

When passing ref types in then everything should generalise Except where there are holes/errors

cache in the website and fragment are both worth looking at

```gleam
import eyg_analysis

pub fn main() {
  let source = ir.Let("x", ir.Integer(5), ir.Variable("x"))
}
```

Further documentation can be found at <https://hexdocs.pm/eyg_analysis>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Dicussions

- Should `debug` be part of this module?
  Usefully printing large types requires more sophistication than converting to a single string representation.