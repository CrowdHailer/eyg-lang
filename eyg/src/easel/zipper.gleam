import gleam/list
import gleam/result
import eygir/annotated as e

pub type Zipper(m) =
  #(e.Node(m), fn(e.Node(m)) -> e.Node(m))

pub fn at(expression, path) {
  do_zipper(expression, path, [])
}

fn do_zipper(expression, path, acc) {
  case path {
    [] ->
      Ok(
        #(expression, fn(new) {
          list.fold(acc, new, fn(element, build) { build(element) })
        }),
      )
    [index, ..path] -> {
      use #(child, rebuild) <- result.then(child(expression, index))
      do_zipper(child, path, [rebuild, ..acc])
    }
  }
}

fn child(node, index) {
  let #(expression, meta) = node
  case expression, index {
    e.Lambda(param, body), 0 ->
      Ok(#(body, fn(x) { #(e.Lambda(param, x), meta) }))
    e.Apply(func, arg), 0 -> Ok(#(func, fn(x) { #(e.Apply(x, arg), meta) }))
    e.Apply(func, arg), 1 -> Ok(#(arg, fn(x) { #(e.Apply(func, x), meta) }))
    e.Let(label, value, then), 0 ->
      Ok(#(value, fn(x) { #(e.Let(label, x, then), meta) }))
    e.Let(label, value, then), 1 ->
      Ok(#(then, fn(x) { #(e.Let(label, value, x), meta) }))
    _, _ -> Error(Nil)
  }
  // This is one of the things that would be harder with overwrite having children
}
