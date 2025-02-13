import eyg/ir/tree as ir
import eyg/runtime/break
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import gleam/dict
import gleam/javascript/promise
import gleeunit/should
import harness/effect
import harness/ffi/env
import harness/stdlib
import platforms/browser

pub fn variable_test() {
  let source = ir.variable("x")

  let env = state.Env([#("x", v.String("assigned"))], dict.new(), dict.new())
  r.execute(source, env, dict.new())
  |> should.equal(Ok(v.String("assigned")))
}

pub fn function_test() {
  let body = ir.variable("x")
  let source = ir.lambda("x", body)

  let scope = [#("foo", v.String("assigned"))]
  let env = state.Env(scope, dict.new(), dict.new())
  r.execute(source, env, dict.new())
  |> should.equal(Ok(v.Closure("x", body, scope)))
}

pub fn function_application_test() {
  let source = ir.apply(ir.lambda("x", ir.string("body")), ir.integer(0))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("body")))

  let source =
    ir.let_(
      "id",
      ir.lambda("x", ir.variable("x")),
      ir.apply(ir.variable("id"), ir.integer(0)),
    )

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(0)))
}

pub fn function_variable_contain_test() {
  let source = ir.apply(ir.lambda("x", ir.string("body")), ir.variable("x"))

  r.execute(source, env.empty(), dict.new())
  |> should.be_error()
}

pub fn builtin_application_test() {
  let source = ir.apply(ir.builtin("string_uppercase"), ir.string("hello"))

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.String("HELLO")))
}

// primitive
pub fn create_a_binary_test() {
  let source = ir.string("hello")

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("hello")))
}

pub fn create_an_integer_test() {
  let source = ir.integer(5)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(5)))
}

pub fn record_creation_test() {
  let source = ir.empty()

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.unit))

  let source =
    ir.apply(
      ir.apply(ir.extend("foo"), ir.string("FOO")),
      ir.apply(ir.apply(ir.extend("bar"), ir.integer(0)), ir.empty()),
    )

  r.execute(ir.apply(ir.select("foo"), source), env.empty(), dict.new())
  |> should.equal(Ok(v.String("FOO")))
  r.execute(ir.apply(ir.select("bar"), source), env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(0)))
}

pub fn case_test() {
  let switch =
    ir.apply(
      ir.apply(ir.case_("Some"), ir.lambda("x", ir.variable("x"))),
      ir.apply(
        ir.apply(ir.case_("None"), ir.lambda("_", ir.string("else"))),
        ir.nocases(),
      ),
    )

  let source = ir.apply(switch, ir.apply(ir.tag("Some"), ir.string("foo")))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("foo")))

  let source = ir.apply(switch, ir.apply(ir.tag("None"), ir.empty()))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("else")))
}

