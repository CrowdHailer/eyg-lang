import gleam/io
import gleam/map
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/unify

pub fn example_test() {
  unify.unify(
    t.Fun(t.Var(578), t.Var(579), t.Fun(t.Var(575), t.Var(579), t.Var(580))),
    t.Fun(t.Fun(t.String, t.Var(584), t.String), t.Var(583), t.String),
    map.new(),
    600
  )
  |> io.debug
}