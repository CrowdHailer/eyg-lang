# eyg_interpreter

Gleam implementation of the [EYG](https://eyg.run) language.
This implementation runs on JavaScript runtimes and works in the browser.

[![Package Version](https://img.shields.io/hexpm/v/eyg_interpreter)](https://hex.pm/packages/eyg_interpreter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eyg_interpreter/)

```sh
npm install --save @ipld/dag-json@10 multiformats@13
gleam add eyg_interpreter@1
```

This library defines two execution modes:
- expression - always returns a value
- block - optionally returns a value and the final environment.

If in doubt use the expression module.
Block is useful for creating shells (or REPLs, terminals, consoles).

```gleam
import eyg/interpreter/expression
import eyg/ir/tree as ir

pub fn main() {
  let source = ir.Let("x", ir.Integer(5), ir.Variable("x"))
  let scope = []
  expression.execute(source, scope)
  // => value.Integer(5)
}
```

Further documentation can be found at <https://hexdocs.pm/eyg_interpreter>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
