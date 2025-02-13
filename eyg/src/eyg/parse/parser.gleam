import eyg/ir/tree as ir
import eyg/parse/token as t
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string

pub type Reason {
  UnexpectEnd
  UnexpectedToken(token: t.Token, position: Int)
}

pub type Span =
  #(Int, Int)

pub type Match =
  #(#(String, Span), Option(#(Span, #(String, Span))))

pub type Pattern {
  Assign(String)
  Destructure(List(Match))
}

fn do_destructure(tokens, acc) {
  case tokens {
    [#(t.RightBrace, _), ..rest] -> Ok(#(acc, rest))
    // can be spaces between colon and rest
    [#(t.Name(field), f), #(t.Colon, c), #(t.Name(var), v), ..rest] -> {
      let field = #(field, #(f, f + string.length(field)))
      let colon = #(c, c + 1)
      let var = #(var, #(v, v + string.length(var)))
      let acc = [#(field, Some(#(colon, var))), ..acc]

      case rest {
        [#(t.RightBrace, _), ..rest] -> Ok(#(acc, rest))
        [#(t.Comma, _), ..rest] -> do_destructure(rest, acc)
        _ -> fail(rest)
      }
    }
    [#(t.Name(field), start), ..rest] -> {
      let field = #(field, #(start, start + string.length(field)))
      let acc = [#(field, None), ..acc]
      case rest {
        [#(t.RightBrace, _), ..rest] -> Ok(#(acc, rest))
        [#(t.Comma, _), ..rest] -> do_destructure(rest, acc)
        _ -> fail(rest)
      }
    }
    _ -> fail(tokens)
  }
}

fn one_pattern(tokens) {
  case tokens {
    [#(t.Name(label), _), ..rest] -> Ok(#(Assign(label), rest))
    [#(t.LeftBrace, _), ..rest] -> {
      use #(matches, rest) <- try(do_destructure(rest, []))
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

pub fn destructured(matches: List(Match), term: #(ir.Expression(_), Span)) {
  list.fold(matches, term, fn(acc, pair) {
    let #(field, assign) = pair
    let #(field, fspan) = field
    let #(cspan, #(var, _vspan)) = case assign {
      Some(#(cspan, #(var, vspan))) -> #(cspan, #(var, vspan))
      None -> #(fspan, #(field, fspan))
    }
    let aspan = #(fspan.0, cspan.1)
    let lspan = #(fspan.0, term.1.1)
    #(
      ir.Let(
        var,
        #(
          ir.Apply(#(ir.Select(field), fspan), #(ir.Variable("$"), cspan)),
          aspan,
        ),
        acc,
      ),
      lspan,
    )
  })
}

pub fn block(tokens) {
  use #(#(token, start), rest) <- try(pop(tokens))
  case token {
    t.Let -> {
      use #(pattern, rest) <- try(one_pattern(rest))
      use rest <- try(case rest {
        [#(t.Equal, _), ..rest] -> Ok(rest)
        _ -> fail(rest)
      })
      use #(value, rest) <- try(expression(rest))
      case block(rest) {
        Ok(#(then, rest)) -> {
          let #(_, #(_start, end)) = then
          let span = #(start, end)
          let exp = case pattern {
            Assign(label) -> #(ir.Let(label, value, then), span)
            Destructure(matches) -> #(
              ir.Let("$", value, destructured(matches, then)),
              span,
            )
          }
          Ok(#(exp, rest))
        }
        Error(UnexpectEnd) -> {
          let span = #(start, start)
          let then = #(ir.Vacant, #(0, 0))
          let exp = case pattern {
            Assign(label) -> #(ir.Let(label, value, then), span)
            Destructure(matches) -> #(
              ir.Let("$", value, destructured(matches, then)),
              span,
            )
          }
          Ok(#(exp, rest))
        }
        Error(other) -> Error(other)
      }
    }
    _ -> {
      expression(tokens)
    }
  }
}

pub fn expression(tokens) {
  use #(#(token, start), rest) <- try(pop(tokens))

  use #(exp, rest) <- try(case token {
    t.Name(label) -> {
      let span = #(start, start + string.length(label))
      Ok(#(#(ir.Variable(label), span), rest))
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
        Assign(label) -> #(ir.Let(label, value, then), span)
        Destructure(matches) -> #(
          ir.Let("$", value, destructured(matches, then)),
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
            Assign(label) -> #(ir.Lambda(label, body), span)
            Destructure(matches) -> #(
              ir.Lambda("$", destructured(matches, body)),
              span,
            )
          }
        })

      Ok(#(exp, rest))
    }
    t.Integer(raw) -> {
      let assert Ok(value) = int.parse(raw)
      let span = #(start, start + string.length(raw))
      Ok(#(#(ir.Integer(value), span), rest))
    }
    t.Minus -> {
      use #(#(next, from), rest) <- try(pop(rest))
      case next {
        t.Integer(raw) -> {
          let assert Ok(value) = int.parse(raw)
          let span = #(start, from + string.length(raw))
          Ok(#(#(ir.Integer(-1 * value), span), rest))
        }
        _ -> Error(UnexpectedToken(token, start))
      }
    }
    t.String(value) -> {
      let span = #(start, start + string.length(value) + 2)
      Ok(#(#(ir.String(value), span), rest))
    }
    t.LeftSquare -> do_list(rest, start, [])
    t.LeftBrace -> do_record(rest, start, [])
    t.Uppername(label) -> {
      let span = #(start, start + string.length(label))

      Ok(#(#(ir.Tag(label), span), rest))
    }
    t.Match -> {
      case rest {
        [#(t.LeftBrace, _), ..rest] -> {
          use #(exp, _, rest) <- try(clauses(rest, start))
          Ok(#(exp, rest))
        }
        _ -> {
          use #(subject, rest) <- try(expression(rest))
          case rest {
            [#(t.LeftBrace, inner), ..rest] -> {
              use #(exp, end, rest) <- try(clauses(rest, inner))
              let span = #(start, end)
              Ok(#(#(ir.Apply(exp, subject), span), rest))
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
          Ok(#(#(ir.Perform(label), span), rest))
        }
        _ -> fail(rest)
      }
    t.Handle ->
      case rest {
        [#(t.Uppername(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(ir.Handle(label), span), rest))
        }
        _ -> fail(rest)
      }
    t.Bang ->
      case rest {
        [#(t.Name(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(ir.Builtin(label), span), rest))
        }
        _ -> fail(rest)
      }
    t.Hash ->
      case rest {
        [#(t.Name(label), end), ..rest] -> {
          let span = #(start, end + string.length(label))
          Ok(#(#(ir.Reference(label), span), rest))
        }
        _ -> fail(rest)
      }

    _ -> Error(UnexpectedToken(token, start))
  })

  after_expression(exp, rest)
}

fn after_expression(exp, rest) {
  case rest {
    [#(t.LeftParen, _start), ..rest] -> {
      use #(arg, rest) <- try(expression(rest))
      use #(args, _end, rest) <- try(do_args(rest, [arg]))
      let args = list.reverse(args)
      let exp =
        list.fold(args, exp, fn(acc, arg) {
          let #(_, #(start, _)) = acc
          let #(_, #(_, end)) = arg
          #(ir.Apply(acc, arg), #(start, end + 1))
        })
      after_expression(exp, rest)
    }
    [#(t.Dot, dot_at), #(t.Name(label), name_at), ..rest] -> {
      let end = name_at + string.length(label)
      let select = #(ir.Select(label), #(dot_at, end))
      let #(_value, #(start, _)) = exp
      let span = #(start, end)
      after_expression(#(ir.Apply(select, exp), span), rest)
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
fn do_list(tokens, start, acc) {
  // use #(t,rest)
  case tokens {
    [] -> Error(UnexpectEnd)
    [#(t.RightSquare, end), ..rest] -> {
      let span = #(start, end + 1)
      Ok(#(build_list(acc, #(ir.Tail, span)), rest))
    }
    _ -> {
      use #(item, rest) <- try(expression(tokens))
      let acc = [#(start, item), ..acc]
      case rest {
        [#(t.Comma, _), #(t.DotDot, _), ..rest] -> {
          use #(tail, rest) <- try(expression(rest))
          use #(#(token, start), rest) <- try(pop(rest))
          case token {
            t.RightSquare -> Ok(#(build_list(acc, tail), rest))
            _ -> Error(UnexpectedToken(token, start))
          }
        }
        [#(t.Comma, start), ..rest] -> do_list(rest, start, acc)

        [#(t.RightSquare, start), ..rest] -> {
          let span = #(start, start + 1)
          Ok(#(build_list(acc, #(ir.Tail, span)), rest))
        }
        [#(t, start), ..] -> Error(UnexpectedToken(t, start))
        [] -> Error(UnexpectEnd)
      }
    }
  }
}

pub fn build_list(reversed, acc) {
  case reversed {
    [#(from, item), ..rest] -> {
      let #(_, #(_, c)) = acc
      let #(_, #(_, b)) = item

      build_list(
        rest,
        #(
          ir.Apply(
            #(ir.Apply(#(ir.Cons, #(from, from + 1)), item), #(from, b)),
            acc,
          ),
          #(from, c),
        ),
      )
    }
    [] -> acc
  }
}

fn do_record(rest, start, acc) {
  use #(#(token, kstart), rest) <- try(pop(rest))
  case token {
    t.RightBrace -> Ok(#(#(ir.Empty, #(start, kstart + 1)), rest))
    t.Name(label) -> {
      use #(#(token, next), rest) <- try(pop(rest))
      case token {
        t.Colon -> {
          use #(value, rest) <- try(expression(rest))
          let acc = [#(#(start, next + 1), label, value), ..acc]

          // replace above with field function

          case rest {
            [#(t.Comma, start), ..rest] -> do_record(rest, start, acc)

            [#(t.RightBrace, start), ..rest] -> {
              let span = #(start, start + 1)
              Ok(#(build_record(acc, #(ir.Empty, span)), rest))
            }
            _ -> fail(rest)
          }
        }
        t.Comma -> {
          let acc = [
            #(
              // kstart is the label starting position
              #(start, kstart + string.length(label)),
              label,
              #(ir.Variable(label), #(kstart, kstart + string.length(label))),
            ),
            ..acc
          ]
          do_record(rest, next, acc)
        }
        t.RightBrace -> {
          let acc = [
            #(
              #(start, kstart + string.length(label)),
              label,
              #(ir.Variable(label), #(kstart, kstart + string.length(label))),
            ),
            ..acc
          ]
          let span = #(next, next + 1)

          Ok(#(build_record(acc, #(ir.Empty, span)), rest))
        }
        _ -> Error(UnexpectedToken(token, start))
      }
    }
    t.DotDot -> {
      use #(value, rest) <- try(expression(rest))
      use #(#(token, start), rest) <- try(pop(rest))
      use rest <- try(case token {
        // could include right brace in the tail for editing
        t.RightBrace -> Ok(rest)
        _ -> Error(UnexpectedToken(token, start))
      })
      Ok(#(build_overwrite(acc, value), rest))
    }
    _ -> Error(UnexpectedToken(token, start))
  }
}

pub fn build_record(reversed, acc) {
  case reversed {
    [#(span, label, item), ..rest] -> {
      let #(_, #(_, c)) = acc
      let #(_, #(_, b)) = item
      let #(a, _) = span

      build_record(
        rest,
        #(
          ir.Apply(#(ir.Apply(#(ir.Extend(label), span), item), #(a, b)), acc),
          #(a, c),
        ),
      )
    }
    [] -> acc
  }
}

pub fn build_overwrite(reversed, acc) {
  case reversed {
    [#(span, label, item), ..rest] -> {
      let #(_, #(_, c)) = acc
      let #(_, #(_, b)) = item
      let #(a, _) = span

      build_overwrite(
        rest,
        #(
          ir.Apply(
            #(ir.Apply(#(ir.Overwrite(label), span), item), #(a, b)),
            acc,
          ),
          #(a, c),
        ),
      )
    }
    [] -> acc
  }
}

fn clauses(tokens, start) {
  use #(clauses, tail, rest) <- try(do_clauses(tokens, start, []))
  let #(_, #(_, end)) = tail
  let exp =
    list.fold(clauses, tail, fn(exp, clause) {
      let #(start, label, cspan, branch) = clause
      let case_ = #(ir.Case(label), cspan)
      let #(_, #(_, branch_end)) = branch
      let inner = #(ir.Apply(case_, branch), #(cspan.0, branch_end))
      let #(_, #(_, final)) = tail
      #(ir.Apply(inner, exp), #(start, final))
    })
  Ok(#(exp, end, rest))
}

fn do_clauses(tokens, start, acc) {
  use #(#(token, clause), rest) <- try(pop(tokens))
  case token {
    t.RightBrace -> Ok(#(acc, #(ir.NoCases, #(start, clause + 1)), rest))
    t.Uppername(label) -> {
      use #(branch, rest) <- try(expression(rest))
      let acc = [
        #(start, label, #(clause, clause + string.length(label)), branch),
        ..acc
      ]
      // peek
      let assert [#(_, last), ..] = rest
      do_clauses(rest, last, acc)
    }
    // Open function is parens that are treated as a call to the line above
    // uppername can never be a tag expression because return from Tag is not another fn
    t.Bar -> {
      use #(#(otherwise, span), rest) <- try(expression(rest))
      case rest {
        [#(t.RightBrace, _), ..rest] -> Ok(#(acc, #(otherwise, span), rest))
        _ -> fail(rest)
      }
    }
    _ -> Error(UnexpectedToken(token, clause))
  }
}

fn pop(tokens) {
  case tokens {
    [t, ..rest] -> Ok(#(t, rest))
    [] -> Error(UnexpectEnd)
  }
}
