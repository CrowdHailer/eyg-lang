import gleam/list
import gleam/listx
import gleam/result
import morph/editable.{type Expression} as e

pub type Zipper {
  Expression(Expression, fn(Expression) -> Expression)
  Destructure
}

pub fn at(exp, path) {
  do_at(exp, path, [])
}

fn do_at(exp, path, acc) {
  case path {
    [] ->
      Ok(
        #(exp, fn(new) {
          list.fold(acc, new, fn(element, build) { build(element) })
        }),
      )
    [index, ..path] -> {
      use #(child, rebuild) <- result.then(child(exp, index))
      do_at(child, path, [rebuild, ..acc])
    }
  }
}

fn split_at(items) {
  todo
}

fn update_at(items, i) {
  let pre = list.take(items, i)
  let rest = list.drop(items, i)
  case rest {
    [item, ..post] -> Ok(#(item, fn(new) { list.flatten([pre, [new], post]) }))
  }
}

// general function doesn't work for looking up the tree
// i.e. for line above/below when in list

fn child(exp, index) {
  //   let #(exp, meta) = node
  case exp {
    e.Call(f, args) -> {
      let assert Ok(#(child, rebuild)) = update_at(args, index)
      let rebuild = fn(new) { e.Call(f, rebuild(new)) }
      Ok(#(child, rebuild))
    }
  }
  // e.Lambda(param, body), 0 ->
  //   Ok(#(body, fn(x) { #(e.Lambda(param, x), meta) }))
  // e.Apply(func, arg), 0 -> Ok(#(func, fn(x) { #(e.Apply(x, arg), meta) }))
  // e.Apply(func, arg), 1 -> Ok(#(arg, fn(x) { #(e.Apply(func, x), meta) }))
  // e.Let(label, value, then), 0 ->
  //   Ok(#(value, fn(x) { #(e.Let(label, x, then), meta) }))
  // e.Let(label, value, then), 1 ->
  //   Ok(#(then, fn(x) { #(e.Let(label, value, x), meta) }))
  // _, _ -> Error(Nil)
  // This is one of the things that would be harder with overwrite having children
}
