external fn log(a) -> Nil =
  "" "console.log"

pub fn fold(input: List(a), initial: b, func: fn(a, b) -> b) -> b {
  case input {
    [] -> initial
    [item, ..rest] -> fold(rest, func(item, initial), func)
  }
}

pub fn test() {
  fold([1, 2], [], fn(i, acc) { [#(Nil, i), ..acc] })
}
