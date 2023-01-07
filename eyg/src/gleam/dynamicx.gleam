pub fn decode1(constructor, d1) {
  fn(raw) {
    try value = d1(raw)
    Ok(constructor(value))
  }
}
