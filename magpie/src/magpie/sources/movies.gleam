import gleam/dynamic.{Dynamic}
import gleam/list
import magpie/store/in_memory.{B, I, L, S}
import gleam/javascript/array.{Array}

external fn do_movies() -> Array(#(Int, String, Dynamic)) =
  "../../movies.mjs" "movies"

pub fn movies() {
  let assert Ok(movies) =
    array.to_list(do_movies())
    |> list.try_map(fn(r) {
      let #(e, a, v) = r
      try v =
        dynamic.any([
          dynamic.decode1(B, dynamic.bool),
          dynamic.decode1(I, dynamic.int),
          dynamic.decode1(S, dynamic.string),
        ])(
          v,
        )
      Ok(#(e, a, v))
    })
  in_memory.create_db(movies)
}
