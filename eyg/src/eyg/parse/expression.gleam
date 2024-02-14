import gleam/list
import eygir/expression as e

pub type Node(m) =
  #(Expression(m), m)

pub type Expression(m) {
  Variable(label: String)
  Lambda(label: String, body: #(Expression(m), m))
  Apply(func: #(Expression(m), m), argument: #(Expression(m), m))
  Let(label: String, definition: #(Expression(m), m), body: #(Expression(m), m))

  Binary(value: BitArray)
  Integer(value: Int)
  Str(value: String)

  Tail
  Cons

  Vacant(comment: String)

  Empty
  Extend(label: String)
  Select(label: String)
  Overwrite(label: String)
  Tag(label: String)
  Case(label: String)
  NoCases

  Perform(label: String)
  Handle(label: String)
  Shallow(label: String)

  Builtin(identifier: String)
}

pub fn strip_meta(in) {
  let #(exp, acc) = do_strip_meta(in, [])
  #(exp, list.reverse(acc))
}

fn do_strip_meta(in, acc) {
  let #(exp, meta) = in
  let acc = [meta, ..acc]
  case exp {
    Variable(x) -> #(e.Variable(x), acc)
    Lambda(label, body) -> {
      let #(exp, acc) = do_strip_meta(body, acc)
      #(e.Lambda(label, exp), acc)
    }
    Apply(func, arg) -> {
      let #(func, acc) = do_strip_meta(func, acc)
      let #(arg, acc) = do_strip_meta(arg, acc)
      #(e.Apply(func, arg), acc)
    }
    Let(label, value, then) -> {
      let #(value, acc) = do_strip_meta(value, acc)
      let #(then, acc) = do_strip_meta(then, acc)
      #(e.Let(label, value, then), acc)
    }
    Binary(value) -> #(e.Binary(value), acc)
    Integer(value) -> #(e.Integer(value), acc)
    Str(value) -> #(e.Str(value), acc)

    Tail -> #(e.Tail, acc)
    Cons -> #(e.Cons, acc)

    Vacant(comment) -> #(e.Vacant(comment), acc)

    Empty -> #(e.Empty, acc)
    Extend(label) -> #(e.Extend(label), acc)
    Select(label) -> #(e.Select(label), acc)
    Overwrite(label) -> #(e.Overwrite(label), acc)
    Tag(label) -> #(e.Tag(label), acc)
    Case(label) -> #(e.Case(label), acc)
    NoCases -> #(e.NoCases, acc)

    Perform(label) -> #(e.Perform(label), acc)
    Handle(label) -> #(e.Handle(label), acc)
    Shallow(label) -> #(e.Shallow(label), acc)

    Builtin(identifier) -> #(e.Builtin(identifier), acc)
  }
}

pub fn add_meta(exp, meta) {
  case exp {
    e.Variable(label) -> #(Variable(label), meta)
    e.Lambda(label, body) -> #(Lambda(label, add_meta(body, meta)), Nil)
    e.Apply(func, arg) -> #(
      Apply(add_meta(func, meta), add_meta(arg, Nil)),
      Nil,
    )
    e.Let(label, value, body) -> #(
      Let(label, add_meta(value, meta), add_meta(body, meta)),
      Nil,
    )

    e.Binary(value) -> #(Binary(value), meta)
    e.Integer(value) -> #(Integer(value), meta)
    e.Str(value) -> #(Str(value), meta)

    e.Tail -> #(Tail, meta)
    e.Cons -> #(Cons, meta)

    e.Vacant(comment) -> #(Vacant(comment), meta)

    e.Empty -> #(Empty, meta)
    e.Extend(label) -> #(Extend(label), meta)
    e.Select(label) -> #(Select(label), meta)
    e.Overwrite(label) -> #(Overwrite(label), meta)
    e.Tag(label) -> #(Tag(label), meta)
    e.Case(label) -> #(Case(label), meta)
    e.NoCases -> #(NoCases, meta)

    e.Perform(label) -> #(Perform(label), meta)
    e.Handle(label) -> #(Handle(label), meta)
    e.Shallow(label) -> #(Shallow(label), meta)

    e.Builtin(identifier) -> #(Builtin(identifier), meta)
  }
}
