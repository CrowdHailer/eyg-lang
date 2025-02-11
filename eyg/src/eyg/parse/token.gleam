import gleam/list

pub type Token {
  Whitespace(String)
  Name(String)
  Uppername(String)
  Integer(String)
  String(String)
  Let
  Match
  Perform
  Deep
  Handle
  // Having keyword token instead of using name prevents keywords used as names
  Equal
  Comma
  DotDot
  Dot
  Colon
  RightArrow
  Minus
  Bang
  Bar
  Hash

  LeftParen
  RightParen
  LeftBrace
  RightBrace
  LeftSquare
  RightSquare

  // Invalid token
  UnexpectedGrapheme(String)
  UnterminatedString(String)
}

pub fn drop_whitespace(tokens) {
  list.filter(tokens, fn(token) {
    case token {
      #(Whitespace(_), _) -> False
      _ -> True
    }
  })
}

pub fn to_string(token) {
  case token {
    Whitespace(raw) -> raw
    Name(raw) -> raw
    Uppername(raw) -> raw
    Integer(raw) -> raw
    String(raw) -> "\"" <> raw <> "\""
    Let -> "let"
    Match -> "match"
    Perform -> "perform"
    Deep -> "deep"
    Handle -> "handle"
    // Having keyword token instead of using name prevents keywords used as names
    Equal -> "="
    Comma -> ","
    DotDot -> ".."
    Dot -> "."
    Colon -> ":"
    RightArrow -> "->"
    Minus -> "-"
    Bang -> "!"
    Bar -> "|"
    Hash -> "#"

    LeftParen -> "("
    RightParen -> ")"
    LeftBrace -> "{"
    RightBrace -> "}"
    LeftSquare -> "["
    RightSquare -> "]"

    // Invalid token
    UnexpectedGrapheme(raw) -> raw
    UnterminatedString(raw) -> "\"" <> raw
  }
}
