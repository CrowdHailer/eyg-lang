import gleam/map
import magpie/query.{Constant, Variable, i, s, v}
import magpie/store/in_memory.{B, I, L, S}
import magpie/sources/movies.{movies}
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

pub fn query_single_test() {
  query.single(#(v("movie"), s("movie/year"), i(1987)), movies(), map.new())
  |> should.equal([
    singleton("movie", I(202)),
    singleton("movie", I(203)),
    singleton("movie", I(204)),
  ])
}

pub fn query_where_test() {
  query.where(
    [
      #(v("movie"), s("movie/title"), s("The Terminator")),
      #(v("movie"), s("movie/director"), v("director")),
      #(v("director"), s("person/name"), v("directorName")),
    ],
    movies(),
  )
  |> should.equal([
    map.new()
    |> map.insert("movie", I(200))
    |> map.insert("director", I(100))
    |> map.insert("directorName", S("James Cameron")),
  ])
}

pub fn query_rest_test() {
  query.run(
    ["directorName"],
    [
      #(v("movie"), s("movie/title"), s("The Terminator")),
      #(v("movie"), s("movie/director"), v("director")),
      #(v("director"), s("person/name"), v("directorName")),
    ],
    movies(),
  )
  |> should.equal([[S("James Cameron")]])
}
