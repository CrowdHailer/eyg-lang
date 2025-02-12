import eyg/runtime/break
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleam/javascript/promise
import gleeunit/should
import harness/effect
import harness/ffi/env
import harness/stdlib
import platforms/browser

pub fn variable_test() {
  let source = a.variable("x")

  let env = state.Env([#("x", v.String("assigned"))], dict.new(), dict.new())
  r.execute(source, env, dict.new())
  |> should.equal(Ok(v.String("assigned")))
}

pub fn function_test() {
  let body = a.variable("x")
  let source = a.lambda("x", body)

  let scope = [#("foo", v.String("assigned"))]
  let env = state.Env(scope, dict.new(), dict.new())
  r.execute(source, env, dict.new())
  |> should.equal(Ok(v.Closure("x", body, scope)))
}

pub fn function_application_test() {
  let source = a.apply(a.lambda("x", a.string("body")), a.integer(0))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("body")))

  let source =
    a.let_(
      "id",
      a.lambda("x", a.variable("x")),
      a.apply(a.variable("id"), a.integer(0)),
    )

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(0)))
}

pub fn function_variable_contain_test() {
  let source = a.apply(a.lambda("x", a.string("body")), a.variable("x"))

  r.execute(source, env.empty(), dict.new())
  |> should.be_error()
}

pub fn builtin_application_test() {
  let source = a.apply(a.builtin("string_uppercase"), a.string("hello"))

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.String("HELLO")))
}

// primitive
pub fn create_a_binary_test() {
  let source = a.string("hello")

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("hello")))
}

pub fn create_an_integer_test() {
  let source = a.integer(5)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(5)))
}

pub fn record_creation_test() {
  let source = a.empty()

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.unit))

  let source =
    a.apply(
      a.apply(a.extend("foo"), a.string("FOO")),
      a.apply(a.apply(a.extend("bar"), a.integer(0)), a.empty()),
    )

  r.execute(a.apply(a.select("foo"), source), env.empty(), dict.new())
  |> should.equal(Ok(v.String("FOO")))
  r.execute(a.apply(a.select("bar"), source), env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(0)))
}

pub fn case_test() {
  let switch =
    a.apply(
      a.apply(a.case_("Some"), a.lambda("x", a.variable("x"))),
      a.apply(
        a.apply(a.case_("None"), a.lambda("_", a.string("else"))),
        a.nocases(),
      ),
    )

  let source = a.apply(switch, a.apply(a.tag("Some"), a.string("foo")))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("foo")))

  let source = a.apply(switch, a.apply(a.tag("None"), a.empty()))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("else")))
}

pub fn rasing_effect_test() {
  let source =
    a.let_(
      "a",
      a.apply(a.perform("Foo"), a.integer(1)),
      a.apply(a.perform("Bar"), a.variable("a")),
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
    a.apply(
      a.apply(a.case_("Ok"), a.lambda("x", a.variable("x"))),
      a.apply(a.apply(a.case_("Error"), a.perform("Raise")), a.nocases()),
    )

  let source = a.apply(switch, a.apply(a.tag("Ok"), a.string("foo")))

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.String("foo")))

  let source = a.apply(switch, a.apply(a.tag("Error"), a.string("nope")))

  let assert Error(#(break.UnhandledEffect("Raise", lifted), _rev, _env, _k)) =
    r.execute(source, env.empty(), dict.new())
  lifted
  |> should.equal(v.String("nope"))
}

pub fn effect_in_builtin_test() {
  let list =
    a.apply(
      a.apply(a.cons(), a.string("fizz")),
      a.apply(a.apply(a.cons(), a.string("buzz")), a.tail()),
    )
  let reducer =
    a.lambda(
      "element",
      a.lambda(
        "state",
        a.let_(
          "reply",
          a.apply(a.perform("Foo"), a.variable("element")),
          a.apply(
            a.apply(a.builtin("string_append"), a.variable("state")),
            a.variable("element"),
          ),
        ),
      ),
    )
  let source =
    a.apply(
      a.apply(a.apply(a.builtin("list_fold"), list), a.string("initial")),
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
    a.lambda("x", a.lambda("k", a.apply(a.tag("Error"), a.variable("x"))))
  let exec = a.lambda("_", a.apply(a.tag("Ok"), a.string("mystring")))
  let source = a.apply(a.apply(a.handle("Throw"), handler), exec)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.String("mystring"))))
}

