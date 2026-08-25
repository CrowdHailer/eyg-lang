import eyg/ir/utils
import gleam/io
import gleam/list
import gleam/string
import midas/continuation.{type Continuation as K, return, then}
import multiformats/cid/v1

/// A node consists of an expression and associated metadata
pub type Node(m) =
  #(Expression(m), m)

/// The entire structure of an EYG program is specified in the following expression nodes.
pub type Expression(m) {
  Variable(label: String)
  Lambda(label: String, body: #(Expression(m), m))
  Apply(func: #(Expression(m), m), argument: #(Expression(m), m))
  Let(label: String, definition: #(Expression(m), m), body: #(Expression(m), m))

  Binary(value: BitArray)
  Integer(value: Int)
  String(value: String)

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
  Reference(reference: Reference)
}

/// A reference to another eyg module.
///
/// Content and Pinned are verifyable against a given module, any shared/or published module can only use these references.
/// Version is fixed, the EYG hub does not accept republishing modules.
/// Package refers only to a package by name. In most instances this will resolve to the latest release in a local cache.
/// Relative is specific to the workspace running the program.
/// This is often the filesystem but can be other things i.e. the location can be cells in a spreadsheet using EYG for scripting.
pub type Reference {
  Content(cid: v1.Cid)
  Package(package: String)
  Version(package: String, version: Int)
  Pinned(release: Release)
  Relative(location: String)
}

/// The identifier of a fully qualified release.
pub type Release {
  Release(package: String, version: Int, module: v1.Cid)
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
  #(String(value), Nil)
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
  #(Reference(Content(identifier)), Nil)
}

pub fn package(package) {
  #(Reference(Package(package)), Nil)
}

pub fn version(package, version) {
  #(Reference(Version(package, version)), Nil)
}

pub fn release(package, version, module) {
  #(Reference(Pinned(Release(package, version, module))), Nil)
}

pub fn relative(location) {
  #(Reference(Relative(location)), Nil)
}

pub fn func(params, body) {
  list.fold_right(params, body, fn(acc, param) { lambda(param, acc) })
}

pub fn call(f, args) {
  list.fold(args, f, fn(acc, arg) { apply(acc, arg) })
}

pub fn block(assignments, then) {
  list.fold_right(assignments, then, fn(acc, assignment) {
    let #(label, value) = assignment
    let_(label, value, acc)
  })
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

pub fn record(fields) {
  do_record(list.reverse(fields), empty())
}

pub fn do_record(reversed, acc) {
  case reversed {
    [#(key, value), ..rest] ->
      do_record(rest, apply(apply(extend(key), value), acc))
    [] -> acc
  }
}

pub fn unit() {
  empty()
}

pub fn get(value, label) {
  apply(select(label), value)
}

pub fn tagged(label, inner) {
  apply(tag(label), inner)
}

pub fn true() {
  tagged("True", unit())
}

pub fn false() {
  tagged("False", unit())
}

pub fn match(value, matches) {
  let m =
    list.fold_right(matches, nocases(), fn(acc, match) {
      let #(label, branch) = match
      call(case_(label), [branch, acc])
    })
  apply(m, value)
}

pub fn add(a, b) {
  apply(apply(builtin("int_add"), a), b)
}

pub fn subtract(a, b) {
  apply(apply(builtin("int_subtract"), a), b)
}

pub fn multiply(a, b) {
  apply(apply(builtin("int_multiply"), a), b)
}

pub fn get_annotation(node: Node(a)) {
  fold(node, [], fn(acc, node) { return([node.1, ..acc]) })(list.reverse)
}

pub fn map_annotation(in: Node(a), f: fn(a) -> b) -> Node(b) {
  rewrite_meta(in, fn(m) { return(f(m)) })(fn(x) { x })
}

pub fn clear_annotation(source) {
  map_annotation(source, fn(_) { Nil })
}

pub fn list_builtins(node: Node(a)) {
  {
    use acc, #(exp, _meta) <- fold(node, [])
    case exp {
      Builtin(i) -> utils.push_new(acc, i)
      _ -> acc
    }
    |> return
  }(list.reverse)
}

pub fn list_references(node: Node(a)) -> List(Reference) {
  {
    use acc, #(exp, _meta) <- fold(node, [])
    case exp {
      Reference(reference) -> utils.push_new(acc, reference)
      _ -> acc
    }
    |> return
  }(list.reverse)
}

/// The variables that are free in this expressions.
/// Free variables need to be in an environment of the expression may crash.
pub fn free_variables(node: Node(a), ignore: List(String)) -> List(String) {
  do_free_variables(node, [], ignore) |> list.reverse()
}

fn do_free_variables(node, found, ignore) {
  let #(exp, _meta) = node
  case exp {
    Variable(var) ->
      case list.contains(found, var) || list.contains(ignore, var) {
        True -> found
        False -> [var, ..found]
      }
    Let(var, value, then) -> {
      let found = do_free_variables(value, found, ignore)
      let ignore = case list.contains(ignore, var) {
        True -> ignore
        False -> [var, ..ignore]
      }
      do_free_variables(then, found, ignore)
    }
    Lambda(var, body) -> {
      let ignore = case list.contains(ignore, var) {
        True -> ignore
        False -> [var, ..ignore]
      }
      do_free_variables(body, found, ignore)
    }
    Apply(func, arg) -> {
      let found = do_free_variables(func, found, ignore)
      do_free_variables(arg, found, ignore)
    }
    _ -> found
  }
}

// pub fn substitute_for_references(exp, subs) {
//   let #(exp, meta) = exp
//   let exp = case exp {
//     Variable(var) ->
//       case list.key_find(subs, var) {
//         Ok(ref) -> Reference(ref)
//         Error(Nil) -> exp
//       }
//     Let(var, value, then) -> {
//       let value = substitute_for_references(value, subs)
//       let subs = listx.key_reject(subs, var)
//       let then = substitute_for_references(then, subs)
//       Let(var, value, then)
//     }
//     Lambda(var, body) -> {
//       let subs = listx.key_reject(subs, var)
//       let body = substitute_for_references(body, subs)
//       Lambda(var, body)
//     }
//     Apply(func, arg) -> {
//       let func = substitute_for_references(func, subs)
//       let arg = substitute_for_references(arg, subs)
//       Apply(func, arg)
//     }
//     _ -> exp
//   }
//   #(exp, meta)
// }

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
    Let("_", #(String(comment), _), then), [] ->
      do_gather_snippets(then, [comment, ..comments], assigns, acc)
    // if assignes is not empty start new block
    Let("_", #(String(new), _), then), _ -> {
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
      io.println(string.inspect(tail))
      [#(comments, assigns), ..acc]
    }
  }
}

// returnes reversed assignments
pub fn gather_snippets(source) {
  do_gather_snippets(source, [], [], [])
}

/// Return the children of the given node in canonical order.
pub fn children(node: Node(a)) -> List(Node(a)) {
  let #(exp, _meta) = node
  case exp {
    Lambda(label: _, body:) -> [body]
    Apply(func:, argument:) -> [func, argument]
    Let(label: _, definition:, body:) -> [definition, body]
    _ -> []
  }
}

/// Apply a function f to the children of an expression.
/// 
/// Note `map_children` works over expressions, not nodes.
/// This allows the returned metadata type to be transformed by the `f`.
/// The parent metadata is mapped explicitly when rebuilding `Node(b)`
pub fn map_children(
  exp: Expression(a),
  f: fn(Node(a)) -> K(t, Node(b)),
) -> K(t, Expression(b)) {
  case exp {
    Lambda(parameter, body) -> {
      use body <- then(f(body))
      return(Lambda(parameter, body))
    }
    Apply(function, argument) -> {
      use function <- then(f(function))
      use argument <- then(f(argument))
      return(Apply(function, argument))
    }
    Let(label, definition, body) -> {
      use definition <- then(f(definition))
      use body <- then(f(body))
      return(Let(label, definition, body))
    }
    Variable(label:) -> return(Variable(label:))
    Binary(value:) -> return(Binary(value:))
    Integer(value:) -> return(Integer(value:))
    String(value:) -> return(String(value:))
    Tail -> return(Tail)
    Cons -> return(Cons)
    Vacant -> return(Vacant)
    Empty -> return(Empty)
    Extend(label:) -> return(Extend(label:))
    Select(label:) -> return(Select(label:))
    Overwrite(label:) -> return(Overwrite(label:))
    Tag(label:) -> return(Tag(label:))
    Case(label:) -> return(Case(label:))
    NoCases -> return(NoCases)
    Perform(label:) -> return(Perform(label:))
    Handle(label:) -> return(Handle(label:))
    Builtin(identifier:) -> return(Builtin(identifier:))
    Reference(reference:) -> return(Reference(reference:))
  }
}

/// Visit each node in a pre-order depth-first traversal and accumulate a value
pub fn fold(node: Node(a), acc: b, f: fn(b, Node(a)) -> K(t, b)) -> K(t, b) {
  do_fold([node], acc, f)
}

fn do_fold(
  nodes: List(Node(a)),
  acc: b,
  f: fn(b, Node(a)) -> K(t, b),
) -> K(t, b) {
  case nodes {
    [] -> return(acc)
    [n, ..rest] -> {
      let rest = list.append(children(n), rest)
      use acc <- then(f(acc, n))
      do_fold(rest, acc, f)
    }
  }
}

/// Visit each node in a post-order depth-first traversal and accumulate a value
pub fn fold_post_order(
  node: Node(a),
  acc: b,
  f: fn(b, Node(a)) -> K(t, b),
) -> K(t, b) {
  do_fold_post_order([node], acc, f)
}

fn do_fold_post_order(
  nodes: List(Node(a)),
  acc: b,
  f: fn(b, Node(a)) -> K(t, b),
) -> K(t, b) {
  case nodes {
    [] -> return(acc)
    [n, ..rest] -> {
      use acc <- then(do_fold_post_order(children(n), acc, f))
      use acc <- then(f(acc, n))
      do_fold_post_order(rest, acc, f)
    }
  }
}

/// Transform each node in a tree.
/// The transformation function `f` sees any children as already rewritten.
pub fn rewrite(
  node: Node(a),
  f: fn(#(Expression(b), a)) -> K(t, Node(b)),
) -> K(t, Node(b)) {
  let recur = fn(child) { rewrite(child, f) }
  let #(exp, meta) = node
  use rebuilt <- then(map_children(exp, recur))
  f(#(rebuilt, meta))
}

/// Transform each node in a tree while passing an accumlated value in post order.
/// The transformation function `f` sees any children as already rewritten.
pub fn rewrite_with(
  node: Node(a),
  with acc: c,
  using f: fn(c, #(Expression(b), a)) -> K(t, #(c, Node(b))),
) -> K(t, #(c, Node(b))) {
  let #(exp, meta) = node
  use #(acc, rebuilt) <- then(map_children_with(exp, acc, f))
  f(acc, #(rebuilt, meta))
}

/// Like `map_children` but with an accumulator value passed to f with each node in order.
pub fn map_children_with(
  exp: Expression(a),
  acc: c,
  f: fn(c, #(Expression(b), a)) -> K(t, #(c, Node(b))),
) -> K(t, #(c, Expression(b))) {
  case exp {
    Lambda(parameter, body) -> {
      use #(acc, body) <- then(rewrite_with(body, acc, f))
      return(#(acc, Lambda(parameter, body)))
    }
    Apply(function, argument) -> {
      use #(acc, function) <- then(rewrite_with(function, acc, f))
      use #(acc, argument) <- then(rewrite_with(argument, acc, f))
      return(#(acc, Apply(function, argument)))
    }
    Let(label, definition, body) -> {
      use #(acc, definition) <- then(rewrite_with(definition, acc, f))
      use #(acc, body) <- then(rewrite_with(body, acc, f))
      return(#(acc, Let(label, definition, body)))
    }
    Variable(label:) -> return(#(acc, Variable(label:)))
    Binary(value: bytes) -> return(#(acc, Binary(value: bytes)))
    Integer(value: integer) -> return(#(acc, Integer(value: integer)))
    String(value: string) -> return(#(acc, String(value: string)))
    Tail -> return(#(acc, Tail))
    Cons -> return(#(acc, Cons))
    Vacant -> return(#(acc, Vacant))
    Empty -> return(#(acc, Empty))
    Extend(label:) -> return(#(acc, Extend(label:)))
    Select(label:) -> return(#(acc, Select(label:)))
    Overwrite(label:) -> return(#(acc, Overwrite(label:)))
    Tag(label:) -> return(#(acc, Tag(label:)))
    Case(label:) -> return(#(acc, Case(label:)))
    NoCases -> return(#(acc, NoCases))
    Perform(label:) -> return(#(acc, Perform(label:)))
    Handle(label:) -> return(#(acc, Handle(label:)))
    Builtin(identifier:) -> return(#(acc, Builtin(identifier:)))
    Reference(reference:) -> return(#(acc, Reference(reference:)))
  }
}

/// Transform just the metadata in each node.
pub fn rewrite_meta(node: Node(a), f: fn(a) -> K(t, b)) -> K(t, Node(b)) {
  rewrite(node, fn(node) {
    let #(exp, meta) = node
    use meta <- then(f(meta))
    return(#(exp, meta))
  })
}
