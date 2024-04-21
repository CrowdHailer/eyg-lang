import gleeunit/should
import magpie/query.{i, s, v}
import magpie/sources/movies.{movies}
import magpie/store/in_memory.{I, S}

pub fn when_was_alien_released_test() {
  query.run(
    ["year"],
    [
      #(v("movie"), s("movie/title"), s("Alien")),
      #(v("movie"), s("movie/year"), v("year")),
    ],
    movies(),
  )
  |> should.equal([[I(1979)]])
}

pub fn what_do_i_know_about_movie_200_test() {
  query.run(["attr", "value"], [#(i(200), v("attr"), v("value"))], movies())
  |> should.equal([
    [S("movie/title"), S("The Terminator")],
    [S("movie/year"), I(1984)],
    [S("movie/director"), I(100)],
    [S("movie/cast"), I(101)],
    [S("movie/cast"), I(102)],
    [S("movie/cast"), I(103)],
    [S("movie/sequel"), I(207)],
  ])
}

pub fn arnold_movie_director_test() {
  query.run(
    ["?directorName", "?movieTitle"],
    [
      #(v("?arnoldId"), s("person/name"), s("Arnold Schwarzenegger")),
      #(v("?movieId"), s("movie/cast"), v("?arnoldId")),
      #(v("?movieId"), s("movie/title"), v("?movieTitle")),
      #(v("?movieId"), s("movie/director"), v("?directorId")),
      #(v("?directorId"), s("person/name"), v("?directorName")),
    ],
    movies(),
  )
  |> should.equal([
    [S("James Cameron"), S("The Terminator")],
    [S("John McTiernan"), S("Predator")],
    [S("Mark L. Lester"), S("Commando")],
    [S("James Cameron"), S("Terminator 2: Judgment Day")],
    [S("Jonathan Mostow"), S("Terminator 3: Rise of the Machines")],
  ])
}