pub fn handle_early_return_effect_test() {
  let handler =
    a.lambda("x", a.lambda("k", a.apply(a.tag("Error"), a.variable("x"))))
  let exec = a.lambda("_", a.apply(a.perform("Throw"), a.string("Bad thing")))
  let source = a.apply(a.apply(a.handle("Throw"), handler), exec)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Tagged("Error", v.String("Bad thing"))))
}

pub fn handle_resume_test() {
  let handler =
    a.lambda(
      "x",
      a.lambda(
        "k",
        a.apply(
          a.apply(a.extend("value"), a.apply(a.variable("k"), a.empty())),
          a.apply(a.apply(a.extend("log"), a.variable("x")), a.empty()),
        ),
      ),
    )

  let exec =
    a.lambda(
      "_",
      a.let_(
        "_",
        a.apply(a.perform("Log"), a.string("my message")),
        a.integer(100),
      ),
    )
  let source = a.apply(a.apply(a.handle("Log"), handler), exec)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(
    Ok(v.Record([#("log", v.String("my message")), #("value", v.Integer(100))])),
  )
}

pub fn ignore_other_effect_test() {
  let handler =
    a.lambda("x", a.lambda("k", a.apply(a.tag("Error"), a.variable("x"))))
  let exec =
    a.lambda(
      "_",
      a.apply(
        a.apply(a.extend("foo"), a.apply(a.perform("Foo"), a.empty())),
        a.empty(),
      ),
    )
  let source = a.apply(a.apply(a.handle("Throw"), handler), exec)

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
    a.apply(
      a.apply(a.extend("a"), a.apply(a.perform("Choose"), a.unit())),
      a.apply(
        a.apply(a.extend("b"), a.apply(a.perform("Choose"), a.unit())),
        a.empty(),
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
    a.lambda(
      "_",
      a.apply(
        a.apply(a.extend("a"), a.apply(a.perform("Choose"), a.unit())),
        a.apply(
          a.apply(a.extend("b"), a.apply(a.perform("Choose"), a.unit())),
          a.empty(),
        ),
      ),
    )
  let handle =
    a.apply(
      a.handle("Choose"),
      a.lambda(
        "_",
        a.lambda(
          "k",
          a.apply(
            a.apply(a.extend("first"), a.apply(a.variable("k"), a.true())),
            a.apply(
              a.apply(a.extend("second"), a.apply(a.variable("k"), a.false())),
              a.empty(),
            ),
          ),
        ),
      ),
    )
  let source = a.apply(handle, raise)

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
    a.apply(
      a.handle("Log"),
      a.lambda("lift", a.lambda("k", a.string("Caught"))),
    )
  let source =
    a.let_(
      "_",
      a.apply(handler, a.lambda("_", a.string("Original"))),
      a.apply(a.perform("Log"), a.string("outer")),
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
    a.apply(a.handle("Fail"), a.lambda("lift", a.lambda("k", a.integer(-1))))
  let exec =
    a.lambda(
      "_",
      a.let_(
        "_",
        a.apply(a.perform("Log"), a.string("my log")),
        a.let_(
          "_",
          a.apply(a.perform("Fail"), a.string("some error")),
          a.string("done"),
        ),
      ),
    )

  let source = a.apply(handler, exec)

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
    a.lambda("_", a.apply(a.perform("Async"), a.lambda("_", a.string("later"))))
  let source = a.apply(f, a.unit())

  let assert Ok(v.Promise(p)) = r.execute(source, stdlib.env(), handlers().1)
  use value <- promise.map(p)
  value
  |> should.equal(v.String("later"))
}
