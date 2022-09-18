import gleam/io
import gleam/option.{None, Some}
import gleam/map
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/effectful
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/analysis
import eyg/editor/editor
import eyg/editor/type_info

fn log(term) {
  e.call(e.variable("do"), e.tagged("Log", term))
}

fn log_twice() {
  e.let_(
    p.Variable("a"),
    log(e.binary("hello")),
    e.let_(p.Variable("b"), log(e.binary("world")), e.tuple_([])),
  )
}

fn log_computation() {
  e.function(p.Tuple([]), log_twice())
}

pub fn unhandled_effect_test() {
  let source = log_twice()
  assert Ok(r.Effect("Log", r.Binary("hello"), cont)) = effectful.eval(source)
  assert Ok(r.Effect("Log", r.Binary("world"), cont)) = cont(r.Tuple([]))

  assert Ok(r.Tuple([])) = cont(r.Tuple([]))
}

pub fn unhandled_effect_nested_test() {
  let source = e.call(log_computation(), e.tuple_([]))
  assert Ok(r.Effect("Log", r.Binary("hello"), cont)) = effectful.eval(source)
  assert Ok(r.Effect("Log", r.Binary("world"), cont)) = cont(r.Tuple([]))

  assert Ok(r.Tuple([])) = cont(r.Tuple([]))
}

pub fn functions_test() {
  let source = e.call(e.function(p.Tuple([]), e.binary("return")), e.tuple_([]))
  assert Ok(r.Binary("return")) = effectful.eval(source)
}

fn collect_logs() {
  e.let_(
    p.Variable("collect_logs"),
    e.function(
      p.Variable("effect"),
      e.case_(
        e.variable("effect"),
        [
          #(
            "Log",
            p.Tuple(["e", "k"]),
            e.let_(
              p.Tuple(["list", "value"]),
              e.call(
                e.call(
                  e.call(e.variable("impl"), e.variable("collect_logs")),
                  e.variable("k"),
                ),
                e.tuple_([]),
              ),
              e.tuple_([
                e.tagged(
                  "Cons",
                  e.tuple_([e.variable("e"), e.variable("list")]),
                ),
                e.variable("value"),
              ]),
            ),
          ),
          #(
            "Return",
            p.Variable("value"),
            e.tuple_([e.tagged("Nil", e.tuple_([])), e.variable("value")]),
          ),
        ],
      ),
    ),
    e.variable("collect_logs"),
  )
}

pub fn handled_effect_test() {
  let source = log_computation()
  let handler = collect_logs()
  let handled = e.call(e.call(e.variable("impl"), handler), source)
  assert Ok(r.Tuple([logs, value])) =
    effectful.eval(e.call(handled, e.tuple_([])))
  assert r.Tagged(
    "Cons",
    r.Tuple([
      r.Binary("hello"),
      r.Tagged(
        "Cons",
        r.Tuple([r.Binary("world"), r.Tagged("Nil", r.Tuple([]))]),
      ),
    ]),
  ) = logs
  assert r.Tuple([]) = value
}

// Ask in unison what logging with the same effect but different types should do.

// TODO union never is not the type because it will return the effect handler result
// I can't work out what should be value of effect type

// analysis.get_type shrinks unbound as well so we can't use that for checking 
fn get_sub_type(typed, typer: typer.Typer, path) {
  assert Ok(element) = editor.get_expression(typed, path)
  try type_ = typer.get_type(element)
  Ok(t.resolve(type_, typer.substitutions))
}

fn get_type(typed, typer) {
  get_sub_type(typed, typer, [])
}

