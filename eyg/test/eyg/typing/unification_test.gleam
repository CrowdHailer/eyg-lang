import gleam/io
import gleam/option.{None, Some}
import eyg/typer/polytype
import eyg/typer
import eyg/typer/monotype as t

pub fn chained_resolve_test() {
  let typer = typer.init()
  assert Ok(typer) = typer.unify(t.Unbound(1), t.Unbound(2), typer)
  assert Ok(typer) = typer.unify(t.Unbound(2), t.Unbound(3), typer)

  let t1 = t.resolve(t.Unbound(1), typer.substitutions)
  let t3 = t.resolve(t.Unbound(3), typer.substitutions)
  assert True = t1 == t3
}

pub fn recursive_unification_test() {
  let typer = typer.init()
  assert Ok(typer) =
    typer.unify(t.Unbound(1), t.Tuple([t.Binary, t.Unbound(2)]), typer)
  assert Ok(typer) = typer.unify(t.Unbound(2), t.Unbound(1), typer)

  assert t.Recursive(0, t.Tuple([t.Binary, t.Unbound(0)])) =
    t.resolve(t.Unbound(1), typer.substitutions)
    |> polytype.shrink

  assert t.Recursive(0, t.Tuple([t.Binary, t.Unbound(0)])) =
    t.resolve(t.Unbound(2), typer.substitutions)
    |> polytype.shrink

  assert Ok(unchanged) = typer.unify(t.Unbound(2), t.Unbound(1), typer)
  assert True = typer == unchanged
}

pub fn unknown_but_recursive_function_test() {
  let t1 =
    t.Function(
      t.Unbound(288),
      t.Recursive(253, t.Function(t.Unbound(288), t.Unbound(253), t.empty)),
      t.empty,
    )
  let t2 =
    t.Recursive(
      i: 0,
      type_: t.Function(
        from: t.Unbound(i: 285),
        to: t.Unbound(i: 0),
        effects: t.empty,
      ),
    )
  assert Ok(_) =
    typer.unify(
      t1,
      t2,
      typer.Typer(next_unbound: 3, inconsistencies: [], substitutions: []),
    )
}

pub fn limited_row_test() {
  let typer = typer.init()
  let t1 = t.Union([#("Some", t.Binary), #("None", t.Tuple([]))], None)
  let t2 = t.Union([#("Some", t.Unbound(-1))], Some(-2))

  assert Ok(typer) = typer.unify(t1, t2, typer)

  // assert Ok(typer) = typer.unify(t.Unbound(2), t.Unbound(3), typer)
  assert t.Binary = t.resolve(t.Unbound(-1), typer.substitutions)
  assert t.Union([#("None", t.Tuple([]))], None) =
    t.resolve(t.Unbound(-2), typer.substitutions)
}

pub fn equal_row_test() {
  let typer = typer.init()
  let t1 = t.Union([#("Some", t.Binary)], None)
  let t2 = t.Union([#("Some", t.Unbound(-1))], Some(-2))

  assert Ok(typer) = typer.unify(t1, t2, typer)

  // assert Ok(typer) = typer.unify(t.Unbound(2), t.Unbound(3), typer)
  assert t.Binary = t.resolve(t.Unbound(-1), typer.substitutions)
  assert t.Union([], None) = t.resolve(t.Unbound(-2), typer.substitutions)
}
