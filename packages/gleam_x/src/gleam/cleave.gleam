pub type Cleaved(v) =
  #(List(v), v, List(v))

/// split a list around an index returning
/// - items before (in reverse order)
/// - value at the index
/// - items after (in original order)
pub fn around(items: List(a), at: Int) -> Result(#(List(a), a, List(a)), Nil) {
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
