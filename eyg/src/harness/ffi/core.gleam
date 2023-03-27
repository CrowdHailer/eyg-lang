import gleam/io
import gleam/map
import eygir/expression as e
import eyg/analysis/typ as t
import eygir/encode
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import gleam/javascript/promise
import harness/ffi/cast
import plinth/browser/window

pub fn equal() {
  let type_ =
    t.Fun(t.Unbound(0), t.Open(1), t.Fun(t.Unbound(0), t.Open(2), t.boolean))
  #(type_, r.Arity2(do_equal))
}

fn do_equal(left, right, _builtins, k) {
  case left == right {
    True -> r.true
    False -> r.false
  }
  |> r.continue(k, _)
}

pub fn debug() {
  let type_ = t.Fun(t.Unbound(0), t.Open(1), t.Binary)
  #(type_, r.Arity1(do_debug))
}

fn do_debug(term, _builtins, k) {
  r.continue(k, r.Binary(r.to_string(term)))
}

pub fn fix() {
  let type_ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )
  #(type_, r.Arity1(do_fix))
}

fn do_fix(builder, builtins, k) {
  r.eval_call(builder, r.Defunc(r.Builtin("fixed", [builder])), builtins, k)
}

pub fn fixed() {
  // I'm not sure a type ever means anything here
  // fixed is not a function you can reference directly it's just a runtime
  // value produced by the fix action
  #(
    t.Unbound(0),
    r.Arity2(fn(builder, arg, builtins, k) {
      r.eval_call(
        builder,
        r.Defunc(r.Builtin("fixed", [builder])),
        builtins,
        r.eval_call(_, arg, builtins, k),
      )
    }),
  )
}

// This should be replaced by capture which returns ast
pub fn serialize() {
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Binary)

  #(type_, r.Arity1(do_serialize))
}

pub fn do_serialize(term, _builtins, k) {
  let exp = capture.capture(term)
  r.continue(k, r.Binary(encode.to_json(exp)))
}

pub fn capture() {
  // TODO need enum type
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, r.Arity1(do_capture))
}

pub fn do_capture(term, _builtins, k) {
  let exp = capture.capture(term)
  r.continue(k, expression_to_language(exp))
}

// could be term to lang
fn expression_to_language(exp) {
  case exp {
    e.Variable(label) ->
      r.Tagged("Variable", r.Record([#("label", r.Binary(label))]))
    e.Lambda(label, body) ->
      r.Tagged(
        "Lambda",
        r.Record([
          #("label", r.Binary(label)),
          #("body", expression_to_language(body)),
        ]),
      )
    e.Apply(func, argument) ->
      r.Tagged(
        "Apply",
        r.Record([
          #("func", expression_to_language(func)),
          #("arguement", expression_to_language(argument)),
        ]),
      )
    e.Let(label, definition, body) ->
      r.Tagged(
        "Let",
        r.Record([
          #("label", r.Binary(label)),
          #("definition", expression_to_language(definition)),
          #("body", expression_to_language(body)),
        ]),
      )

    e.Integer(value) ->
      r.Tagged("Integer", r.Record([#("value", r.Integer(value))]))
    e.Binary(value) ->
      r.Tagged("Binary", r.Record([#("value", r.Binary(value))]))

    e.Tail -> r.Tagged("Tail", r.Record([]))
    e.Cons -> r.Tagged("Cons", r.Record([]))

    e.Vacant -> r.Tagged("Vacant", r.Record([]))

    e.Empty -> r.Tagged("Empty", r.Record([]))
    e.Extend(label) ->
      r.Tagged("Extend", r.Record([#("label", r.Binary(label))]))
    e.Select(label) ->
      r.Tagged("Select", r.Record([#("label", r.Binary(label))]))
    e.Overwrite(label) ->
      r.Tagged("Overwrite", r.Record([#("label", r.Binary(label))]))
    e.Tag(label) -> r.Tagged("Tag", r.Record([#("label", r.Binary(label))]))
    e.Case(label) -> r.Tagged("Case", r.Record([#("label", r.Binary(label))]))
    e.NoCases -> r.Tagged("NoCases", r.Record([]))

    e.Perform(label) ->
      r.Tagged("Perform", r.Record([#("label", r.Binary(label))]))
    e.Handle(label) ->
      r.Tagged("Handle", r.Record([#("label", r.Binary(label))]))
    e.Builtin(identifier) ->
      r.Tagged("Builtin", r.Record([#("identifier", r.Binary(identifier))]))
  }
}

pub fn encode_uri() {
  let type_ = t.Fun(t.Binary, t.Open(-1), t.Binary)
  #(type_, r.Arity1(do_encode_uri))
}

pub fn do_encode_uri(term, _builtins, k) {
  use unencoded <- cast.string(term)
  r.continue(k, r.Binary(window.encode_uri(unencoded)))
}
