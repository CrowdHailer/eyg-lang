import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import gleam/result
import gleam/javascript
import gleam/javascript/array.{Array}
import gleeunit/should

// TODO needs to be top level or bundled with source when building
external fn do_movies() -> Array(#(Int, String, Dynamic)) =
  "/Users/petersaxton/src/github.com/crowdhailer/eyg-lang/magpie/src/movies.mjs" "movies"

// "/opt/app/magpie/src/movies.mjs" "movies"

pub type Value {
  B(Bool)
  I(Int)
  S(String)
  L(List(Value))
}

pub fn movies() {
  array.to_list(do_movies())
  |> list.try_map(fn(r) {
    let #(e, a, v) = r
    use v <- result.then(dynamic.any([
      dynamic.decode1(B, dynamic.bool),
      dynamic.decode1(I, dynamic.int),
      dynamic.decode1(S, dynamic.string),
    ])(v))
    Ok(#(e, a, v))
  })
}

// getting objects
// pub fn new_test()  {
//     {
//         use movie <- db()
//         use title <- get(movie, "movie/title", string)
//         use year <- get(movie, "movie/year", is(1987))
//         yield(#(title, year))
//     }
//     todo
// }
// just smart map and filter, could be paraelised

pub type Match(c, t) {
  Variable(fn(c, t) -> Result(c, Nil))
  Constant(t)
}

fn c(value) {
  Constant(value)
}

fn match_part(match, part, context) {
  case match {
    Constant(value) if value == part -> Ok(context)
    Constant(_) -> Error(Nil)
    Variable(update) ->
      case update(context, part) {
        Error(Nil) -> Error(Nil)
        Ok(context) -> {
          Ok(context)
        }
      }
  }
}

pub fn match_pattern(
  e: Match(c, Int),
  a: Match(c, String),
  v,
  triple: #(Int, String, Value),
  context,
) {
  use context <- result.then(match_part(e, triple.0, context))
  use context <- result.then(match_part(a, triple.1, context))
  use context <- result.then(match_part(v, triple.2, context))
  Ok(context)
}

fn single(
  e: Match(c, Int),
  a: Match(c, String),
  v,
  triples,
  context: c,
) -> List(c) {
  list.filter_map(triples, match_pattern(e, a, v, _, context))
}

fn match(e: Match(c, Int), a: Match(c, String), v, k) {
  fn(triples, contexts) {
    let contexts =
      list.map(contexts, single(e, a, v, triples, _))
      |> list.flatten
    // pass full db for every pattern hence value in index
    k()(triples, contexts)
  }
}

fn done() {
  fn(triples, contexts) { contexts }
}

fn find(
  query: fn(Match(#(Option(t)), t)) ->
    fn(List(#(Int, String, Value)), List(#(Option(t)))) -> List(#(Option(t))),
) {
  fn(triples) {
    let contexts =
      query(Variable(fn(state, value) {
        let #(a) = state
        case a {
          None -> Ok(#(Some(value)))
          Some(v) if v == value -> Ok(#(Some(value)))
          _ -> Error(Nil)
        }
      }))(triples, [#(None)])
    contexts
    |> list.try_map(fn(c) {
      case c.0 {
        Some(value) -> Ok(value)
        None -> Error("query parameter not used")
      }
    })
  }
}

fn find2(
  query: fn(
    Match(#(Option(t), Option(u)), t),
    Match(#(Option(t), Option(u)), u),
  ) ->
    fn(List(#(Int, String, Value)), List(#(Option(t), Option(u)))) ->
      List(#(Option(t), Option(u))),
) {
  fn(triples) {
    let contexts =
      query(
        Variable(fn(state, value) {
          let #(a, b) = state
          case a {
            None -> Ok(#(Some(value), b))
            Some(v) if v == value -> Ok(#(Some(value), b))
            _ -> Error(Nil)
          }
        }),
        Variable(fn(state, value) {
          let #(a, b) = state
          case b {
            None -> Ok(#(a, Some(value)))
            Some(v) if v == value -> Ok(#(a, Some(value)))
            _ -> Error(Nil)
          }
        }),
      )(triples, [#(None, None)])
    contexts
    |> list.try_map(fn(c: #(Option(_), Option(_))) {
      case c.0 {
        Some(v0) ->
          case c.1 {
            Some(v1) -> Ok(#(v0, v1))
            None -> {
              io.debug(contexts)
              Error("query parameter not used")
            }
          }
        None -> {
          io.debug(contexts)
          Error("query parameter not used")
        }
      }
    })
  }
}

fn find5(
  query: fn(
    Match(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5)), t1),
    Match(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5)), t2),
    Match(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5)), t3),
    Match(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5)), t4),
    Match(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5)), t5),
  ) ->
    fn(
      List(#(Int, String, Value)),
      List(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5))),
    ) ->
      List(#(Option(t1), Option(t2), Option(t3), Option(t4), Option(t5))),
) {
  fn(triples) {
    let contexts =
      query(
        Variable(fn(state, value) {
          let #(a, b, c, d, e) = state

          case a {
            None -> Ok(#(Some(value), b, c, d, e))
            Some(v) if v == value -> Ok(#(Some(value), b, c, d, e))
            _ -> Error(Nil)
          }
        }),
        Variable(fn(state, value) {
          let #(a, b, c, d, e) = state
          case b {
            None -> Ok(#(a, Some(value), c, d, e))
            Some(v) if v == value -> Ok(#(a, Some(value), c, d, e))
            _ -> Error(Nil)
          }
        }),
        Variable(fn(state, value) {
          let #(a, b, c, d, e) = state
          case c {
            None -> Ok(#(a, b, Some(value), d, e))
            Some(v) if v == value -> Ok(#(a, b, Some(value), d, e))
            _ -> Error(Nil)
          }
        }),
        Variable(fn(state, value) {
          let #(a, b, c, d, e) = state
          case d {
            None -> Ok(#(a, b, c, Some(value), e))
            Some(v) if v == value -> Ok(#(a, b, c, Some(value), e))
            _ -> Error(Nil)
          }
        }),
        Variable(fn(state, value) {
          let #(a, b, c, d, e) = state
          case e {
            None -> Ok(#(a, b, c, d, Some(value)))
            Some(v) if v == value -> Ok(#(a, b, c, d, Some(value)))
            _ -> Error(Nil)
          }
        }),
      )(triples, [#(None, None, None, None, None)])
    contexts
    |> list.try_map(fn(
      c: #(Option(_), Option(_), Option(_), Option(_), Option(_)),
    ) {
      case c.0 {
        Some(v0) ->
          case c.1 {
            Some(v1) ->
              case c.2 {
                Some(v2) ->
                  case c.3 {
                    Some(v3) ->
                      case c.4 {
                        Some(v4) -> Ok(#(v0, v1, v2, v3, v4))
                        None -> {
                          io.debug(contexts)
                          Error("query parameter not used")
                        }
                      }
                    None -> {
                      io.debug(contexts)
                      Error("query parameter not used")
                    }
                  }
                None -> {
                  io.debug(contexts)
                  Error("query parameter not used")
                }
              }
            None -> {
              io.debug(contexts)
              Error("query parameter not used")
            }
          }
        None -> {
          io.debug(contexts)
          Error("query parameter not used")
        }
      }
    })
  }
}

fn int(match) {
  case match {
    Constant(value) -> Constant(I(value))
    Variable(f) ->
      Variable(fn(state, value) {
        case value {
          I(value) -> f(state, value)
          _ -> Error(Nil)
        }
      })
  }
}

fn string(match) {
  case match {
    Constant(value) -> Constant(S(value))
    Variable(f) ->
      Variable(fn(state, value) {
        case value {
          S(value) -> f(state, value)
          _ -> Error(Nil)
        }
      })
  }
}

// cant have unused vars in this approach or with nested calls to var because each builds a tuple in return tyupe
pub fn match_test() {
  let assert Ok(movies) = movies()
  // io.debug(movies())
  let q =
    find(fn(id) {
      use <- match(id, c("movie/year"), c(I(1987)))
      done()
    })

  io.debug(q(movies))

  let q =
    find2(fn(id, year) {
      use <- match(id, c("movie/title"), string(c("Alien")))
      use <- match(id, c("movie/year"), int(year))
      done()
    })
  io.debug(q(movies))

  let q =
    find2(fn(attr, value) {
      use <- match(c(200), attr, string(value))
      done()
    })
  io.debug(q(movies))

  let q =
    find2(fn(attr, value) {
      use <- match(c(200), attr, value)
      done()
    })
  io.debug(q(movies))

  let q =
    find5(fn(arnold, movie, movie_title, director, director_name) {
      use <- match(arnold, c("person/name"), string(c("Arnold Schwarzenegger")))
      use <- match(movie, c("movie/cast"), int(arnold))
      use <- match(movie, c("movie/title"), string(movie_title))
      //   note if don't use right type then no results
      use <- match(movie, c("movie/director"), int(director))
      use <- match(director, c("person/name"), string(director_name))
      done()
    })
  io.debug(q(movies))
  // done needs to take things that are already values
  // use filter(move, greater_than(5))
  // use assign(bob, value(foo)) foo needs to exist otherwise this isfull scale unification

  //     let q =
  //     find2(fn(id, year) {
  //       use <- match(id, c("movie/year"), c(I(1987)))
  //       done()
  //     })

  //   io.debug(q(movies))

  //   todo as "triiiples"
}
