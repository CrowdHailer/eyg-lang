import eyg/cli/internal/source
import eyg/ir/tree as ir
import gleam/list

pub const meta = source.Location(source.Repl, source.Json)

pub fn variable(label) {
  #(ir.Variable(label), meta)
}

pub fn lambda(label, body) {
  #(ir.Lambda(label, body), meta)
}

pub fn apply(func, argument) {
  #(ir.Apply(func, argument), meta)
}

pub fn let_(label, value, then) {
  #(ir.Let(label, value, then), meta)
}

pub fn binary(value) {
  #(ir.Binary(value), meta)
}

pub fn integer(value) {
  #(ir.Integer(value), meta)
}

pub fn string(value) {
  #(ir.String(value), meta)
}

pub fn tail() {
  #(ir.Tail, meta)
}

pub fn cons() {
  #(ir.Cons, meta)
}

pub fn vacant() {
  #(ir.Vacant, meta)
}

pub fn empty() {
  #(ir.Empty, meta)
}

pub fn extend(label) {
  #(ir.Extend(label), meta)
}

pub fn select(label) {
  #(ir.Select(label), meta)
}

pub fn overwrite(label) {
  #(ir.Overwrite(label), meta)
}

pub fn tag(label) {
  #(ir.Tag(label), meta)
}

pub fn case_(label) {
  #(ir.Case(label), meta)
}

pub fn nocases() {
  #(ir.NoCases, meta)
}

pub fn perform(label) {
  #(ir.Perform(label), meta)
}

pub fn handle(label) {
  #(ir.Handle(label), meta)
}

pub fn builtin(identifier) {
  #(ir.Builtin(identifier), meta)
}

pub fn reference(identifier) {
  #(ir.ContentReference(identifier), meta)
}

pub fn release(package, release, identifier) {
  #(ir.ReleaseReference(package, release, identifier), meta)
}

pub fn relative(location) {
  #(ir.RelativeReference(location), meta)
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
