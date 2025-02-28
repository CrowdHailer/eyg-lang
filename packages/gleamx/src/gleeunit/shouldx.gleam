import gleam/string

pub fn be_empty(a: List(a)) -> Nil {
  case a {
    [] -> Nil
    _ -> panic as string.concat(["\n", string.inspect(a), "\nshould be empty"])
  }
}

pub fn contain1(items) {
  case items {
    [a] -> a
    _ ->
      panic as string.concat([
        "\n",
        string.inspect(items),
        "\nshould have one item",
      ])
  }
}

pub fn contain2(items) {
  case items {
    [a, b] -> #(a, b)
    _ ->
      panic as string.concat([
        "\n",
        string.inspect(items),
        "\nshould have two items",
      ])
  }
}
