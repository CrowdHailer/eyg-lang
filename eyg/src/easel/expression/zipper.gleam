import eyg/ir/tree as ir
import gleam/list
import gleam/result

pub type Zipper(m) =
  #(ir.Node(m), fn(ir.Node(m)) -> ir.Node(m))

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
    ir.Lambda(param, body), 0 ->
      Ok(#(body, fn(x) { #(ir.Lambda(param, x), meta) }))
    ir.Apply(func, arg), 0 -> Ok(#(func, fn(x) { #(ir.Apply(x, arg), meta) }))
    ir.Apply(func, arg), 1 -> Ok(#(arg, fn(x) { #(ir.Apply(func, x), meta) }))
    ir.Let(label, value, then), 0 ->
      Ok(#(value, fn(x) { #(ir.Let(label, x, then), meta) }))
    ir.Let(label, value, then), 1 ->
      Ok(#(then, fn(x) { #(ir.Let(label, value, x), meta) }))
    _, _ -> Error(Nil)
  }
  // This is one of the things that would be harder with overwrite having children
}
