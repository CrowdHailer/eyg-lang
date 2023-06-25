import gleam/map
import gleam/javascript/promise
import gleeunit/should
import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/ffi/env
import harness/effect
import harness/stdlib
import platforms/browser

pub fn variable_test() {
  let source = e.Variable("x")
  r.eval(source, r.Env([#("x", r.Binary("assigned"))], map.new()), r.Value)
  |> should.equal(r.Value(r.Binary("assigned")))
}

pub fn function_test() {
  let body = e.Variable("x")
  let source = e.Lambda("x", body)
  let scope = [#("foo", r.Binary("assigned"))]
  let env = r.Env(scope, map.new())
  r.eval(source, env, r.Value)
  |> should.equal(r.Value(r.Function("x", body, scope)))
}

pub fn function_application_test() {
  let source = e.Apply(e.Lambda("x", e.Binary("body")), e.Integer(0))
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Binary("body")))

  let source =
    e.Let(
      "id",
      e.Lambda("x", e.Variable("x")),
      e.Apply(e.Variable("id"), e.Integer(0)),
    )
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Integer(0)))
}

pub fn builtin_application_test() {
  let source = e.Apply(e.Builtin("string_uppercase"), e.Binary("hello"))

  r.eval(source, stdlib.env(), r.Value)
  |> should.equal(r.Value(r.Binary("HELLO")))
}

// primitive
pub fn create_a_binary_test() {
  let source = e.Binary("hello")
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Binary("hello")))
}

pub fn create_an_integer_test() {
  let source = e.Integer(5)
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Integer(5)))
}

pub fn record_creation_test() {
  let source = e.Empty
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Record([])))

  let source =
    e.Apply(
      e.Apply(e.Extend("foo"), e.Binary("FOO")),
      e.Apply(e.Apply(e.Extend("bar"), e.Integer(0)), e.Empty),
    )
  r.eval(e.Apply(e.Select("foo"), source), env.empty(), r.Value)
  |> should.equal(r.Value(r.Binary("FOO")))
  r.eval(e.Apply(e.Select("bar"), source), env.empty(), r.Value)
  |> should.equal(r.Value(r.Integer(0)))
}

pub fn case_test() {
  let switch =
    e.Apply(
      e.Apply(e.Case("Some"), e.Lambda("x", e.Variable("x"))),
      e.Apply(
        e.Apply(e.Case("None"), e.Lambda("_", e.Binary("else"))),
        e.NoCases,
      ),
    )

  let source = e.Apply(switch, e.Apply(e.Tag("Some"), e.Binary("foo")))
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Binary("foo")))

  let source = e.Apply(switch, e.Apply(e.Tag("None"), e.Empty))
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Binary("else")))
}

pub fn rasing_effect_test() {
  let source =
    e.Let(
      "a",
      e.Apply(e.Perform("Foo"), e.Integer(1)),
      e.Apply(e.Perform("Bar"), e.Variable("a")),
    )
  let assert r.Effect("Foo", lifted, k) = r.eval(source, env.empty(), r.Value)
  lifted
  |> should.equal(r.Integer(1))
  let assert r.Effect("Bar", lifted, k) = r.loop(k(r.Binary("reply")))
  lifted
  |> should.equal(r.Binary("reply"))
  let assert r.Value(term) = r.loop(k(r.Record([])))
  term
  |> should.equal(r.Record([]))
}

pub fn effect_in_case_test() {
  let switch =
    e.Apply(
      e.Apply(e.Case("Ok"), e.Lambda("x", e.Variable("x"))),
      e.Apply(e.Apply(e.Case("Error"), e.Perform("Raise")), e.NoCases),
    )

  let source = e.Apply(switch, e.Apply(e.Tag("Ok"), e.Binary("foo")))
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Binary("foo")))

  let source = e.Apply(switch, e.Apply(e.Tag("Error"), e.Binary("nope")))
  let assert r.Effect("Raise", lifted, _k) =
    r.eval(source, env.empty(), r.Value)
  lifted
  |> should.equal(r.Binary("nope"))
}

pub fn effect_in_builtin_test() {
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Binary("fizz")),
      e.Apply(e.Apply(e.Cons, e.Binary("buzz")), e.Tail),
    )
  let reducer =
    e.Lambda(
      "element",
      e.Lambda(
        "state",
        e.Let(
          "reply",
          e.Apply(e.Perform("Foo"), e.Variable("element")),
          e.Apply(
            e.Apply(e.Builtin("string_append"), e.Variable("state")),
            e.Variable("element"),
          ),
        ),
      ),
    )
  let source =
    e.Apply(
      e.Apply(e.Apply(e.Builtin("list_fold"), list), e.Binary("initial")),
      reducer,
    )
  let assert r.Effect("Foo", lifted, k) = r.eval(source, stdlib.env(), r.Value)
  lifted
  |> should.equal(r.Binary("fizz"))
  let assert r.Effect("Foo", lifted, k) = r.loop(k(r.unit))
  lifted
  |> should.equal(r.Binary("buzz"))
  k(r.unit)
  |> r.loop()
  |> should.equal(r.Value(r.Binary("initialfizzbuzz")))
}

pub fn handler_no_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Binary("mystring")))
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Tagged("Ok", r.Binary("mystring"))))

  let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)
  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Tagged("Ok", r.Binary("mystring"))))
}

pub fn handle_early_return_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec = e.Lambda("_", e.Apply(e.Perform("Throw"), e.Binary("Bad thing")))
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Tagged("Error", r.Binary("Bad thing"))))
}

