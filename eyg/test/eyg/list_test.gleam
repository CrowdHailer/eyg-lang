import gleam/io
import gleam/list

fn add_one(acc) {
  case acc {
    i if i < 10 -> Ok(#(i + 1))
    _ -> Error(Nil)
  }
}

pub fn try_fold_test() {
  let acc = 0
  let Ok(acc) =
    list.try_fold(
      [Nil, Nil, Nil, Nil],
      acc,
      fn(_item, acc) {
        try #(acc) = add_one(acc)
        Ok(acc)
      },
    )
  let 4 = acc
}
