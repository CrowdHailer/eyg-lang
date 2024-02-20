import gleam/list
import eygir/expression as e

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
  Query(List(Constraint(m)))
  // Solve and project from Flix
  Solve(relation: String)
}

// first class is Compose for queries, Something for :-, And for Comma
pub type Constraint(m) {
  Constraint(head: Atom(m), body: List(#(Bool, Atom(m))))
}

// Atoms are also caused Literals maybe goals
pub type Atom(m) {
  Atom(relation: String, terms: List(#(String, #(Expression(m), m))))
}

pub fn strip_annotation(in) -> #(_, _) {
  let #(exp, acc) = do_strip_annotation(in, [])
  #(exp, list.reverse(acc))
}

pub fn drop_annotation(in) {
  strip_annotation(in).0
}

fn do_strip_annotation(in, acc) {
  let #(exp, meta) = in
  let acc = [meta, ..acc]
  case exp {
    Variable(x) -> #(e.Variable(x), acc)
    Lambda(label, body) -> {
      let #(exp, acc) = do_strip_annotation(body, acc)
      #(e.Lambda(label, exp), acc)
    }
    Apply(func, arg) -> {
      let #(func, acc) = do_strip_annotation(func, acc)
      let #(arg, acc) = do_strip_annotation(arg, acc)
      #(e.Apply(func, arg), acc)
    }
    Let(label, value, then) -> {
      let #(value, acc) = do_strip_annotation(value, acc)
      let #(then, acc) = do_strip_annotation(then, acc)
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
    Query(constraints) -> #(
      e.Query(
        list.map(constraints, fn(c) {
          let Constraint(head, body) = c
          let head = strip_atom(head)
          e.Constraint(
            head,
            list.map(body, fn(b) {
              let #(negate, atom) = b
              #(negate, strip_atom(atom))
            }),
          )
        }),
      ),
      acc,
    )
    Solve(label) -> #(e.Solve(label), acc)
  }
}

fn strip_atom(a) {
  let Atom(r, properties) = a
  let properties =
    list.map(properties, fn(p) {
      let #(k, value) = p
      #(k, drop_annotation(value))
    })
  e.Atom(r, properties)
}