pub fn rasing_effect_test() {
  let source =
    ir.let_(
      "a",
      ir.apply(ir.perform("Foo"), ir.integer(1)),
      ir.apply(ir.perform("Bar"), ir.variable("a")),
    )

  let assert Error(#(break.UnhandledEffect("Foo", lifted), Nil, env, k)) =
    r.execute(source, env.empty(), dict.new())
  lifted
  |> should.equal(v.Integer(1))
  let assert Error(#(break.UnhandledEffect("Bar", lifted), Nil, env, k)) =
    r.loop(state.step(state.V(v.String("reply")), env, k))
  lifted
  |> should.equal(v.String("reply"))
  let assert Ok(term) = r.loop(state.step(state.V(v.unit), env, k))
  term
  |> should.equal(v.unit)
}

pub fn effect_in_case_test() {
  let switch =
    ir.apply(
      ir.apply(ir.case_("Ok"), ir.lambda("x", ir.variable("x"))),
      ir.apply(ir.apply(ir.case_("Error"), ir.perform("Raise")), ir.nocases()),
    )

  let source = ir.apply(switch, ir.apply(ir.tag("Ok"), ir.string("foo")))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("foo")))

  let source = ir.apply(switch, ir.apply(ir.tag("Error"), ir.string("nope")))

  let assert Error(#(break.UnhandledEffect("Raise", lifted), _rev, _env, _k)) =
    r.execute(source, env.empty(), dict.new())
  lifted
  |> should.equal(v.String("nope"))
}

pub fn effect_in_builtin_test() {
  let list =
    ir.apply(
      ir.apply(ir.cons(), ir.string("fizz")),
      ir.apply(ir.apply(ir.cons(), ir.string("buzz")), ir.tail()),
    )
  let reducer =
    ir.lambda(
      "element",
      ir.lambda(
        "state",
        ir.let_(
          "reply",
          ir.apply(ir.perform("Foo"), ir.variable("element")),
          ir.apply(
            ir.apply(ir.builtin("string_append"), ir.variable("state")),
            ir.variable("element"),
          ),
        ),
      ),
    )
  let source =
    ir.apply(
      ir.apply(ir.apply(ir.builtin("list_fold"), list), ir.string("initial")),
      reducer,
    )

  let assert Error(#(break.UnhandledEffect("Foo", lifted), Nil, env, k)) =
    r.execute(source, stdlib.env(), dict.new())
  lifted
  |> should.equal(v.String("fizz"))
  let assert Error(#(break.UnhandledEffect("Foo", lifted), Nil, env, k)) =
    r.loop(state.step(state.V(v.unit), env, k))
  lifted
  |> should.equal(v.String("buzz"))
  r.loop(state.step(state.V(v.unit), env, k))
  |> should.equal(Ok(v.String("initialfizzbuzz")))
}

pub fn handler_no_effect_test() {
  let handler =
    ir.lambda("x", ir.lambda("k", ir.apply(ir.tag("Error"), ir.variable("x"))))
  let exec = ir.lambda("_", ir.apply(ir.tag("Ok"), ir.string("mystring")))
  let source = ir.apply(ir.apply(ir.handle("Throw"), handler), exec)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.String("mystring"))))
}

pub fn handle_early_return_effect_test() {
  let handler =
    ir.lambda("x", ir.lambda("k", ir.apply(ir.tag("Error"), ir.variable("x"))))
  let exec =
    ir.lambda("_", ir.apply(ir.perform("Throw"), ir.string("Bad thing")))
  let source = ir.apply(ir.apply(ir.handle("Throw"), handler), exec)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Tagged("Error", v.String("Bad thing"))))
}

