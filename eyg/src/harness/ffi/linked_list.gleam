import harness/ffi/spec.{
  build, empty, end, field, lambda, list_of, record, unbound, union, variant,
}

pub fn pop() {
  let el = unbound()
  lambda(
    list_of(el),
    union(variant(
      "Ok",
      record(field("head", el, field("tail", list_of(el), empty()))),
      variant("Error", record(empty()), end()),
    )),
  )
  |> build(fn(list) {
    fn(ok) {
      fn(error) {
        case list {
          [head, ..tail] -> ok(#(head, #(tail, Nil)))
          [] -> error(Nil)
        }
      }
    }
  })
}
