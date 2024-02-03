import gleam/io
import gleam/list
import gleam/result
import eyg/parse/lexer
import eyg/parse/parser
import gleeunit/should
import eyg/analysis/fast_j as j

fn parse(src) {
  src
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
}

fn do_resolve(return) {
  let #(acc, bindings) = return
  list.map(acc, fn(node) {
    let #(typed, effect, env) = node
    let typed = case typed {
      Ok(type_) -> Ok(j.resolve(type_, bindings))
      Error(reason) -> Error(reason)
    }
    let effect = j.resolve(effect, bindings)
    #(typed, effect, env)
  })
}

fn drop_env(results) {
  list.map(results, fn(r) {
    let #(type_, eff, _env) = r
    #(type_, eff)
  })
}

fn do_render(results) {
  list.map(results, fn(r) {
    let #(type_, eff) = r
    #(result.map(type_, j.render_type), j.render_effects(eff))
  })
}

pub fn literal_test() {
  "5"
  |> parse
  |> j.infer
  |> do_resolve()
  |> should.equal([#(Ok(j.Integer), j.Empty, [])])
}

pub fn pure_function_test() {
  "(_) -> 5"
  |> parse
  |> j.infer
  |> do_resolve()
  |> should.equal([
    #(Ok(j.Fun(j.Var(0), j.Empty, j.Integer)), j.Empty, []),
    #(Ok(j.Integer), j.Empty, [#("_", j.Var(#(False, 0)))]),
  ])

  "(x) -> x"
  |> parse
  |> j.infer
  |> do_resolve()
  |> should.equal([
    #(Ok(j.Fun(j.Var(0), j.Empty, j.Var(0))), j.Empty, []),
    #(Ok(j.Var(0)), j.Empty, [#("x", j.Var(#(False, 0)))]),
  ])
}

pub fn let_polymorphism_test() {
  "let f = (x) -> x
  let y = f(3)
  f(\"hey\")"
  |> parse
  |> j.infer
  |> do_resolve()
  |> drop_env()
  |> should.equal([
    #(Ok(j.String), j.Empty),
    #(Ok(j.Fun(j.Var(0), j.Empty, j.Var(0))), j.Empty),
    #(Ok(j.Var(0)), j.Empty),
    #(Ok(j.String), j.Empty),
    #(Ok(j.Integer), j.Empty),
    #(Ok(j.Fun(j.Integer, j.Empty, j.Integer)), j.Empty),
    #(Ok(j.Integer), j.Empty),
    #(Ok(j.String), j.Empty),
    #(Ok(j.Fun(j.String, j.Empty, j.String)), j.Empty),
    #(Ok(j.String), j.Empty),
  ])
}

pub fn perform_test() {
  "perform Log(5)"
  |> parse
  |> j.infer
  |> do_resolve()
  |> drop_env()
  |> do_render()
  |> should.equal([
    #(Ok("2"), "<Log(Integer, 2), ..1>"),
    #(Ok("(Integer) -> <Log(Integer, 2), ..1> 2"), "<>"),
    #(Ok("Integer"), "<>"),
  ])
}

// TODO perform should be closed

pub fn combine_effect_test() {
  "let x = perform Log(\"info\")
  perform Foo(5)"
  |> parse
  |> j.infer
  |> do_resolve()
  |> should.equal([
    #(Ok(j.Var(5)), j.Empty, []),
    #(Ok(j.Var(1)), j.EffectExtend("Log", #(j.String, j.Var(1)), j.Empty), []),
    #(
      Ok(j.Fun(
        j.String,
        j.EffectExtend("Log", #(j.String, j.Var(1)), j.Empty),
        j.Var(1),
      )),
      j.Empty,
      [],
    ),
    #(Ok(j.String), j.Empty, []),
    #(Ok(j.Var(5)), j.EffectExtend("Foo", #(j.Integer, j.Var(5)), j.Empty), [
      #("x", j.Var(#(True, 1))),
    ]),
    #(
      Ok(j.Fun(
        j.Integer,
        j.EffectExtend("Foo", #(j.Integer, j.Var(5)), j.Empty),
        j.Var(5),
      )),
      j.Empty,
      [#("x", j.Var(#(True, 1)))],
    ),
    #(Ok(j.Integer), j.Empty, [#("x", j.Var(#(True, 1)))]),
  ])
}

pub fn poly_in_effect_test() {
  "let do = (f) -> f(1)
  let _ = do((x) -> x)
  do((x) -> perform Foo(5))"
  |> parse
  |> j.infer
  |> do_resolve()
  |> drop_env()
  |> do_render()
  |> should.equal([
    #(Ok("9"), "<>"),
    #(Ok("((Integer) -> <..2> 1) -> <..2> 1"), "<>"),
    #(Ok("1"), "<..2>"),
    #(Ok("(Integer) -> <..2> 1"), "<>"),
    #(Ok("Integer"), "<>"),
    #(Ok("9"), "<>"),
    #(Ok("Integer"), "<>"),
    #(Ok("((Integer) -> <> Integer) -> <> Integer"), "<>"),
    #(Ok("(Integer) -> <> Integer"), "<>"),
    #(Ok("Integer"), "<>"),
    #(Ok("9"), "<Foo(Integer, 9)>"),
    #(Ok("((Integer) -> <Foo(Integer, 9)> 9) -> <Foo(Integer, 9)> 9"), "<>"),
    #(Ok("(Integer) -> <Foo(Integer, 9)> 9"), "<>"),
    #(Ok("9"), "<Foo(Integer, 9)>"),
    #(Ok("(Integer) -> <Foo(Integer, 9)> 9"), "<>"),
    #(Ok("Integer"), "<>"),
  ])
}

pub fn poly_in_effect_unification_test() {
  "(f) ->
    let _ = f(1)
    perform Log(\"\")"
  |> parse
  |> j.infer
  |> do_resolve()
  |> drop_env()
  |> do_render()
  |> should.equal([
    #(Ok("((Integer) -> <Log(String, 4)> 1) -> <Log(String, 4)> 4"), "<>"),
    #(Ok("4"), "<>"),
    #(Ok("1"), "<Log(String, 4)>"),
    #(Ok("(Integer) -> <Log(String, 4)> 1"), "<>"),
    #(Ok("Integer"), "<>"),
    #(Ok("4"), "<Log(String, 4)>"),
    #(Ok("(String) -> <Log(String, 4)> 4"), "<>"),
    #(Ok("String"), "<>"),
  ])
}
// let with two performs has a closed total effect
// f(5) Has total effect something that might depend on f

// Test if a sometihng accepting functions is passed in something pure

// let x = perform A({})
// perform B({})

// Using unhandled effects at the top for anything i.e. prompt breaks the idea of compiling in native effects

// function(_) {
//   perform A({}, j1)
// }
//
// function j1(x) {
//   perform B({})
// }
//
// pub fn simple_fn_test() {
//   "(x) -> x"
//   todo
// }

// pub fn assignment_test() {
//   "let f = (x) -> x
//   f(5)"
//   |> parse()
//   |> fast_j.infer()
// }
// pub fn assignment_test() {
//   "(f) ->
//     let x = f(5)
//     x
//   "
//   |> parse()
//   todo
// }

// TODO multi arity functions that dont raise effects
