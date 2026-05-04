# topological

Topologically sort lists of any type.

[![Package Version](https://img.shields.io/hexpm/v/topological)](https://hex.pm/packages/topological)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/topological/)

```sh
gleam add topological@1
```
```gleam
import topological

pub fn main()  {
  [#("A", ["B", "C"]), #("B", ["C"]), #("C", ["D"]), #("D", [])]
  |> topological.sort
  // Ok(["A", "B", "C", "D"])
}
```

Further documentation can be found at <https://hexdocs.pm/topological>.

## Development

```sh
gleam run
gleam test
```
