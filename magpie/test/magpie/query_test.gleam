import gleam/map
import magpie/query.{Constant, Variable}
import magpie/store/in_memory.{B, I, L, S}
import gleeunit/should

// part of mapx on cleanup branch
fn singleton(key, value) {
  map.new()
  |> map.insert(key, value)
}

pub fn match_pattern_test() {
  query.match_pattern(
    #(Variable("movie"), Constant(S("movie/director")), Variable("director")),
    #(200, "movie/director", I(100)),
    singleton("movie", I(200)),
  )
  |> should.equal(Ok(
    map.new()
    |> map.insert("movie", I(200))
    |> map.insert("director", I(100)),
  ))

  query.match_pattern(
    #(Variable("movie"), Constant(S("movie/director")), Variable("director")),
    #(200, "movie/director", I(100)),
    singleton("movie", I(202)),
  )
  |> should.equal(Error(Nil))
}