pub fn handle_resume_test() {
  let handler =
    ir.lambda(
      "x",
      ir.lambda(
        "k",
        ir.apply(
          ir.apply(ir.extend("value"), ir.apply(ir.variable("k"), ir.empty())),
          ir.apply(ir.apply(ir.extend("log"), ir.variable("x")), ir.empty()),
        ),
      ),
    )

  let exec =
    ir.lambda(
      "_",
      ir.let_(
        "_",
        ir.apply(ir.perform("Log"), ir.string("my message")),
        ir.integer(100),
      ),
    )
  let source = ir.apply(ir.apply(ir.handle("Log"), handler), exec)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(
    Ok(v.Record([#("log", v.String("my message")), #("value", v.Integer(100))])),
  )
}

pub fn ignore_other_effect_test() {
  let handler =
    ir.lambda("x", ir.lambda("k", ir.apply(ir.tag("Error"), ir.variable("x"))))
  let exec =
    ir.lambda(
      "_",
      ir.apply(
        ir.apply(ir.extend("foo"), ir.apply(ir.perform("Foo"), ir.empty())),
        ir.empty(),
      ),
    )
  let source = ir.apply(ir.apply(ir.handle("Throw"), handler), exec)

  let assert Error(#(break.UnhandledEffect("Foo", lifted), Nil, env, k)) =
    r.execute(source, env.empty(), dict.new())
  lifted
  |> should.equal(v.unit)
  // calling k should fall throu
  // Should test wrapping binary here to check K works properly
  r.loop(state.step(state.V(v.String("reply")), env, k))
  |> should.equal(Ok(v.Record([#("foo", v.String("reply"))])))
}

pub fn multiple_effects_test() {
  let source =
    ir.apply(
      ir.apply(ir.extend("a"), ir.apply(ir.perform("Choose"), ir.unit())),
      ir.apply(
        ir.apply(ir.extend("b"), ir.apply(ir.perform("Choose"), ir.unit())),
        ir.empty(),
      ),
    )

  let assert Error(#(break.UnhandledEffect("Choose", lifted), Nil, env, k)) =
    r.execute(source, env.empty(), dict.new())
  lifted
  |> should.equal(v.unit)

  let assert Error(#(break.UnhandledEffect("Choose", lifted), Nil, env, k)) =
    r.loop(state.step(state.V(v.String("True")), env, k))
  lifted
  |> should.equal(v.unit)

  r.loop(state.step(state.V(v.String("False")), env, k))
  |> should.equal(
    Ok(v.Record([#("a", v.String("True")), #("b", v.String("False"))])),
  )
}

pub fn multiple_resumptions_test() {
  let raise =
    ir.lambda(
      "_",
      ir.apply(
        ir.apply(ir.extend("a"), ir.apply(ir.perform("Choose"), ir.unit())),
        ir.apply(
          ir.apply(ir.extend("b"), ir.apply(ir.perform("Choose"), ir.unit())),
          ir.empty(),
        ),
      ),
    )
  let handle =
    ir.apply(
      ir.handle("Choose"),
      ir.lambda(
        "_",
        ir.lambda(
          "k",
          ir.apply(
            ir.apply(ir.extend("first"), ir.apply(ir.variable("k"), ir.true())),
            ir.apply(
              ir.apply(
                ir.extend("second"),
                ir.apply(ir.variable("k"), ir.false()),
              ),
              ir.empty(),
            ),
          ),
        ),
      ),
    )
  let source = ir.apply(handle, raise)

  r.execute(source, env.empty(), dict.new())
  // Not sure this is the correct value but it checks regressions
  |> should.equal(
    Ok(
      v.Record(fields: [
        #(
          "first",
          v.Record([
            #(
              "first",
              v.Record([
                #("a", v.Tagged("True", v.unit)),
                #("b", v.Tagged("True", v.unit)),
              ]),
            ),
            #(
              "second",
              v.Record([
                #("a", v.Tagged("True", v.unit)),
                #("b", v.Tagged("False", v.unit)),
              ]),
            ),
          ]),
        ),
        #(
          "second",
          v.Record([
            #(
              "first",
              v.Record([
                #("a", v.Tagged("False", v.unit)),
                #("b", v.Tagged("True", v.unit)),
              ]),
            ),
            #(
              "second",
              v.Record([
                #("a", v.Tagged("False", v.unit)),
                #("b", v.Tagged("False", v.unit)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  )
}

pub fn handler_doesnt_continue_to_effect_then_in_let_test() {
  let handler =
    ir.apply(
      ir.handle("Log"),
      ir.lambda("lift", ir.lambda("k", ir.string("Caught"))),
    )
  let source =
    ir.let_(
      "_",
      ir.apply(handler, ir.lambda("_", ir.string("Original"))),
      ir.apply(ir.perform("Log"), ir.string("outer")),
    )

  let assert Error(#(
    break.UnhandledEffect("Log", v.String("outer")),
    Nil,
    env,
    k,
  )) = r.execute(source, env.empty(), dict.new())
  r.loop(state.step(state.V(v.unit), env, k))
  |> should.equal(Ok(v.unit))
}

pub fn handler_is_applied_after_other_effects_test() {
  let handler =
    ir.apply(
      ir.handle("Fail"),
      ir.lambda("lift", ir.lambda("k", ir.integer(-1))),
    )
  let exec =
    ir.lambda(
      "_",
      ir.let_(
        "_",
        ir.apply(ir.perform("Log"), ir.string("my log")),
        ir.let_(
          "_",
          ir.apply(ir.perform("Fail"), ir.string("some error")),
          ir.string("done"),
        ),
      ),
    )

  let source = ir.apply(handler, exec)

  let assert Error(#(
    break.UnhandledEffect("Log", v.String("my log")),
    Nil,
    env,
    k,
  )) = r.execute(source, env.empty(), dict.new())

  r.loop(state.step(state.V(v.unit), env, k))
  |> should.equal(Ok(v.Integer(-1)))
}

// async/task

fn handlers() {
  effect.init()
  |> effect.extend("Async", browser.async())
}

pub fn async_test() {
  let f =
    ir.lambda(
      "_",
      ir.apply(ir.perform("Async"), ir.lambda("_", ir.string("later"))),
    )
  let source = ir.apply(f, ir.unit())

  let assert Ok(v.Promise(p)) = r.execute(source, stdlib.env(), handlers().1)
  use value <- promise.map(p)
  value
  |> should.equal(v.String("later"))
}
