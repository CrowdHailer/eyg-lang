pub type Option(a) {
  Some(a)
  None
}

/// Updates a value held within the Some of an Option by calling a given function
/// on it.
///
/// If the option is a None rather than Some the function is not called and the
/// option stays the same.
///
/// ## Examples
///
///    > map(over: Some(1), with: fn(x) { x + 1 })
///    Some(2)
///
///    > map(over: None, with: fn(x) { x + 1 })
///    None
///
pub fn map(over option: Option(a), with fun: fn(a) -> b) -> Option(b) {
  case option {
    Some(x) -> Some(fun(x))
    None -> None
  }
}
