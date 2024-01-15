import gleam/dict
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
  r.eval(
    source,
    r.Env([#("x", r.Str("assigned"))], dict.new()),
    r.WillRenameAsDone(dict.new()),
  )
  |> should.equal(r.Value(r.Str("assigned")))
}

pub fn function_test() {
  let body = e.Variable("x")
  let source = e.Lambda("x", body)
  let scope = [#("foo", r.Str("assigned"))]
  let env = r.Env(scope, dict.new())
  r.eval(source, env, r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Function("x", body, scope, [])))
}

pub fn function_application_test() {
  let source = e.Apply(e.Lambda("x", e.Str("body")), e.Integer(0))
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Str("body")))

  let source =
    e.Let(
      "id",
      e.Lambda("x", e.Variable("x")),
      e.Apply(e.Variable("id"), e.Integer(0)),
    )
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Integer(0)))
}

pub fn builtin_application_test() {
  let source = e.Apply(e.Builtin("string_uppercase"), e.Str("hello"))

  r.eval(source, stdlib.env(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Str("HELLO")))
}

// primitive
pub fn create_a_binary_test() {
  let source = e.Str("hello")
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Str("hello")))
}

pub fn create_an_integer_test() {
  let source = e.Integer(5)
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Integer(5)))
}

pub fn record_creation_test() {
  let source = e.Empty
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Record([])))

  let source =
    e.Apply(
      e.Apply(e.Extend("foo"), e.Str("FOO")),
      e.Apply(e.Apply(e.Extend("bar"), e.Integer(0)), e.Empty),
    )
  r.eval(
    e.Apply(e.Select("foo"), source),
    env.empty(),
    r.WillRenameAsDone(dict.new()),
  )
  |> should.equal(r.Value(r.Str("FOO")))
  r.eval(
    e.Apply(e.Select("bar"), source),
    env.empty(),
    r.WillRenameAsDone(dict.new()),
  )
  |> should.equal(r.Value(r.Integer(0)))
}

pub fn case_test() {
  let switch =
    e.Apply(
      e.Apply(e.Case("Some"), e.Lambda("x", e.Variable("x"))),
      e.Apply(e.Apply(e.Case("None"), e.Lambda("_", e.Str("else"))), e.NoCases),
    )

  let source = e.Apply(switch, e.Apply(e.Tag("Some"), e.Str("foo")))
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Str("foo")))

  let source = e.Apply(switch, e.Apply(e.Tag("None"), e.Empty))
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Str("else")))
}

pub fn rasing_effect_test() {
  let source =
    e.Let(
      "a",
      e.Apply(e.Perform("Foo"), e.Integer(1)),
      e.Apply(e.Perform("Bar"), e.Variable("a")),
    )
  let assert r.Effect("Foo", lifted, rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  lifted
  |> should.equal(r.Integer(1))
  let assert r.Effect("Bar", lifted, rev, env, k) =
    r.loop(r.V(r.Value(r.Str("reply"))), rev, env, k)
  lifted
  |> should.equal(r.Str("reply"))
  let assert r.Value(term) = r.loop(r.V(r.Value(r.Record([]))), rev, env, k)
  term
  |> should.equal(r.Record([]))
}

pub fn effect_in_case_test() {
  let switch =
    e.Apply(
      e.Apply(e.Case("Ok"), e.Lambda("x", e.Variable("x"))),
      e.Apply(e.Apply(e.Case("Error"), e.Perform("Raise")), e.NoCases),
    )

  let source = e.Apply(switch, e.Apply(e.Tag("Ok"), e.Str("foo")))
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Str("foo")))

  let source = e.Apply(switch, e.Apply(e.Tag("Error"), e.Str("nope")))
  let assert r.Effect("Raise", lifted, _rev, _env, _k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  lifted
  |> should.equal(r.Str("nope"))
}

pub fn effect_in_builtin_test() {
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Str("fizz")),
      e.Apply(e.Apply(e.Cons, e.Str("buzz")), e.Tail),
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
      e.Apply(e.Apply(e.Builtin("list_fold"), list), e.Str("initial")),
      reducer,
    )
  let assert r.Effect("Foo", lifted, rev, env, k) =
    r.eval(source, stdlib.env(), r.WillRenameAsDone(dict.new()))
  lifted
  |> should.equal(r.Str("fizz"))
  let assert r.Effect("Foo", lifted, rev, env, k) =
    r.loop(r.V(r.Value(r.unit)), rev, env, k)
  lifted
  |> should.equal(r.Str("buzz"))
  r.loop(r.V(r.Value(r.unit)), rev, env, k)
  |> should.equal(r.Value(r.Str("initialfizzbuzz")))
}

pub fn handler_no_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Str("mystring")))
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Tagged("Ok", r.Str("mystring"))))

  // shallow
  let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)

  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Tagged("Ok", r.Str("mystring"))))
}

