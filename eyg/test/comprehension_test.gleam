import gleam/list
import gleam/string
import gleeunit/should

fn in(items, cb) {
  list.flat_map(items, cb)
}

fn for() {
  use x <- in(["1", "2"])
  use y <- in(["a", "b"])
  [string.append(x, y)]
}

pub fn list_test() {
  for()
  |> should.equal(["1a", "1b", "2a", "2b"])
}

fn return(value, _cb) {
  value
}

pub fn return_test() -> Nil {
  {
    use <- return(2)
    1
  }
  |> should.equal(2)
}
