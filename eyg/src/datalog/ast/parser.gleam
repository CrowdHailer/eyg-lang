import gleam/io
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import datalog/ast

pub fn parse(raw) {
  use tokens <- result.then(do_tokenise([], raw))
  //   io.debug(tokens)
  do_read_constraints([], tokens)
}

fn do_read_constraints(constraints, tokens) {
  case tokens {
    [] -> Ok(list.reverse(constraints))
    [Label(relation), LeftRound, ..tokens] -> {
      use #(terms, tokens) <- result.then(do_read_terms([], tokens))
      use #(c, tokens) <- result.then(case tokens {
        [Binding, ..tokens] -> {
          use #(body, tokens) <- result.then(do_read_body([], tokens))
          Ok(#(ast.Constraint(ast.Atom(relation, terms), body), tokens))
        }
        [Stop, ..tokens] ->
          Ok(#(ast.Constraint(ast.Atom(relation, terms), []), tokens))
      })
      do_read_constraints([c, ..constraints], tokens)
    }
    _ -> {
      io.debug(tokens)
      panic as "other"
    }
  }
}

fn do_read_body(atoms, tokens) {
  case tokens {
    [Stop, ..tokens] -> Ok(#(list.reverse(atoms), tokens))
    [Label(relation), LeftRound, ..tokens] -> {
      use #(terms, tokens) <- result.then(do_read_terms([], tokens))
      let atom = ast.Atom(relation, terms)
      let atoms = [#(False, atom), ..atoms]
      case tokens {
        [Stop, ..tokens] -> Ok(#(list.reverse(atoms), tokens))
        [Comma, ..tokens] -> do_read_body(atoms, tokens)
        _ -> {
          io.debug(tokens)
          panic as "other"
        }
      }
    }
    [Not, Label(relation), LeftRound, ..tokens] -> {
      use #(terms, tokens) <- result.then(do_read_terms([], tokens))
      let atom = ast.Atom(relation, terms)
      let atoms = [#(True, atom), ..atoms]
      case tokens {
        [Stop, ..tokens] -> Ok(#(list.reverse(atoms), tokens))
        [Comma, ..tokens] -> do_read_body(atoms, tokens)
        _ -> {
          io.debug(tokens)
          panic as "other"
        }
      }
    }
    _ -> {
      io.debug(tokens)
      panic as "other"
    }
  }
}

fn do_read_terms(terms, tokens) {
  case tokens {
    [RightRound, ..tokens] -> Ok(#(list.reverse(terms), tokens))
    [Literal(l), Comma, ..tokens] ->
      do_read_terms([ast.Literal(l), ..terms], tokens)
    [Literal(l), RightRound, ..tokens] ->
      Ok(#(list.reverse([ast.Literal(l), ..terms]), tokens))
    [Label(l), Comma, ..tokens] ->
      do_read_terms([ast.Variable(l), ..terms], tokens)
    [Label(l), RightRound, ..tokens] ->
      Ok(#(list.reverse([ast.Variable(l), ..terms]), tokens))
    _ -> {
      io.debug(tokens)
      panic
    }
  }
}

type Token {
  Label(String)
  Not
  Comma
  Stop
  Binding
  LeftRound
  RightRound
  Literal(ast.Value)
}

const letters = [
  "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
  "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f",
  "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v",
  "w", "x", "y", "z",
]

const digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

fn do_tokenise(tokens, rest: String) {
  case rest {
    "" -> Ok(list.reverse(tokens))
    " " <> rest | "\t" <> rest | "\n" <> rest | "\r" <> rest ->
      do_tokenise(tokens, rest)
    ":-" <> rest -> do_tokenise([Binding, ..tokens], rest)
    "," <> rest -> do_tokenise([Comma, ..tokens], rest)
    "." <> rest -> do_tokenise([Stop, ..tokens], rest)
    "not" <> rest -> do_tokenise([Not, ..tokens], rest)
    "(" <> rest -> do_tokenise([LeftRound, ..tokens], rest)
    ")" <> rest -> do_tokenise([RightRound, ..tokens], rest)
    "true" <> rest -> do_tokenise([Literal(ast.B(True)), ..tokens], rest)
    "false" <> rest -> do_tokenise([Literal(ast.B(False)), ..tokens], rest)
    "\"" <> rest -> {
      use #(value, rest) <- result.then(do_string([], rest))
      do_tokenise([Literal(ast.S(value)), ..tokens], rest)
    }
    _ -> {
      use #(ch, rest) <- result.then(string.pop_grapheme(rest))
      case list.contains(letters, ch) {
        True -> {
          use #(label, rest) <- result.then(do_label([ch], rest))
          do_tokenise([Label(label), ..tokens], rest)
        }
        False ->
          case list.contains(digits, ch) {
            True -> {
              use #(raw, rest) <- result.then(do_digit([ch], rest))
              let assert Ok(number) = int.parse(raw)
              do_tokenise([Literal(ast.I(number)), ..tokens], rest)
            }
            False -> Error(Nil)
          }
      }
    }
  }
}

fn do_label(gathered, buffer) {
  case string.pop_grapheme(buffer) {
    Error(Nil) -> Ok(#(string.concat(list.reverse(gathered)), buffer))
    Ok(#(ch, rest)) ->
      case list.contains(letters, ch) {
        True -> do_label([ch, ..gathered], rest)
        False -> Ok(#(string.concat(list.reverse(gathered)), buffer))
      }
  }
}

fn do_digit(gathered, buffer) {
  case string.pop_grapheme(buffer) {
    Error(Nil) -> Ok(#(string.concat(list.reverse(gathered)), buffer))
    Ok(#(ch, rest)) ->
      case list.contains(digits, ch) {
        True -> do_digit([ch, ..gathered], rest)
        False -> Ok(#(string.concat(list.reverse(gathered)), buffer))
      }
  }
}

fn do_string(gathered, rest) {
  case rest {
    "" -> Error(Nil)
    "\"" <> rest -> Ok(#(string.concat(list.reverse(gathered)), rest))
    "\\\\" <> rest -> do_string(["\\", ..gathered], rest)
    "\\\"" <> rest -> do_string(["\"", ..gathered], rest)
    _ -> {
      let assert Ok(#(ch, rest)) = string.pop_grapheme(rest)
      do_string([ch, ..gathered], rest)
    }
  }
}