pub fn handle_early_return_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec = e.Lambda("_", e.Apply(e.Perform("Throw"), e.Str("Bad thing")))
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Tagged("Error", r.Str("Bad thing"))))

  let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)

  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Tagged("Error", r.Str("Bad thing"))))
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
      e.Let("_", e.Apply(e.Perform("Log"), e.Str("my message")), e.Integer(100)),
    )
  let source = e.Apply(e.Apply(e.Handle("Log"), handler), exec)

  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(
    r.Value(
      r.Record([#("value", r.Integer(100)), #("log", r.Str("my message"))]),
    ),
  )

  let source = e.Apply(e.Apply(e.Shallow("Log"), handler), exec)

  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  |> should.equal(
    r.Value(
      r.Record([#("value", r.Integer(100)), #("log", r.Str("my message"))]),
    ),
  )
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

  let assert r.Effect("Foo", lifted, rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  lifted
  |> should.equal(r.Record([]))
  // calling k should fall throu
  // Should test wrapping binary here to check K works properly
  r.loop(r.V(r.Value(r.Str("reply"))), rev, env, k)
  |> should.equal(r.Value(r.Record([#("foo", r.Str("reply"))])))

  // SHALLOW
  let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)

  let assert r.Effect("Foo", lifted, rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  lifted
  |> should.equal(r.Record([]))
  // calling k should fall throu
  // Should test wrapping binary here to check K works properly
  r.loop(r.V(r.Value(r.Str("reply"))), rev, env, k)
  |> should.equal(r.Value(r.Record([#("foo", r.Str("reply"))])))
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

  let assert r.Effect("Choose", lifted, rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  lifted
  |> should.equal(r.Record([]))

  let assert r.Effect("Choose", lifted, rev, env, k) =
    r.loop(r.V(r.Value(r.Str("True"))), rev, env, k)
  lifted
  |> should.equal(r.Record([]))

  r.loop(r.V(r.Value(r.Str("False"))), rev, env, k)
  |> should.equal(
    r.Value(r.Record([#("a", r.Str("True")), #("b", r.Str("False"))])),
  )
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
  r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  // Not sure this is the correct value but it checks regressions
  |> should.equal(
    r.Value(
      term: r.Record(fields: [
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
      ]),
    ),
  )
}

pub fn handler_doesnt_continue_to_effect_then_in_let_test() {
  let handler =
    e.Apply(e.Handle("Log"), e.Lambda("lift", e.Lambda("k", e.Str("Caught"))))
  let source =
    e.Let(
      "_",
      e.Apply(handler, e.Lambda("_", e.Str("Original"))),
      e.Apply(e.Perform("Log"), e.Str("outer")),
    )
  let assert r.Effect("Log", r.Str("outer"), rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  r.loop(r.V(r.Value(r.Record([]))), rev, env, k)
  |> should.equal(r.Value(r.Record([])))

  let handler =
    e.Apply(e.Shallow("Log"), e.Lambda("lift", e.Lambda("k", e.Str("Caught"))))
  let source =
    e.Let(
      "_",
      e.Apply(handler, e.Lambda("_", e.Str("Original"))),
      e.Apply(e.Perform("Log"), e.Str("outer")),
    )
  let assert r.Effect("Log", r.Str("outer"), rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))
  r.loop(r.V(r.Value(r.Record([]))), rev, env, k)
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
        e.Apply(e.Perform("Log"), e.Str("my log")),
        e.Let(
          "_",
          e.Apply(e.Perform("Fail"), e.Str("some error")),
          e.Str("done"),
        ),
      ),
    )

  let source = e.Apply(handler, exec)
  let assert r.Effect("Log", r.Str("my log"), rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))

  r.loop(r.V(r.Value(r.Record([]))), rev, env, k)
  |> should.equal(r.Value(r.Integer(-1)))

  let handler =
    e.Apply(e.Shallow("Fail"), e.Lambda("lift", e.Lambda("k", e.Integer(-1))))
  let exec =
    e.Lambda(
      "_",
      e.Let(
        "_",
        e.Apply(e.Perform("Log"), e.Str("my log")),
        e.Let(
          "_",
          e.Apply(e.Perform("Fail"), e.Str("some error")),
          e.Str("done"),
        ),
      ),
    )

  let source = e.Apply(handler, exec)
  let assert r.Effect("Log", r.Str("my log"), rev, env, k) =
    r.eval(source, env.empty(), r.WillRenameAsDone(dict.new()))

  r.loop(r.V(r.Value(r.Record([]))), rev, env, k)
  |> should.equal(r.Value(r.Integer(-1)))
}

// async/task

fn handlers() {
  effect.init()
  |> effect.extend("Async", browser.async())
}

pub fn async_test() {
  let source =
    e.Lambda("_", e.Apply(e.Perform("Async"), e.Lambda("_", e.Str("later"))))
  let assert Ok(r.Promise(p)) =
    r.run(source, stdlib.env(), r.unit, handlers().1)
  use value <- promise.map(p)
  value
  |> should.equal(r.Str("later"))
}
