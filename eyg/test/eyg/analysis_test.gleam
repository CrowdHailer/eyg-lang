import gleam/io
import gleam/option.{Some}
import gleam/list
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/analysis
import eyg/typer

fn variables_needed(source) {
  do_variables_needed(source)
  |> list.unique
  |> list.sort(string.compare)
}

fn do_variables_needed(tree) {
  let #(_, exp) = tree
  case exp {
    e.Binary(_) | e.Hole -> []
    e.Variable(label) -> [label]
    e.Tuple(elems) ->
      list.fold(
        elems,
        [],
        fn(acc, e) { list.append(acc, do_variables_needed(e)) },
      )
    e.Record(fields) ->
      list.fold(
        fields,
        [],
        fn(acc, f) {
          let #(_, e) = f
          list.append(acc, do_variables_needed(e))
        },
      )
    e.Access(e, _) | e.Tagged(_, e) -> do_variables_needed(e)
    e.Call(f, arg) ->
      list.append(do_variables_needed(f), do_variables_needed(arg))
    e.Let(_p, value, then) ->
      list.append(do_variables_needed(value), do_variables_needed(then))
    //   TODO pattern
    e.Function(_p, body) -> do_variables_needed(body)
    e.Case(value, branches) ->
      list.fold(
        branches,
        do_variables_needed(value),
        fn(acc, b) {
          // TODO remove pattern
          let #(_, _, then) = b
          list.append(acc, do_variables_needed(then))
        },
      )
    //   TODO these shouldn't add anything new or we will change them to be eval'd functions
    e.Provider(_, _, _) -> []
  }
  // _ -> todo
}

fn by_type(tree, scope) {
  assert Ok(typer) = do_type(tree, scope, typer.init())
  t.resolve(scope, typer.substitutions)
}

fn do_type(tree, scope, state) -> Result(typer.Typer, _) {
  let #(_, exp) = tree
  case exp {
    e.Variable(label) -> {
      let #(row, state) = typer.next_unbound(state)
      let #(type_, state) = typer.next_unbound(state)
      typer.unify(
        t.Record([#(label, t.Unbound(type_))], Some(row)),
        scope,
        state,
      )
    }
    e.Let(_, value, then) -> do_type(value, scope, state)
    e.Access(term, key) ->
      // This is on the type of the term does nothing to scope. I think need to run through checking the typer
      todo
    _ -> {
      io.debug(exp)
      todo
    }
  }
}

pub fn slim_records_test() -> Nil {
  //   e.let_(p.Record([]), e.record([]), e.hole())

  let source = e.variable("x")
  assert _ =
    by_type(source, t.Unbound(-1))
    |> io.debug

  let source =
    e.let_(
      p.Variable(""),
      e.access(e.variable("x"), "foo"),
      e.let_(p.Variable(""), e.access(e.variable("x"), "foo"), e.hole()),
    )

  assert _ =
    by_type(source, t.Unbound(-1))
    |> io.debug
  todo("slim")
}

pub fn capturing_all_type_variables_test() {
  // If there is a function from string -> string could be a -> b a -> string b -> string
  // how do providers work over this
  let source = e.variable("x")
  assert ["x"] = variables_needed(source)

  let source = e.binary("hello")
  assert [] = variables_needed(source)

  let source = e.call(e.variable("x"), e.variable("y"))
  assert ["x", "y"] = variables_needed(source)

  let source = e.tuple_([e.variable("x"), e.variable("y")])
  assert ["x", "y"] = variables_needed(source)

  let source = e.access(e.variable("x"), "y")
  assert ["x"] = variables_needed(source)

  let source = e.tagged("Y", e.variable("x"))
  assert ["x"] = variables_needed(source)
  //   todo("test")
}
