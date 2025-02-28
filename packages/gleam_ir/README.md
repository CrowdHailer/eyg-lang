# EYG IR

Work with the intermediate representation of the [EYG](https://eyg.run) language.
The EYG language is "AST first", there is no textual syntax.
Instead the [AST specification](https://github.com/CrowdHailer/eyg-lang/blob/main/ir/README.md) is the public interface of the language.

This means the language does not need a lexer parser.
Writing interpreters or compilers is much simple.

This library defines:
- A Gleam data structure for working with EYG programs.
- Create immutable references for EYG programs using the [dag-json](https://ipld.io/docs/codecs/known/dag-json/) codec.

[![Package Version](https://img.shields.io/hexpm/v/eyg_ir)](https://hex.pm/packages/eyg_ir)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eyg_ir/)

```sh
gleam add eyg_ir@1
npm install --save @ipld/dag-json@10 multiformats@13
```
```gleam
import eyg/ir/dag_json

pub fn main() {
  let bytes = simplifile.read_bits("my_program.eyg.json")
  let source = dag_json.from_block(bytes)
}
```

Further documentation can be found at <https://hexdocs.pm/eyg_ir>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
