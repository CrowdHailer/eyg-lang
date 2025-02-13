import eyg/ir/tree as ir
import eyg/parse/lexer
import eyg/parse/parser
import eyg/parse/token
import gleam/option.{None, Some}
import gleam/result

pub fn from_string(src) {
  src
  |> lexer.lex()
  |> token.drop_whitespace()
  |> parser.expression()
}

pub fn all_from_string(src) {
  use #(source, remaining) <- result.try(from_string(src))
  case remaining {
    [] -> Ok(source)
    [#(token, at), ..] -> Error(parser.UnexpectedToken(token, at))
  }
}

pub fn block_from_string(src) {
  let parsed =
    src
    |> lexer.lex()
    |> token.drop_whitespace()
    |> parser.block()
  case parsed {
    Ok(#(exp, left)) -> Ok(#(do_gather(exp, []), left))
    Error(reason) -> Error(reason)
  }
}

fn do_gather(exp, acc) {
  let #(exp, span) = exp
  case exp {
    ir.Let(label, value, then) ->
      do_gather(then, [#(label, value, span), ..acc])
    ir.Vacant -> #(acc, None)
    _ -> #(acc, Some(#(exp, span)))
  }
}
