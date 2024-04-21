import gleam/dict
import gleeunit/should
import magpie/query.{Constant, Variable, i, s, v}
import magpie/sources/movies.{movies}
import magpie/store/in_memory.{I, S}

// part of mapx on cleanup branch
fn singleton(key, value) {
  dict.new()
  |> dict.insert(key, value)
}

pub fn match_pattern_test() {
  query.match_pattern(
    #(Variable("movie"), Constant(S("movie/director")), Variable("director")),
    #(200, "movie/director", I(100)),
    singleton("movie", I(200)),
  )
  |> should.equal(Ok(
    dict.new()
    |> dict.insert("movie", I(200))
    |> dict.insert("director", I(100)),
  ))

  query.match_pattern(
    #(Variable("movie"), Constant(S("movie/director")), Variable("director")),
    #(200, "movie/director", I(100)),
    singleton("movie", I(202)),
  )
  |> should.equal(Error(Nil))
}

pub fn query_single_test() {
  query.single(#(v("movie"), s("movie/year"), i(1987)), movies(), dict.new())
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
    dict.new()
    |> dict.insert("movie", I(200))
    |> dict.insert("director", I(100))
    |> dict.insert("directorName", S("James Cameron")),
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
