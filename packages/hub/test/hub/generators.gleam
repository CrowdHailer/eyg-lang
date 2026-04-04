import gleam/int
import gleam/list
import gleam/listx
import gleam/string

const letters = [
  "a",
  "b",
  "c",
  "d",
  "e",
  "f",
  "g",
  "h",
  "i",
  "j",
  "k",
  "l",
  "m",
  "n",
  "o",
  "p",
  "q",
  "r",
  "s",
  "t",
  "u",
  "v",
  "w",
  "x",
  "y",
  "z",
]

pub fn package() {
  let length = int.random(5) + 2
  fn() { list.sample(letters, 1) }
  |> listx.repeatedly(length)
  |> list.flatten
  |> string.concat
}
