import gleam.{type String as S}

pub type Token {
  Name(S)
  Uppername(S)
  Integer(S)
  String(S)
  Let
  Match
  Perform
  Deep
  Shallow
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

  LeftParen
  RightParen
  LeftBrace
  RightBrace
  LeftSquare
  RightSquare
}
