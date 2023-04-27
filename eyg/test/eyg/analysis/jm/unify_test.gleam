import gleam/io
import gleam/map
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/unify

pub fn other_test() {
  let assert Ok(#(s, _next)) =
    unify.unify(
      t.Fun(t.Var(1), t.Empty, t.Var(1)),
      t.Fun(t.Var(2), t.Empty, t.String),
      map.new(),
      600,
    )
  s
  |> map.to_list
  |> io.debug
  todo
}
