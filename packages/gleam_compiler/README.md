# eyg_compile

[EYG](https://eyg.run) compiler that transpiles to JavaScript.

[![Package Version](https://img.shields.io/hexpm/v/eyg_compile)](https://hex.pm/packages/eyg_compile)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eyg_compile/)

```sh
gleam add eyg_compiler
```
```gleam
import eyg/compiler
import eyg/ir/tree as ir
import gleam/dict

pub fn main() {
  let source = ir.let_("x", ir.integer(5), ir.variable("x"))
  let refs = dict.new()
  compiler.to_js(source, refs)
  // let x$0 = 5;
  // x$0
}
```

Further documentation can be found at <https://hexdocs.pm/eyg_compile>.

## Development

```sh
gleam run
gleam test
```

## Notes

Compilation path follows two main resources.

- [MinCaml](https://www.kb.ecei.tohoku.ac.jp/~sumii/pub/FDPE05.pdf)
- [Generalized Evidence Passing for Effect Handler](https://www.microsoft.com/en-us/research/uploads/prod/2021/08/genev-icfp21.pdf)
  - Long version (https://www.microsoft.com/en-us/research/uploads/prod/2021/03/multip-tr-v4.pdf)

The current implementation uses a `js` version of a monad, something is an instance of an `Eff` or not.
If not is is assumed a value. This is similar to thinking of value or `null` being an `Option`.

This allows the transpiled JS to look as similar as possible to the original source.
There is no lambda lifting or closure conversion and there is no global `yielding` variable.
These are not necessary when relying on the dynamism of JS.

Such an implementation is ineffecient as it always bubbles the effect, there is no evidence passing.
A future version could add the evidence vector and other optimisation, however:
- readability would be effected.
- performance should not be sort before measurement.
- A fast interpreter with flat AST may be faster and simpler.

It's probably worth considering what compilation to tiny go or an arduino interpreter looks like.

- Is there a way to check for tail resumption if handler is passed as var and not AST? 
  This is needed if trying to optimise away bubbling in the general case
