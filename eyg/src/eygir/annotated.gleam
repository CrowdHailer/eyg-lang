import eygir/expression as e
import gleam/dynamic
import gleam/dynamicx
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

  Vacant

  Empty
  Extend(label: String)
  Select(label: String)
  Overwrite(label: String)
  Tag(label: String)
  Case(label: String)
  NoCases

  Perform(label: String)
  Handle(label: String)

  Builtin(identifier: String)
  Reference(identifier: String)
  NamedReference(package: String, release: Int)
}

pub fn variable(label) {
  #(Variable(label), Nil)
}

pub fn lambda(label, body) {
  #(Lambda(label, body), Nil)
}

pub fn apply(func, argument) {
  #(Apply(func, argument), Nil)
}

pub fn let_(label, value, then) {
  #(Let(label, value, then), Nil)
}

pub fn binary(value) {
  #(Binary(value), Nil)
}

pub fn integer(value) {
  #(Integer(value), Nil)
}

pub fn string(value) {
  #(Str(value), Nil)
}

pub fn tail() {
  #(Tail, Nil)
}

pub fn cons() {
  #(Cons, Nil)
}

pub fn vacant() {
  #(Vacant, Nil)
}

pub fn empty() {
  #(Empty, Nil)
}

pub fn extend(label) {
  #(Extend(label), Nil)
}

pub fn select(label) {
  #(Select(label), Nil)
}

pub fn overwrite(label) {
  #(Overwrite(label), Nil)
}

pub fn tag(label) {
  #(Tag(label), Nil)
}

pub fn case_(label) {
  #(Case(label), Nil)
}

pub fn nocases() {
  #(NoCases, Nil)
}

pub fn perform(label) {
  #(Perform(label), Nil)
}

pub fn handle(label) {
  #(Handle(label), Nil)
}

pub fn builtin(identifier) {
  #(Builtin(identifier), Nil)
}

pub fn reference(identifier) {
  #(Reference(identifier), Nil)
}

pub fn namedreference(package, release) {
  #(NamedReference(package, release), Nil)
}

pub fn unit() {
  empty()
}

pub fn true() {
  apply(tag("True"), unit())
}

pub fn false() {
  apply(tag("False"), unit())
}

pub fn list(items) {
  do_list(list.reverse(items), tail())
}

pub fn do_list(reversed, acc) {
  case reversed {
    [item, ..rest] -> do_list(rest, apply(apply(cons(), item), acc))
    [] -> acc
  }
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

    Vacant -> #(e.Vacant, acc)

    Empty -> #(e.Empty, acc)
    Extend(label) -> #(e.Extend(label), acc)
    Select(label) -> #(e.Select(label), acc)
    Overwrite(label) -> #(e.Overwrite(label), acc)
    Tag(label) -> #(e.Tag(label), acc)
    Case(label) -> #(e.Case(label), acc)
    NoCases -> #(e.NoCases, acc)

    Perform(label) -> #(e.Perform(label), acc)
    Handle(label) -> #(e.Handle(label), acc)

    Builtin(identifier) -> #(e.Builtin(identifier), acc)
    Reference(identifier) -> #(e.Reference(identifier), acc)
    NamedReference(package, release) -> #(
      e.NamedReference(package, release),
      acc,
    )
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

    e.Vacant -> #(Vacant, meta)

    e.Empty -> #(Empty, meta)
    e.Extend(label) -> #(Extend(label), meta)
    e.Select(label) -> #(Select(label), meta)
    e.Overwrite(label) -> #(Overwrite(label), meta)
    e.Tag(label) -> #(Tag(label), meta)
    e.Case(label) -> #(Case(label), meta)
    e.NoCases -> #(NoCases, meta)

    e.Perform(label) -> #(Perform(label), meta)
    e.Handle(label) -> #(Handle(label), meta)

    e.Builtin(identifier) -> #(Builtin(identifier), meta)
    e.Reference(identifier) -> #(Reference(identifier), meta)
    e.NamedReference(package, release) -> #(
      NamedReference(package, release),
      meta,
    )
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
      #(dynamicx.unsafe_coerce(dynamic.from(primitive)), f(meta))
    }
  }
}

pub fn clear_annotation(source) {
  map_annotation(source, fn(_) { Nil })
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

pub fn list_references(exp) {
  do_list_references(exp, [])
}

// do later node first in Let/Call statements so no need to reverse
fn do_list_references(exp, found) {
  let #(exp, _meta) = exp
  case exp {
    Reference(identifier) ->
      case list.contains(found, identifier) {
        True -> found
        False -> [identifier, ..found]
      }
    Let(_label, value, then) -> {
      let found = do_list_references(then, found)
      do_list_references(value, found)
    }
    Lambda(_label, body) -> do_list_references(body, found)
    Apply(func, arg) -> {
      let found = do_list_references(arg, found)
      do_list_references(func, found)
    }
    _ -> found
  }
}

pub fn list_named_references(exp) {
  do_list_named_references(exp, [])
}

// do later node first in Let/Call statements so no need to reverse
fn do_list_named_references(exp, found) {
  let #(exp, _meta) = exp
  case exp {
    NamedReference(package, release) ->
      case list.contains(found, #(package, release)) {
        True -> found
        False -> [#(package, release), ..found]
      }
    Let(_label, value, then) -> {
      let found = do_list_named_references(then, found)
      do_list_named_references(value, found)
    }
    Lambda(_label, body) -> do_list_named_references(body, found)
    Apply(func, arg) -> {
      let found = do_list_named_references(arg, found)
      do_list_named_references(func, found)
    }
    _ -> found
  }
}

// currently unused as moved to analysis
pub fn list_vacant(exp) {
  do_list_vacant(exp, [])
}

pub fn do_list_vacant(exp, found) {
  let #(exp, meta) = exp
  case exp {
    Vacant -> [#(meta, "todo"), ..found]
    Let(_label, value, then) -> {
      let found = do_list_vacant(then, found)
      do_list_vacant(value, found)
    }
    Lambda(_label, body) -> do_list_vacant(body, found)
    Apply(func, arg) -> {
      let found = do_list_vacant(arg, found)
      do_list_vacant(func, found)
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

pub fn from_block(assigns, tail) {
  list.fold(assigns, tail, fn(acc, assign) {
    let #(label, value, meta) = assign
    #(Let(label, value, acc), meta)
  })
}

pub fn do_gather_snippets(node, comments, assigns, acc) {
  let #(exp, meta) = node
  case exp, assigns {
    // if assigns is empty keep adding comments
    Let("_", #(Str(comment), _), then), [] ->
      do_gather_snippets(then, [comment, ..comments], assigns, acc)
    // if assignes is not empty start new block
    Let("_", #(Str(new), _), then), _ -> {
      let comments = list.reverse(comments)
      let assigns = list.reverse(assigns)
      // comments are context
      let acc = [#(comments, assigns), ..acc]
      do_gather_snippets(then, [new], [], acc)
    }
    Let(label, value, then), _ -> {
      let assigns = [#(label, value, meta), ..assigns]
      do_gather_snippets(then, comments, assigns, acc)
    }
    tail, _ -> {
      io.debug(tail)
      [#(comments, assigns), ..acc]
    }
  }
}

// returnes reversed assignments
pub fn gather_snippets(source) {
  do_gather_snippets(source, [], [], [])
}
