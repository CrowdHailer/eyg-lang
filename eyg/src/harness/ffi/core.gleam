import gleam/io
import gleam/list
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
  r.continue(k, r.LinkedList(expression_to_language(exp)))
}

// could be term to lang
// Defunc continuation 
// recursive data structure vs list
// recusive correct by construction
// could just read till next end term
// Cases and provider
// i.e.
// match exp {
//   Handle format("handle %s")
// }
// crafting interpreters probably has a handle on this
// flat design is first step to hashable
// defunc continuation
// use the render block version and drop out when finished
// anything simple -> cont
// most other things use render block with indent
// try and write to buffer once but why performance
// actually always return lines
// if single render block does it's thing
// if not we nest in
// is there an elegant write once I think it pairs with defunc'd
// rendering? is it that interesting to do twice?
// TODO have a single code element that renders the value
fn expression_to_language(exp) {
  case exp {
    e.Variable(label) -> [r.Tagged("Variable", r.Binary(label))]
    e.Lambda(label, body) -> {
      let head = r.Tagged("Lambda", r.Binary(label))
      let rest = expression_to_language(body)
      [head, ..rest]
    }
    e.Apply(func, argument) -> {
      let head = r.Tagged("Apply", r.Record([]))
      let rest =
        list.append(
          expression_to_language(func),
          expression_to_language(argument),
        )
      [head, ..rest]
    }
    e.Let(label, definition, body) -> {
      let head = r.Tagged("Let", r.Binary(label))
      [
        head,
        ..list.append(
          expression_to_language(definition),
          expression_to_language(body),
        )
      ]
    }

    e.Integer(value) -> [r.Tagged("Integer", r.Integer(value))]
    e.Binary(value) -> [r.Tagged("Binary", r.Binary(value))]

    e.Tail -> [r.Tagged("Tail", r.Record([]))]
    e.Cons -> [r.Tagged("Cons", r.Record([]))]

    e.Vacant -> [r.Tagged("Vacant", r.Record([]))]

    e.Empty -> [r.Tagged("Empty", r.Record([]))]
    e.Extend(label) -> [r.Tagged("Extend", r.Binary(label))]
    e.Select(label) -> [r.Tagged("Select", r.Binary(label))]
    e.Overwrite(label) -> [r.Tagged("Overwrite", r.Binary(label))]
    e.Tag(label) -> [r.Tagged("Tag", r.Binary(label))]
    e.Case(label) -> [r.Tagged("Case", r.Binary(label))]
    e.NoCases -> [r.Tagged("NoCases", r.Record([]))]

    e.Perform(label) -> [r.Tagged("Perform", r.Binary(label))]
    e.Handle(label) -> [r.Tagged("Handle", r.Binary(label))]
    e.Builtin(identifier) -> [r.Tagged("Builtin", r.Binary(identifier))]
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