pub fn handle_resume_test() {
  let handler =
    e.Lambda(
      "x",
      e.Lambda(
        "k",
        e.Apply(
          e.Apply(e.Extend("value"), e.Apply(e.Variable("k"), e.Empty)),
          e.Apply(e.Apply(e.Extend("log"), e.Variable("x")), e.Empty),
        ),
      ),
    )

  let exec =
    e.Lambda(
      "_",
      e.Let(
        "_",
        e.Apply(e.Perform("Log"), e.Binary("my message")),
        e.Integer(100),
      ),
    )
  let source = e.Apply(e.Apply(e.Handle("Log"), handler), exec)

  r.eval(source, env.empty(), r.Value)
  |> should.equal(r.Value(r.Record([
    #("value", r.Integer(100)),
    #("log", r.Binary("my message")),
  ])))
}

pub fn ignore_other_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec =
    e.Lambda(
      "_",
      e.Apply(
        e.Apply(e.Extend("foo"), e.Apply(e.Perform("Foo"), e.Empty)),
        e.Empty,
      ),
    )
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  let assert r.Effect("Foo", lifted, k) = r.eval(source, env.empty(), r.Value)
  lifted
  |> should.equal(r.Record([]))
  // calling k should fall throu
  // Should test wrapping binary here to check K works properly
  k(r.Binary("reply"))
  |> r.loop
  |> should.equal(r.Value(r.Record([#("foo", r.Binary("reply"))])))
}

pub fn multiple_effects_test() {
  let source =
    e.Apply(
      e.Apply(e.Extend("a"), e.Apply(e.Perform("Choose"), e.unit)),
      e.Apply(
        e.Apply(e.Extend("b"), e.Apply(e.Perform("Choose"), e.unit)),
        e.Empty,
      ),
    )

  let assert r.Effect("Choose", lifted, k) =
    r.eval(source, env.empty(), r.Value)
  lifted
  |> should.equal(r.Record([]))

  let assert r.Effect("Choose", lifted, k) = r.loop(k(r.Binary("True")))
  lifted
  |> should.equal(r.Record([]))

  k(r.Binary("False"))
  |> r.loop
  |> should.equal(r.Value(r.Record([
    #("a", r.Binary("True")),
    #("b", r.Binary("False")),
  ])))
}

pub fn multiple_resumptions_test() {
  let raise =
    e.Lambda(
      "_",
      e.Apply(
        e.Apply(e.Extend("a"), e.Apply(e.Perform("Choose"), e.unit)),
        e.Apply(
          e.Apply(e.Extend("b"), e.Apply(e.Perform("Choose"), e.unit)),
          e.Empty,
        ),
      ),
    )
  let handle =
    e.Apply(
      e.Handle("Choose"),
      e.Lambda(
        "_",
        e.Lambda(
          "k",
          e.Apply(
            e.Apply(e.Extend("first"), e.Apply(e.Variable("k"), e.true)),
            e.Apply(
              e.Apply(e.Extend("second"), e.Apply(e.Variable("k"), e.false)),
              e.Empty,
            ),
          ),
        ),
      ),
    )
  let source = e.Apply(handle, raise)
  r.eval(source, env.empty(), r.Value)
  // Not sure this is the correct value but it checks regressions
  |> should.equal(r.Value(term: r.Record(fields: [
    #(
      "first",
      r.Record([
        #(
          "first",
          r.Record([
            #("a", r.Tagged("True", r.Record([]))),
            #("b", r.Tagged("True", r.Record([]))),
          ]),
        ),
        #(
          "second",
          r.Record([
            #("a", r.Tagged("True", r.Record([]))),
            #("b", r.Tagged("False", r.Record([]))),
          ]),
        ),
      ]),
    ),
    #(
      "second",
      r.Record([
        #(
          "first",
          r.Record([
            #("a", r.Tagged("False", r.Record([]))),
            #("b", r.Tagged("True", r.Record([]))),
          ]),
        ),
        #(
          "second",
          r.Record([
            #("a", r.Tagged("False", r.Record([]))),
            #("b", r.Tagged("False", r.Record([]))),
          ]),
        ),
      ]),
    ),
  ])))
}

pub fn handler_doesnt_continue_test() {
  let handler =
    e.Apply(
      e.Handle("Log"),
      e.Lambda("lift", e.Lambda("k", e.Binary("Caught"))),
    )
  let source =
    e.Let(
      "_",
      e.Apply(handler, e.Lambda("_", e.Binary("Original"))),
      e.Apply(e.Perform("Log"), e.Binary("outer")),
    )
  let assert r.Effect("Log", r.Binary("outer"), k) =
    r.eval(source, env.empty(), r.Value)
  k(r.Record([]))
  |> should.equal(r.Value(r.Record([])))
}

pub fn handler_is_applied_after_other_effects_test() {
  let handler =
    e.Apply(e.Handle("Fail"), e.Lambda("lift", e.Lambda("k", e.Integer(-1))))
  let exec =
    e.Lambda(
      "_",
      e.Let(
        "_",
        e.Apply(e.Perform("Log"), e.Binary("my log")),
        e.Let(
          "_",
          e.Apply(e.Perform("Fail"), e.Binary("some error")),
          e.Binary("done"),
        ),
      ),
    )

  let source = e.Apply(handler, exec)
  let assert r.Effect("Log", r.Binary("my log"), k) =
    r.eval(source, env.empty(), r.Value)

  k(r.Record([]))
  |> r.loop
  |> should.equal(r.Value(r.Integer(-1)))
}

// async/task

fn handlers() {
  effect.init()
  |> effect.extend("Async", browser.async())
}

pub fn async_test() {
  let source =
    e.Lambda("_", e.Apply(e.Perform("Async"), e.Lambda("_", e.Binary("later"))))
  let assert Ok(r.Promise(p)) =
    r.run(source, stdlib.env(), r.unit, handlers().1)
  use value <- promise.map(p)
  value
  |> should.equal(r.Binary("later"))
}
