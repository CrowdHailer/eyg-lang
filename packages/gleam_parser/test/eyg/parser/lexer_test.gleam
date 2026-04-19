import eyg/parser/lexer
import eyg/parser/token as t
import gleeunit/should

pub fn grouping_test() {
  "()"
  |> lexer.lex
  |> should.equal([#(t.LeftParen, 0), #(t.RightParen, 1)])
  "{}"
  |> lexer.lex
  |> should.equal([#(t.LeftBrace, 0), #(t.RightBrace, 1)])
  "[]"
  |> lexer.lex
  |> should.equal([#(t.LeftSquare, 0), #(t.RightSquare, 1)])
}

pub fn punctuation_test() {
  "=->,.:!..-|#@"
  |> lexer.lex
  |> should.equal([
    #(t.Equal, 0),
    #(t.RightArrow, 1),
    #(t.Comma, 3),
    #(t.Dot, 4),
    #(t.Colon, 5),
    #(t.Bang, 6),
    #(t.DotDot, 7),
    #(t.Minus, 9),
    #(t.Bar, 10),
    #(t.Hash, 11),
    #(t.At, 12),
  ])
}

pub fn keyword_test() {
  "let match perform deep handle import"
  |> lexer.lex
  |> should.equal([
    #(t.Let, 0),
    #(t.Whitespace(" "), 3),
    #(t.Match, 4),
    #(t.Whitespace(" "), 9),
    #(t.Perform, 10),
    #(t.Whitespace(" "), 17),
    #(t.Deep, 18),
    #(t.Whitespace(" "), 22),
    #(t.Handle, 23),
    #(t.Whitespace(" "), 29),
    #(t.Import, 30),
  ])
}

pub fn string_test() {
  "\"\"\"hello\"\"\\\\\""
  |> lexer.lex
  |> should.equal([
    #(t.String(""), 0),
    #(t.String("hello"), 2),
    #(t.String("\\"), 9),
  ])
}

pub fn number_test() {
  "1 01 1000 -5"
  |> lexer.lex
  |> should.equal([
    #(t.Integer("1"), 0),
    #(t.Whitespace(" "), 1),
    #(t.Integer("01"), 2),
    #(t.Whitespace(" "), 4),
    #(t.Integer("1000"), 5),
    #(t.Whitespace(" "), 9),
    #(t.Minus, 10),
    #(t.Integer("5"), 11),
  ])
}

pub fn name_test() {
  "alice x1 _"
  |> lexer.lex
  |> should.equal([
    #(t.Name("alice"), 0),
    #(t.Whitespace(" "), 5),
    #(t.Name("x1"), 6),
    #(t.Whitespace(" "), 8),
    #(t.Name("_"), 9),
  ])
}

pub fn uppername_test() {
  "Ok MyThing A1"
  |> lexer.lex
  |> should.equal([
    #(t.Uppername("Ok"), 0),
    #(t.Whitespace(" "), 2),
    #(t.Uppername("MyThing"), 3),
    #(t.Whitespace(" "), 10),
    #(t.Uppername("A1"), 11),
  ])
}

pub fn call_test() {
  "alice(1)"
  |> lexer.lex
  |> should.equal([
    #(t.Name("alice"), 0),
    #(t.LeftParen, 5),
    #(t.Integer("1"), 6),
    #(t.RightParen, 7),
  ])

  "Ok(1)"
  |> lexer.lex
  |> should.equal([
    #(t.Uppername("Ok"), 0),
    #(t.LeftParen, 2),
    #(t.Integer("1"), 3),
    #(t.RightParen, 4),
  ])
}

pub fn unexpected_charachter_test() {
  "`"
  |> lexer.lex
  |> should.equal([#(t.UnexpectedGrapheme("`"), 0)])
}

pub fn unterminated_string_test() {
  "\"ab"
  |> lexer.lex
  |> should.equal([#(t.UnterminatedString("ab"), 0)])

  "\"xy\\"
  |> lexer.lex
  |> should.equal([#(t.UnterminatedString("xy\\"), 0)])
}

pub fn invalid_escape_test() {
  "\"\\q\""
  |> lexer.lex
  |> should.equal([#(t.InvalidEscape("\\q\""), 0)])
}

pub fn name_with_keyword_prefix_test() {
  "letter matching performance deeper handler imported"
  |> lexer.lex
  |> should.equal([
    #(t.Name("letter"), 0),
    #(t.Whitespace(" "), 6),
    #(t.Name("matching"), 7),
    #(t.Whitespace(" "), 15),
    #(t.Name("performance"), 16),
    #(t.Whitespace(" "), 27),
    #(t.Name("deeper"), 28),
    #(t.Whitespace(" "), 34),
    #(t.Name("handler"), 35),
    #(t.Whitespace(" "), 42),
    #(t.Name("imported"), 43),
  ])
}

pub fn name_with_keyword_and_underscore_test() {
  "let_value match_arm perform_side_effect"
  |> lexer.lex
  |> should.equal([
    #(t.Name("let_value"), 0),
    #(t.Whitespace(" "), 9),
    #(t.Name("match_arm"), 10),
    #(t.Whitespace(" "), 19),
    #(t.Name("perform_side_effect"), 20),
  ])
}

pub fn name_with_keyword_and_digits_test() {
  "let1 match2"
  |> lexer.lex
  |> should.equal([
    #(t.Name("let1"), 0),
    #(t.Whitespace(" "), 4),
    #(t.Name("match2"), 5),
  ])
}
