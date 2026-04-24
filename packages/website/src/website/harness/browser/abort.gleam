import eyg/interpreter/break

pub fn blocking(lift) {
  //   use value <- result.map(impl(lift))
  Error(break.UnhandledEffect("Abort", lift))
}

pub fn preflight(lift) {
  Error(break.UnhandledEffect("Abort", lift))
}
