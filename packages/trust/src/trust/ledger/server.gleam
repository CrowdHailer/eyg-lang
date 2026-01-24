import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type PullParameters {
  PullParameters(since: Int, limit: Int, entities: List(String))
}

pub fn pull_parameters_from_query(query) {
  let since =
    list.key_find(query, "since")
    |> result.try(int.parse)
    |> result.unwrap(0)

  let limit =
    list.key_find(query, "limit")
    |> result.try(int.parse)
    |> result.unwrap(1000)

  let entities =
    list.key_find(query, "entities")
    |> result.map(string.split(_, ","))
    |> result.unwrap([])
  PullParameters(since:, limit:, entities:)
}
