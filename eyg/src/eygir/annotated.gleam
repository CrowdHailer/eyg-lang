import eygir/expression as e
import gleam/dynamic
import gleam/io
import gleam/list
import gleam/listx

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
  Reference(identifier: String)
}

pub fn strip_annotation(in) {
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
    Reference(identifier) -> #(e.Reference(identifier), acc)
  }
}

pub fn add_annotation(exp, meta) {
  case exp {
    e.Variable(label) -> #(Variable(label), meta)
    e.Lambda(label, body) -> #(Lambda(label, add_annotation(body, meta)), meta)
    e.Apply(func, arg) -> #(
      Apply(add_annotation(func, meta), add_annotation(arg, meta)),
      meta,
    )
    e.Let(label, value, body) -> #(
      Let(label, add_annotation(value, meta), add_annotation(body, meta)),
      meta,
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
    e.Reference(identifier) -> #(Reference(identifier), meta)
  }
}

pub fn map_annotation(
  in: #(Expression(a), a),
  f: fn(a) -> b,
) -> #(Expression(b), b) {
  let #(exp, meta) = in
  case exp {
    Lambda(label, body) -> {
      let body = map_annotation(body, f)
      #(Lambda(label, body), f(meta))
    }
    Apply(func, arg) -> {
      let func = map_annotation(func, f)
      let arg = map_annotation(arg, f)
      #(Apply(func, arg), f(meta))
    }
    Let(label, value, then) -> {
      let value = map_annotation(value, f)
      let then = map_annotation(then, f)
      #(Let(label, value, then), f(meta))
    }
    primitive -> {
      #(dynamic.unsafe_coerce(dynamic.from(primitive)), f(meta))
    }
  }
}

pub fn list_builtins(exp) {
  do_list_builtins(exp, [])
}

// do later node first in Let/Call statements so no need to reverse
fn do_list_builtins(exp, found) {
  let #(exp, _meta) = exp
  case exp {
    Builtin(identifier) ->
      case list.contains(found, identifier) {
        True -> found
        False -> [identifier, ..found]
      }
    Let(_label, value, then) -> {
      let found = do_list_builtins(then, found)
      do_list_builtins(value, found)
    }
    Lambda(_label, body) -> do_list_builtins(body, found)
    Apply(func, arg) -> {
      let found = do_list_builtins(arg, found)
      do_list_builtins(func, found)
    }
    _ -> found
  }
}

pub fn free_variables(exp) {
  do_free_variables(exp, [], [])
}

fn do_free_variables(exp, found, ignore) {
  let #(exp, _meta) = exp
  case exp {
    Variable(var) ->
      case list.contains(found, var) || list.contains(ignore, var) {
        True -> found
        False -> [var, ..found]
      }
    Let(var, value, then) -> {
      let found = do_free_variables(then, found, ignore)
      let ignore = case list.contains(ignore, var) {
        True -> ignore
        False -> [var, ..ignore]
      }
      do_free_variables(value, found, ignore)
    }
    Lambda(var, body) -> {
      let ignore = case list.contains(ignore, var) {
        True -> ignore
        False -> [var, ..ignore]
      }
      do_free_variables(body, found, ignore)
    }
    Apply(func, arg) -> {
      let found = do_free_variables(arg, found, ignore)
      do_free_variables(func, found, ignore)
    }
    _ -> found
  }
}

pub fn substitute_for_references(exp, subs) {
  let #(exp, meta) = exp
  let exp = case exp {
    Variable(var) ->
      case list.key_find(subs, var) {
        Ok(ref) -> Reference(ref)
        Error(Nil) -> exp
      }
    Let(var, value, then) -> {
      let value = substitute_for_references(value, subs)
      let subs = listx.key_reject(subs, var)
      let then = substitute_for_references(then, subs)
      Let(var, value, then)
    }
    Lambda(var, body) -> {
      let subs = listx.key_reject(subs, var)
      let body = substitute_for_references(body, subs)
      Lambda(var, body)
    }
    Apply(func, arg) -> {
      let func = substitute_for_references(func, subs)
      let arg = substitute_for_references(arg, subs)
      Apply(func, arg)
    }
    _ -> exp
  }
  #(exp, meta)
}
