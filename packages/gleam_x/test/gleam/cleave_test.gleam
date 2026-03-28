import gleam/cleave

pub fn cleave_test() {
  assert Ok(#([2, 1], 3, [4, 5])) == cleave.around([1, 2, 3, 4, 5], 2)
}