pub fn unbound_effect_literal_test() {
  let source = e.call(e.variable("do"), e.tagged("Log", e.binary("hello")))
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

  assert [] = typer.inconsistencies
  assert Ok(t.Unbound(-1)) = get_type(typed, typer)
  assert t.Union(
    [#("Log", t.Function(t.Binary, t.Unbound(-1), after))],
    Some(_),
  ) = t.resolve(t.Unbound(-2), typer.substitutions)

  // TODO do we want linear types
  assert Ok(t.Union([#("Log", t.Binary)], None)) =
    get_sub_type(typed, typer, [1])
  assert Ok(t.Function(t.Union([#("Log", t.Binary)], None), t.Unbound(-1), _)) =
    get_sub_type(typed, typer, [0])
  // test that you can start efect with generic function, probably don't want to support this but checks out in the model
}

pub fn bound_effect_literal_test() {
  let source = e.call(e.variable("do"), e.tagged("Log", e.binary("hello")))
  // I think unbound -2 is effects in the rest of the continuation
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union(
        [#("Log", t.Function(t.Binary, t.Tuple([]), t.Unbound(-2)))],
        None,
      ),
      [],
    )

  assert [] = typer.inconsistencies
  assert Ok(t.Tuple([])) = get_type(typed, typer)

  assert Ok(t.Union([#("Log", t.Binary)], None)) =
    get_sub_type(typed, typer, [1])
  assert Ok(t.Function(t.Union([#("Log", t.Binary)], None), t.Tuple([]), _)) =
    get_sub_type(typed, typer, [0])
}

pub fn infering_function_effect_test() {
  let source =
    e.function(
      p.Tuple([]),
      e.call(e.variable("do"), e.tagged("Log", e.binary("hello"))),
    )
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  assert [] = typer.inconsistencies
  assert Ok(t.Function(t.Tuple([]), t.Unbound(return), effects)) =
    get_type(typed, typer)
  assert t.Union([#("Log", t.Function(t.Binary, t.Unbound(resolve), _))], _) =
    effects
  assert True = resolve == return
}

pub fn incorrect_effect_raised_test() {
  let source = e.call(e.variable("do"), e.tagged("Log", e.tuple_([])))
  // I think unbound -2 is effects in the rest of the continuation
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union(
        [#("Log", t.Function(t.Binary, t.Tuple([]), t.Unbound(-2)))],
        None,
      ),
      [],
    )

  assert [#([0], typer.UnmatchedTypes(t.Binary, t.Tuple([])))] =
    typer.inconsistencies
  assert Error(typer.UnmatchedTypes(_, _)) = get_sub_type(typed, typer, [0])
}

pub fn incorrect_effect_returned_test() {
  let source = e.call(e.variable("do"), e.tagged("Log", e.binary("hello")))
  // I think unbound -2 is effects in the rest of the continuation
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Binary,
      t.Union(
        [#("Log", t.Function(t.Binary, t.Tuple([]), t.Unbound(-2)))],
        None,
      ),
      [],
    )

  assert [#([0], typer.UnmatchedTypes(t.Tuple([]), t.Binary))] =
    typer.inconsistencies
}

pub fn effect_with_not_a_union_type_test() {
  let source = e.call(e.variable("do"), e.tuple_([]))
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

  assert [#([1], typer.UnmatchedTypes(t.Union(_, _), t.Tuple([])))] =
    typer.inconsistencies
}

pub fn effect_with_a_big_union_type_test() {
  let source = e.call(e.variable("do"), e.variable("x"))
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Unbound(-2),
      [
        #(
          "x",
          polytype.Polytype(
            [],
            t.Union([#("Foo", t.Binary), #("Bar", t.Binary)], None),
          ),
        ),
      ],
    )

  assert [#([1], typer.UnexpectedFields([#("Foo", _), #("Bar", _)]))] =
    typer.inconsistencies
}

pub fn cant_call_effect_in_pure_env_test() {
  let source = e.call(e.variable("do"), e.tagged("Log", e.binary("hello")))
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  // maybe this ends up on the call level i.e. an error at the root
  assert [#([0], typer.UnexpectedFields([#("Log", _)]))] = typer.inconsistencies
}

pub fn mismateched_effect_test() {
  let source = e.tuple_([log(e.binary("hello")), log(e.tuple_([]))])
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

  assert [
    #(
      [1, 0],
      typer.UnmatchedTypes(expected: t.Binary, given: t.Tuple(elements: [])),
    ),
  ] = typer.inconsistencies
}

pub fn mismateched_effect_in_block_test() {
  let source = e.let_(p.Tuple([]), log(e.binary("hello")), log(e.tuple_([])))
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

  assert [
    #(
      [2, 0],
      typer.UnmatchedTypes(expected: t.Binary, given: t.Tuple(elements: [])),
    ),
  ] = typer.inconsistencies
}

// --------------------- Handle Keyword -----------------------------

pub fn not_a_function_handler_test() {
  let source = e.call(e.variable("impl"), e.binary("yo!"))
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  // maybe this ends up on the call level i.e. an error at the root
  assert [#([1], typer.UnmatchedTypes(t.Function(_, _, _), t.Binary))] =
    typer.inconsistencies
  // TODO test that it's still in the tree
}

pub fn handler_is_not_union_test() {
  let source =
    e.call(e.variable("impl"), e.function(p.Tuple([]), e.binary("yo!")))
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  // maybe this ends up on the call level i.e. an error at the root
  // TODO errors should return the actual top types at the position and then print the diff
  assert [#([1], typer.UnmatchedTypes(t.Union(_, _), t.Tuple([])))] =
    typer.inconsistencies
}

pub fn handler_is_missing_effect_test() {
  let source =
    e.call(
      e.variable("impl"),
      e.function(
        p.Variable("effect"),
        e.case_(
          e.variable("effect"),
          [#("Return", p.Tuple([]), e.binary("pure"))],
        ),
      ),
    )
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  // maybe this ends up on the call level i.e. an error at the root
  // TODO errors should return the actual top types at the position and then print the diff
  // This error would be better if it said the case was missing fields but that's not how we work
  assert [#([1, 1, 0], typer.UnexpectedFields(_))] = typer.inconsistencies
}

pub fn infer_handler_test() {
  let handler =
    e.function(
      p.Variable("eff"),
      e.case_(
        e.variable("eff"),
        [
          #("Return", p.Tuple([]), e.tuple_([e.binary("foo"), e.tuple_([])])),
          #(
            "Foo",
            p.Tuple(["v", "k"]),
            e.tuple_([
              e.variable("v"),
              e.call(e.variable("k"), e.binary("read")),
            ]),
          ),
        ],
      ),
    )
  let source = e.call(e.variable("impl"), handler)
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  assert [] = typer.inconsistencies
  // calling the catch function never raises effects even if evaluating the arguments might
  assert Ok(t.Function(computation, exec, t.Union([], None))) =
    get_type(typed, typer)

  // Final returned type is the arm values of case statements in the handler
  assert t.Function(
    t.Unbound(input),
    t.Tuple([t.Binary, t.Tuple([])]),
    t.Union([], Some(outer)),
  ) = exec

  // Pure handles a tuple so the return type here needs to be the same
  // Foo effect is available to computation, but we also need to extend by the environment effects
  assert t.Function(
    t.Unbound(i),
    t.Tuple([]),
    t.Union([#("Foo", effect)], Some(other_effects)),
  ) = computation
  assert True = i == input
  assert True = other_effects == outer
  assert t.Function(t.Binary, t.Binary, eff) = effect
}

pub fn infer_continuation_type_test() {
  let handler =
    e.function(
      p.Variable("eff"),
      e.case_(
        e.variable("eff"),
        [
          #("Return", p.Variable(""), e.hole()),
          #(
            "Foo",
            p.Tuple(["v", "k"]),
            e.tuple_([e.variable("v"), e.variable("k")]),
          ),
        ],
      ),
    )
  let source = e.call(e.variable("impl"), handler)
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  assert [#(_, typer.Warning(_))] = typer.inconsistencies
  // calling the catch function never raises effects even if evaluating the arguments might
  assert Ok(t.Function(computation, exec, t.Union([], None))) =
    get_type(typed, typer)

  // Final returned type is the arm values of case statements in the handler
  assert t.Function(
    t.Unbound(input),
    t.Tuple([
      t.Unbound(effect_arg),
      t.Function(t.Unbound(effect_return), t.Unbound(cont_return), cont_effect),
    ]),
    t.Union([], Some(outer)),
  ) = exec
  assert t.Function(
    t.Unbound(i),
    t.Unbound(c_ret),
    t.Union([#("Foo", effect)], Some(other_effects)),
  ) = computation
  assert t.Function(t.Unbound(eff_arg), t.Unbound(eff_ret), eff) = effect
  assert True = i == input
  assert True = effect_arg == eff_arg
  assert True = effect_return == eff_ret
  // cont_return is trivial
  assert True = cont_return == c_ret
}

pub fn recursive_handler_test() {
  let source = e.call(e.variable("impl"), collect_logs())
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

  assert [] = typer.inconsistencies

  // calling the catch function never raises effects even if evaluating the arguments might
  assert Ok(t.Function(computation, exec, t.Union([], None))) =
    get_type(typed, typer)

  // Final returned type is the arm values of case statements in the handler
  assert t.Function(
    t.Unbound(input),
    t.Tuple([list, value]),
    t.Union([], Some(outer)),
  ) = exec
  assert t.Recursive(
    i,
    t.Union(
      [#("Cons", t.Tuple([t.Unbound(_), t.Unbound(r)])), #("Nil", t.Tuple([]))],
      _,
    ),
  ) = list
  assert True = i == r

  assert t.Function(
    t.Unbound(i),
    c_ret,
    t.Union([#("Log", effect)], Some(other_effects)),
  ) = computation
  // assert t.Function(t.Unbound(eff_arg), t.Unbound(eff_ret), eff) = effect
  assert True = i == input
  assert True = value == c_ret
  assert True = outer == other_effects
}

// --------------------- LOG functions ------------------------------

const log_fn = #(
  "log",
  polytype.Polytype(
    [1],
    t.Function(t.Binary, t.Tuple([]), t.Union([#("Log", t.Binary)], Some(1))),
  ),
)

const abort_fn = #(
  "abort",
  polytype.Polytype(
    [1],
    t.Function(
      t.Tuple([]),
      t.Tuple([]),
      t.Union([#("Abort", t.Tuple([]))], Some(1)),
    ),
  ),
)

pub fn single_effect_test() {
  let source = e.call(e.variable("log"), e.binary("my log"))

  // I think effect type should just be union
  // open effects space
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [log_fn])
  assert t.Union([#("Log", t.Binary)], Some(_)) =
    t.resolve(t.Unbound(-2), typer.substitutions)
  assert [] = typer.inconsistencies

  // unbound term of effect
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union([#("Log", t.Unbound(-2))], None),
      [log_fn],
    )
  assert t.Binary = t.resolve(t.Unbound(-2), typer.substitutions)
  assert [] = typer.inconsistencies

  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union([#("Log", t.Binary)], None),
      [log_fn],
    )
  assert [] = typer.inconsistencies

  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union([#("Log", t.Tuple([]))], None),
      [log_fn],
    )
  assert [#([0], typer.UnmatchedTypes(t.Tuple([]), t.Binary))] =
    typer.inconsistencies

  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn])
  assert [#([0], typer.UnexpectedFields([#("Log", t.Binary)]))] =
    typer.inconsistencies

  // function test
  let source = e.function(p.Tuple([]), source)
  // Potentially open is a better name to t.empty
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn])
  assert [] = typer.inconsistencies
  assert t.Function(t.Tuple([]), t.Tuple([]), effect) =
    t.resolve(t.Unbound(-1), typer.substitutions)
  assert t.Union([#("Log", t.Binary)], Some(_)) = effect
}

pub fn multiple_call_effect_test() {
  let source =
    e.call(e.variable("abort"), e.call(e.variable("log"), e.binary("my log")))

  // I think effect type should just be union
  // open effects space
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Unbound(-2),
      [log_fn, abort_fn],
    )
  assert [] = typer.inconsistencies
  assert t.Union([#("Abort", t.Tuple([])), #("Log", t.Binary)], Some(_)) =
    t.resolve(t.Union([], Some(-2)), typer.substitutions)

  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union([#("Log", t.Tuple([]))], None),
      [log_fn, abort_fn],
    )
  assert [
    #([1, 0], typer.UnmatchedTypes(t.Tuple([]), t.Binary)),
    #([0], typer.UnexpectedFields([#("Abort", t.Tuple([]))])),
  ] = typer.inconsistencies

  // function test
  let source = e.function(p.Tuple([]), source)
  // Potentially open is a better name to t.empty
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn, abort_fn])
  assert [] = typer.inconsistencies
  assert t.Function(t.Tuple([]), t.Tuple([]), effect) =
    t.resolve(t.Unbound(-1), typer.substitutions)
  assert t.Union([#("Abort", t.Tuple([])), #("Log", t.Binary)], Some(_)) =
    effect
}

pub fn multiple_let_effect_test() {
  let source =
    e.let_(
      p.Tuple([]),
      e.call(e.variable("log"), e.binary("my log")),
      e.call(e.variable("abort"), e.tuple_([])),
    )

  // I think effect type should just be union
  // open effects space
  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Unbound(-2),
      [log_fn, abort_fn],
    )
  assert [] = typer.inconsistencies
  assert t.Union([#("Log", t.Binary), #("Abort", t.Tuple([]))], Some(_)) =
    t.resolve(t.Union([], Some(-2)), typer.substitutions)

  let #(typed, typer) =
    analysis.infer_effectful(
      source,
      t.Unbound(-1),
      t.Union([#("Log", t.Tuple([]))], None),
      [log_fn, abort_fn],
    )
  assert [
    #([2, 0], typer.UnexpectedFields([#("Abort", t.Tuple([]))])),
    #([1, 0], typer.UnmatchedTypes(t.Tuple([]), t.Binary)),
  ] = typer.inconsistencies

  let source = e.function(p.Tuple([]), source)
  // Potentially open is a better name to t.empty
  let #(typed, typer) =
    analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn, abort_fn])
  assert [] = typer.inconsistencies
  assert t.Function(t.Tuple([]), t.Tuple([]), effect) =
    t.resolve(t.Unbound(-1), typer.substitutions)
  assert t.Union([#("Log", t.Binary), #("Abort", t.Tuple([]))], Some(_)) =
    effect
}
