import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/string
import eyg/parse/expression as e
import eyg/parse/token as t
import gleam/io

pub type Reason {
  UnexpectEnd
  UnexpectedToken(token: t.Token, position: Int)
}

pub fn parse(tokens) {
  case expression(tokens) {
    Ok(#(e, [])) -> Ok(e)
    Ok(#(_, leftover)) -> {
      io.debug(leftover)
      panic
    }
    Error(reason) -> Error(reason)
  }
}

pub type Pattern {
  Assign(String)
  Destructure(List(#(String, String, #(Int, Int))))
}

fn one_pattern(tokens) {
  case tokens {
    [#(t.Name(label), _), ..rest] -> Ok(#(Assign(label), rest))
    [#(t.LeftBrace, _), ..rest] -> {
      use #(matches, rest) <- try(do_pattern(rest, []))
      Ok(#(Destructure(matches), rest))
    }
    _ -> fail(tokens)
  }
}

pub fn do_patterns(tokens, acc) {
  use #(pattern, tokens) <- try(one_pattern(tokens))
  let acc = [pattern, ..acc]
  use #(#(next, start), rest) <- try(pop(tokens))
  case next {
    t.Comma -> do_patterns(rest, acc)
    t.RightParen -> Ok(#(acc, rest))
    _ -> Error(UnexpectedToken(next, start))
  }
}

pub fn expression(tokens) {
  use #(#(token, start), rest) <- try(pop(tokens))

  use #(exp, rest) <- try(case token {
    t.Name(label) -> {
      let span = #(start, start + string.length(label))
      Ok(#(#(e.Variable(label), span), rest))
    }
    t.Let -> {
      use #(pattern, rest) <- try(one_pattern(rest))
      use rest <- try(case rest {
        [#(t.Equal, _), ..rest] -> Ok(rest)
        _ -> fail(rest)
      })
      use #(value, rest) <- try(expression(rest))
      use #(then, rest) <- try(expression(rest))
      let #(_, #(_start, end)) = then
      let span = #(start, end)
      let exp = case pattern {
        Assign(label) -> #(e.Let(label, value, then), span)
        Destructure(matches) -> #(
          e.Let(
            "$",
            value,
            list.fold(matches, then, fn(acc, pair) {
              let #(field, var, span) = pair
              #(
                e.Let(
                  var,
                  #(
                    e.Apply(#(e.Select(field), span), #(e.Variable("$"), span)),
                    span,
                  ),
                  acc,
                ),
                span,
              )
            }),
          ),
          span,
        )
      }
      Ok(#(exp, rest))
    }
    t.LeftParen -> {
      use #(patterns_reversed, rest) <- try(do_patterns(rest, []))
      use rest <- try(case rest {
        [#(t.RightArrow, _), #(t.LeftBrace, _), ..rest] -> Ok(rest)
        _ -> fail(rest)
      })
      use #(body, rest) <- try(expression(rest))
      use #(rest, end) <- try(case rest {
        [#(t.RightBrace, end), ..rest] -> Ok(#(rest, end))
        _ -> fail(rest)
      })
      let span = #(start, end + 1)
      let exp =
        list.fold(patterns_reversed, body, fn(body, pattern) {
          case pattern {
            Assign(label) -> #(e.Lambda(label, body), span)
            Destructure(matches) -> #(
              e.Lambda(
                "$",
                list.fold(matches, body, fn(acc, pair) {
                  let #(field, var, span) = pair
                  #(
                    e.Let(
                      var,
                      #(
                        e.Apply(#(e.Select(field), span), #(
                          e.Variable("$"),
                          span,
                        )),
                        span,
                      ),
                      acc,
                    ),
                    span,
                  )
                }),
              ),
              span,
            )
          }
        })

      Ok(#(exp, rest))
    }
    t.Integer(raw) -> {
      let assert Ok(value) = int.parse(raw)
      let span = #(start, start + string.length(raw))
      Ok(#(#(e.Integer(value), span), rest))
    }
    t.String(value) -> {
      let span = #(start, start + string.length(value) + 2)
      Ok(#(#(e.Str(value), span), rest))
    }
    t.LeftSquare -> do_list(rest, [])
    t.LeftBrace -> do_record(rest, [])
    t.Uppername(label) -> {
      let span = #(start, start + string.length(label))

      Ok(#(#(e.Tag(label), span), rest))
    }
    t.Match -> {
      case rest {
        [#(t.LeftBrace, _), ..rest] -> {
          use #(exp, _, rest) <- try(clauses(rest))
          Ok(#(exp, rest))
        }
        _ -> {
          use #(subject, rest) <- try(expression(rest))
          case rest {
            [#(t.LeftBrace, _), ..rest] -> {
              use #(exp, end, rest) <- try(clauses(rest))
              let span = #(start, end)
              Ok(#(#(e.Apply(exp, subject), span), rest))
            }
            _ -> fail(rest)
          }
        }
      }
    }
    t.Perform ->
      case rest {
        [#(t.Uppername(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(e.Perform(label), span), rest))
        }
        _ -> fail(rest)
      }
    t.Handle ->
      case rest {
        [#(t.Uppername(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(e.Handle(label), span), rest))
        }
        _ -> fail(rest)
      }
    t.Shallow ->
      case rest {
        [#(t.Uppername(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(e.Shallow(label), span), rest))
        }
        _ -> fail(rest)
      }
    t.Bang ->
      case rest {
        [#(t.Name(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(e.Builtin(label), span), rest))
        }
        _ -> fail(rest)
      }
    _ -> Error(UnexpectedToken(token, start))
  })

  after_expression(exp, rest)
}

fn do_pattern(tokens, acc) {
  case tokens {
    [#(t.RightBrace, _), ..rest] -> Ok(#(acc, rest))
    [#(t.Name(field), start), #(t.Colon, _), #(t.Name(var), end), ..rest] -> {
      let span = #(start, end + string.length(var))
      let acc = [#(field, var, span), ..acc]
      case rest {
        [#(t.RightBrace, _), ..rest] -> Ok(#(acc, rest))
        [#(t.Comma, _), ..rest] -> do_pattern(rest, acc)
        _ -> fail(rest)
      }
    }
    [#(t.Name(field), start), ..rest] -> {
      let span = #(start, start + string.length(field))
      let acc = [#(field, field, span), ..acc]
      case rest {
        [#(t.RightBrace, _), ..rest] -> Ok(#(acc, rest))
        [#(t.Comma, _), ..rest] -> do_pattern(rest, acc)
        _ -> fail(rest)
      }
    }
    _ -> fail(tokens)
  }
}

fn after_expression(exp, rest) {
  case rest {
    // This clause is backtracing even if only one node, is it worth having
    // [#(t.RightArrow, _), ..rest] -> {
    //   use #(body, rest) <- try(expression(rest))
    //   case exp {
    //     e.Variable(label) -> Ok(#(e.Lambda(label, body), rest))
    //   }
    // }
    [#(t.LeftParen, start), ..rest] -> {
      use #(arg, rest) <- try(expression(rest))
      use #(args, end, rest) <- try(do_args(rest, [arg]))
      let args = list.reverse(args)
      let exp =
        list.fold(args, exp, fn(acc, arg) {
          let #(_, #(start, _)) = acc
          let #(_, #(_, end)) = arg
          #(e.Apply(acc, arg), #(start, end + 1))
        })
      after_expression(exp, rest)
    }
    [#(t.Dot, dot_at), #(t.Name(label), name_at), ..rest] -> {
      let end = name_at + string.length(label)
      let select = #(e.Select(label), #(dot_at, end))
      let #(_value, #(start, _)) = exp
      let span = #(start, end)
      after_expression(#(e.Apply(select, exp), span), rest)
    }
    _ -> Ok(#(exp, rest))
  }
}

fn do_args(tokens, acc) {
  case tokens {
    [#(t.RightParen, end), ..rest] -> Ok(#(acc, end + 1, rest))
    [#(t.Comma, _), ..rest] -> {
      use #(arg, rest) <- try(expression(rest))
      do_args(rest, [arg, ..acc])
    }
    _ -> fail(tokens)
  }
}

fn fail(tokens) {
  case tokens {
    [] -> Error(UnexpectEnd)
    [#(t, start), ..] -> Error(UnexpectedToken(t, start))
  }
}

// this supports trailing comma
fn do_list(tokens, acc) {
  // use #(t,rest)
  case tokens {
    [] -> Error(UnexpectEnd)
    [#(t.RightSquare, start), ..rest] -> {
      let span = #(start, start + 1)
      Ok(#(build_list(acc, #(e.Tail, span)), rest))
    }
    _ -> {
      use #(item, rest) <- try(expression(tokens))
      let acc = [item, ..acc]
      case rest {
        [#(t.Comma, _), #(t.DotDot, _), ..rest] -> {
          use #(tail, rest) <- try(expression(rest))
          use #(#(token, start), rest) <- try(pop(rest))
          case token {
            t.RightSquare -> Ok(#(build_list(acc, tail), rest))
            _ -> Error(UnexpectedToken(token, start))
          }
        }
        [#(t.Comma, _), ..rest] -> do_list(rest, acc)

        [#(t.RightSquare, start), ..rest] -> {
          let span = #(start, start + 1)
          Ok(#(build_list(acc, #(e.Tail, span)), rest))
        }
        [#(t, start), ..] -> Error(UnexpectedToken(t, start))
        [] -> Error(UnexpectEnd)
      }
    }
  }
}

pub fn build_list(reversed, acc) {
  case reversed {
    [item, ..rest] -> {
      let #(_, #(_, c)) = acc
      let #(_, #(a, b)) = item

      build_list(
        rest,
        #(e.Apply(#(e.Apply(#(e.Cons, #(a, a)), item), #(a, b)), acc), #(a, c)),
      )
    }
    [] -> acc
  }
}

fn do_record(rest, acc) {
  use #(#(token, start), rest) <- try(pop(rest))
  case token {
    t.RightBrace -> Ok(#(#(e.Empty, #(start, start + 1)), rest))
    t.Name(label) -> {
      use #(#(token, start), rest) <- try(pop(rest))
      case token {
        t.Colon -> {
          use #(value, rest) <- try(expression(rest))
          let acc = [#(label, value), ..acc]

          // replace above with field function

          case rest {
            [#(t.Comma, _), ..rest] -> do_record(rest, acc)

            [#(t.RightBrace, _), ..rest] ->
              Ok(#(build_record(acc, e.Empty), rest))
            _ -> fail(rest)
          }
        }
        t.Comma -> {
          let acc = [
            #(
              label,
              #(e.Variable(label), #(start, start + string.length(label))),
            ),
            ..acc
          ]
          do_record(rest, acc)
        }
        t.RightBrace -> {
          let acc = [
            #(
              label,
              #(e.Variable(label), #(start, start + string.length(label))),
            ),
            ..acc
          ]
          Ok(#(build_record(acc, e.Empty), rest))
        }
        _ -> Error(UnexpectedToken(token, start))
      }
    }
    t.DotDot -> {
      use #(value, rest) <- try(expression(rest))
      use #(#(token, start), rest) <- try(pop(rest))
      use rest <- try(case token {
        t.RightBrace -> Ok(rest)
        _ -> Error(UnexpectedToken(token, start))
      })
      Ok(#(build_overwrite(acc, value), rest))
    }
    _ -> Error(UnexpectedToken(token, start))
  }
}

fn build_record(_, _) {
  todo as "build record"
}

fn build_overwrite(_, _) {
  todo as "build record"
}

fn clauses(tokens) {
  use #(clauses, tail, rest) <- try(do_clauses(tokens, []))
  let #(_, #(_, end)) = tail
  let exp =
    list.fold(clauses, tail, fn(exp, clause) {
      let #(label, start, branch) = clause
      let case_ = #(e.Case(label), #(start, start + string.length(label)))
      let #(_, #(_, branch_end)) = branch
      let inner = #(e.Apply(case_, branch), #(start, branch_end))
      let #(_, #(_, final)) = tail
      #(e.Apply(inner, exp), #(start, final))
    })
  Ok(#(exp, end, rest))
}

fn do_clauses(tokens, acc) {
  use #(#(token, start), rest) <- try(pop(tokens))
  case token {
    t.RightBrace -> Ok(#(acc, #(e.NoCases, #(start, start + 1)), rest))
    t.Uppername(label) -> {
      use #(branch, rest) <- try(expression(rest))
      let acc = [#(label, start, branch), ..acc]
      do_clauses(rest, acc)
    }
    _ -> Error(UnexpectedToken(token, start))
  }
}

fn pop(tokens) {
  case tokens {
    [t, ..rest] -> Ok(#(t, rest))
    [] -> Error(UnexpectEnd)
  }
}
