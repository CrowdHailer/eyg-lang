//// A deterministic pseudo random number generator.
////
//// Reproducibility matters more than statistical quality here.
//// Every counterexample has to be replayable from its seed.

pub opaque type Seed {
  Seed(state: Int)
}

pub fn seed(value: Int) {
  Seed(normalise(value * 2_654_435_761 + 1))
}

fn normalise(x) {
  let x = x % 2_147_483_647
  case x < 0 {
    True -> x + 2_147_483_647
    False -> x
  }
}

/// A Lehmer generator, chosen because it stays inside the safe integer range
/// on the JavaScript target.
fn next(seed: Seed) {
  let state = normalise(seed.state * 48_271)
  // Zero is a fixed point of the generator so it is never a valid state.
  let state = case state {
    0 -> 1
    _ -> state
  }
  Seed(state)
}

/// An integer in the range 0 (inclusive) to limit (exclusive).
pub fn int(seed, limit) {
  let seed = next(seed)
  #(seed.state % limit, seed)
}

/// Pick one item from a list, the list must not be empty.
pub fn pick(seed, items: List(a)) -> #(a, Seed) {
  let #(index, seed) = int(seed, length(items, 0))
  let assert Ok(item) = at(items, index)
  #(item, seed)
}

/// Pick one item from a list of #(weight, item), the list must not be empty.
pub fn weighted(seed, items: List(#(Int, a))) -> #(a, Seed) {
  let total = total_weight(items, 0)
  let #(index, seed) = int(seed, total)
  #(select(items, index), seed)
}

fn total_weight(items, acc) {
  case items {
    [] -> acc
    [#(weight, _), ..rest] -> total_weight(rest, acc + weight)
  }
}

fn select(items, index) {
  case items {
    [] -> panic as "no items to select from"
    [#(weight, item), ..rest] ->
      case index < weight {
        True -> item
        False -> select(rest, index - weight)
      }
  }
}

fn length(items, acc) {
  case items {
    [] -> acc
    [_, ..rest] -> length(rest, acc + 1)
  }
}

fn at(items, index) {
  case items, index {
    [], _ -> Error(Nil)
    [item, ..], 0 -> Ok(item)
    [_, ..rest], _ -> at(rest, index - 1)
  }
}
