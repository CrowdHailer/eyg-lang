import eyg/parse/token as t

pub type Category {
  Whitespace
  Text
  UpperText
  Number
  String
  KeyWord
  Effect
  Builtin
  Reference
  Punctuation
  Unknown
}

fn classify(token) {
  case token {
    t.Whitespace(_) -> Whitespace
    t.Name(_) -> Text
    t.Uppername(_) -> UpperText
    t.Integer(_) -> Number
    t.String(_) -> String

    t.Let -> KeyWord
    t.Match -> KeyWord
    t.Perform -> KeyWord
    t.Deep -> KeyWord
    t.Handle -> KeyWord

    t.Equal -> Punctuation
    t.Comma -> Punctuation
    t.DotDot -> Punctuation
    t.Dot -> Punctuation
    t.Colon -> Punctuation
    t.RightArrow -> Punctuation
    t.Minus -> Punctuation
    t.Bang -> Punctuation
    t.Bar -> Punctuation
    t.Hash -> Reference

    t.LeftParen -> Punctuation
    t.RightParen -> Punctuation
    t.LeftBrace -> Punctuation
    t.RightBrace -> Punctuation
    t.LeftSquare -> Punctuation
    t.RightSquare -> Punctuation

    t.UnexpectedGrapheme(_) -> Unknown
    t.UnterminatedString(_) -> String
  }
}

// returned reversed
fn do_highlight(tokens, class, buffer, acc) {
  case tokens {
    [] -> push(class, buffer, acc)
    [t.Perform as k, t.Whitespace(w), t.Uppername(l), ..tokens]
    | [t.Deep as k, t.Whitespace(w), t.Uppername(l), ..tokens]
    | [t.Handle as k, t.Whitespace(w), t.Uppername(l), ..tokens] -> {
      let acc = [
        #(Effect, l),
        #(Whitespace, w),
        #(KeyWord, t.to_string(k)),
        ..push(class, buffer, acc)
      ]
      do_highlight(tokens, Text, "", acc)
    }
    [t.Bang as k, t.Name(l), ..tokens] -> {
      let acc = [#(Builtin, t.to_string(k) <> l), ..push(class, buffer, acc)]
      do_highlight(tokens, Text, "", acc)
    }
    [t.Hash as k, t.Name(l), ..tokens] -> {
      let acc = [#(Reference, t.to_string(k) <> l), ..push(class, buffer, acc)]
      do_highlight(tokens, Text, "", acc)
    }
    [next, ..tokens] -> {
      let raw = t.to_string(next)
      case classify(next) {
        c if c == class -> do_highlight(tokens, class, buffer <> raw, acc)
        new -> do_highlight(tokens, new, raw, push(class, buffer, acc))
      }
    }
  }
}

pub fn push(class, buffer, acc) {
  case buffer {
    "" -> acc
    _ -> [#(class, buffer), ..acc]
  }
}

pub fn highlight(tokens, with) {
  let reversed = do_highlight(tokens, Text, "", [])
  do_map(reversed, with, [])
}

fn do_map(items, func, acc) {
  case items {
    [] -> acc
    [item, ..items] -> do_map(items, func, [func(item), ..acc])
  }
}
