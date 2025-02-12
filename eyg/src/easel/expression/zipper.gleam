import eygir/annotated as a
import gleam/list
import gleam/result

pub type Zipper(m) =
  #(a.Node(m), fn(a.Node(m)) -> a.Node(m))

pub fn at(expression, path) -> Result(Zipper(_), Nil) {
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

fn child(expression, index) {
  let #(expression, meta) = expression
  case expression, index {
    a.Lambda(param, body), 0 ->
      Ok(#(body, fn(x) { #(a.Lambda(param, x), meta) }))
    a.Apply(func, arg), 0 -> Ok(#(func, fn(x) { #(a.Apply(x, arg), meta) }))
    a.Apply(func, arg), 1 -> Ok(#(arg, fn(x) { #(a.Apply(func, x), meta) }))
    a.Let(label, value, then), 0 ->
      Ok(#(value, fn(x) { #(a.Let(label, x, then), meta) }))
    a.Let(label, value, then), 1 ->
      Ok(#(then, fn(x) { #(a.Let(label, value, x), meta) }))
    _, _ -> Error(Nil)
  }
  // This is one of the things that would be harder with overwrite having children
}
