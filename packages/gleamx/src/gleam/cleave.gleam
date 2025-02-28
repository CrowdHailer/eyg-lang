pub type Cleaved(v) =
  #(List(v), v, List(v))

pub fn around(items, at) {
  do_around(items, at, [])
}

fn do_around(items, left, acc) {
  case items, left {
    // pre is left reversed
    [item, ..after], 0 -> Ok(#(acc, item, after))
    [item, ..after], i -> do_around(after, i - 1, [item, ..acc])
    [], _ -> Error(Nil)
  }
}
