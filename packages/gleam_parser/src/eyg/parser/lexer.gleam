import eyg/parser/token as t
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string

pub fn lex(raw: String) -> List(#(t.Token, Int)) {
  let bits = bit_array.from_string(raw)
  loop(bits, 0, [])
}

fn loop(raw, offset, acc) {
  case pop(raw, offset) {
    Ok(#(token, offset, rest)) -> loop(rest, offset, [token, ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}

fn done(at start) {
  fn(t, size, rest) { Ok(#(#(t, start), start + size, rest)) }
}

fn pop(raw, start) {
  let done = done(at: start)

  // If we track whitespace token then can always return original start
  case raw {
    <<"//", rest:bits>> -> comment(<<>>, rest, done)
    <<"\r\n", rest:bits>> -> whitespace(<<"\r\n">>, rest, done)
    <<"\n", rest:bits>> -> whitespace(<<"\n">>, rest, done)
    <<" ", rest:bits>> -> whitespace(<<" ">>, rest, done)
    <<"\t", rest:bits>> -> whitespace(<<"\t">>, rest, done)

    <<"(", rest:bits>> -> done(t.LeftParen, 1, rest)
    <<")", rest:bits>> -> done(t.RightParen, 1, rest)
    <<"{", rest:bits>> -> done(t.LeftBrace, 1, rest)
    <<"}", rest:bits>> -> done(t.RightBrace, 1, rest)
    <<"[", rest:bits>> -> done(t.LeftSquare, 1, rest)
    <<"]", rest:bits>> -> done(t.RightSquare, 1, rest)

    <<"=", rest:bits>> -> done(t.Equal, 1, rest)
    <<"->", rest:bits>> -> done(t.RightArrow, 2, rest)
    <<",", rest:bits>> -> done(t.Comma, 1, rest)
    <<"..", rest:bits>> -> done(t.DotDot, 2, rest)
    <<".", rest:bits>> -> done(t.Dot, 1, rest)
    <<":", rest:bits>> -> done(t.Colon, 1, rest)
    <<"-", rest:bits>> -> done(t.Minus, 1, rest)
    <<"!", rest:bits>> -> done(t.Bang, 1, rest)
    <<"|", rest:bits>> -> done(t.Bar, 1, rest)
    <<"#", rest:bits>> -> done(t.Hash, 1, rest)
    <<"@", rest:bits>> -> done(t.At, 1, rest)

    <<"\"", rest:bits>> -> string(<<>>, 1, rest, done)

    <<"1", rest:bits>> -> integer(<<"1">>, rest, done)
    <<"2", rest:bits>> -> integer(<<"2">>, rest, done)
    <<"3", rest:bits>> -> integer(<<"3">>, rest, done)
    <<"4", rest:bits>> -> integer(<<"4">>, rest, done)
    <<"5", rest:bits>> -> integer(<<"5">>, rest, done)
    <<"6", rest:bits>> -> integer(<<"6">>, rest, done)
    <<"7", rest:bits>> -> integer(<<"7">>, rest, done)
    <<"8", rest:bits>> -> integer(<<"8">>, rest, done)
    <<"9", rest:bits>> -> integer(<<"9">>, rest, done)
    <<"0", rest:bits>> -> integer(<<"0">>, rest, done)
    _ -> {
      let next_byte = bytes_take_first(raw)
      let rest = bytes_drop_first(raw)
      case next_byte {
        <<"_">>
        | <<"a">>
        | <<"b">>
        | <<"c">>
        | <<"d">>
        | <<"e">>
        | <<"f">>
        | <<"g">>
        | <<"h">>
        | <<"i">>
        | <<"j">>
        | <<"k">>
        | <<"l">>
        | <<"m">>
        | <<"n">>
        | <<"o">>
        | <<"p">>
        | <<"q">>
        | <<"r">>
        | <<"s">>
        | <<"t">>
        | <<"u">>
        | <<"v">>
        | <<"w">>
        | <<"x">>
        | <<"y">>
        | <<"z">> -> name(next_byte, rest, done)
        <<"A">>
        | <<"B">>
        | <<"C">>
        | <<"D">>
        | <<"E">>
        | <<"F">>
        | <<"G">>
        | <<"H">>
        | <<"I">>
        | <<"J">>
        | <<"K">>
        | <<"L">>
        | <<"M">>
        | <<"N">>
        | <<"O">>
        | <<"P">>
        | <<"Q">>
        | <<"R">>
        | <<"S">>
        | <<"T">>
        | <<"U">>
        | <<"V">>
        | <<"W">>
        | <<"X">>
        | <<"Y">>
        | <<"Z">> -> uppername(next_byte, rest, done)
        <<>> -> Error(Nil)
        _ -> {
          let string = to_string(raw)
          let #(char, rest) =
            string.pop_grapheme(string) |> result.unwrap(#(string, ""))
          let size = bit_array.byte_size(<<char:utf8>>)
          done(t.UnexpectedGrapheme(char), size, <<rest:utf8>>)
        }
      }
    }
  }
}

fn to_string(bits) {
  case bit_array.to_string(bits) {
    Ok(s) -> s
    // because the public interface is a string (valid utf8) and all breaks are on ascii charachters it is safe to turn sub sections back to string.
    Error(_) -> panic as "invalid utf8 in token"
  }
}

fn comment(buffer, rest, done) {
  case rest {
    // leave newline on stack to end up as witespace
    <<"\r\n", _:bits>> | <<"\n", _:bits>> ->
      done(t.Comment(to_string(buffer)), bit_array.byte_size(buffer) + 2, rest)
    // A comment at EOF (no trailing newline) closes here.
    <<>> ->
      done(t.Comment(to_string(buffer)), bit_array.byte_size(buffer) + 2, <<>>)
    _ -> {
      let next_byte = bytes_take_first(rest)
      let rest = bytes_drop_first(rest)
      comment(bit_array.append(buffer, next_byte), rest, done)
    }
  }
}

fn whitespace(buffer, rest, done) {
  case rest {
    <<"\r\n", rest:bits>> ->
      whitespace(bit_array.append(buffer, <<"\r\n">>), rest, done)
    <<"\n", rest:bits>> ->
      whitespace(bit_array.append(buffer, <<"\n">>), rest, done)
    <<" ", rest:bits>> ->
      whitespace(bit_array.append(buffer, <<" ">>), rest, done)
    <<"\t", rest:bits>> ->
      whitespace(bit_array.append(buffer, <<"\t">>), rest, done)
    _ ->
      done(t.Whitespace(to_string(buffer)), bit_array.byte_size(buffer), rest)
  }
}

fn string(buffer, length, rest, done) {
  case rest {
    <<"\"", rest:bits>> -> done(t.String(to_string(buffer)), length + 1, rest)
    <<"\\", rest:bits>> ->
      case rest {
        <<"\"", rest:bits>> ->
          string(bit_array.append(buffer, <<"\"">>), length + 2, rest, done)
        <<"\\", rest:bits>> ->
          string(bit_array.append(buffer, <<"\\">>), length + 2, rest, done)
        <<"t", rest:bits>> ->
          string(bit_array.append(buffer, <<"\t">>), length + 2, rest, done)
        <<"r", rest:bits>> ->
          string(bit_array.append(buffer, <<"\r">>), length + 2, rest, done)
        <<"n", rest:bits>> ->
          string(bit_array.append(buffer, <<"\n">>), length + 2, rest, done)
        <<>> ->
          done(
            t.UnterminatedString(to_string(bit_array.append(buffer, <<"\\">>))),
            length + 1,
            <<>>,
          )
        _ ->
          done(
            t.InvalidEscape(
              to_string(bit_array.append(
                bit_array.append(buffer, <<"\\">>),
                rest,
              )),
            ),
            length,
            <<>>,
          )
      }
    <<>> -> done(t.UnterminatedString(to_string(buffer)), length, <<>>)
    _ -> {
      let next_byte = bytes_take_first(rest)
      let rest = bytes_drop_first(rest)
      string(bit_array.append(buffer, next_byte), length + 1, rest, done)
    }
  }
}

fn name(buffer, raw, done) {
  let next_byte = bytes_take_first(raw)
  let rest = bytes_drop_first(raw)
  case
    is_lower_grapheme(next_byte)
    || is_digit_grapheme(next_byte)
    || next_byte == <<"_">>
  {
    True -> name(bit_array.append(buffer, next_byte), rest, done)
    False ->
      done(keyword_or_name(to_string(buffer)), bit_array.byte_size(buffer), raw)
  }
}

fn keyword_or_name(buffer) {
  case buffer {
    "let" -> t.Let
    "match" -> t.Match
    "perform" -> t.Perform
    "deep" -> t.Deep
    "handle" -> t.Handle
    "import" -> t.Import
    _ -> t.Name(buffer)
  }
}

fn uppername(buffer, raw, done) {
  let next_byte = bytes_take_first(raw)
  let rest = bytes_drop_first(raw)

  case
    is_upper_grapheme(next_byte)
    || is_lower_grapheme(next_byte)
    || is_digit_grapheme(next_byte)
    || next_byte == <<"_">>
  {
    True -> uppername(bit_array.append(buffer, next_byte), rest, done)
    False ->
      done(t.Uppername(to_string(buffer)), bit_array.byte_size(buffer), raw)
  }
}

fn integer(buffer, rest, done) {
  case rest {
    <<"1", rest:bits>> -> integer(bit_array.append(buffer, <<"1">>), rest, done)
    <<"2", rest:bits>> -> integer(bit_array.append(buffer, <<"2">>), rest, done)
    <<"3", rest:bits>> -> integer(bit_array.append(buffer, <<"3">>), rest, done)
    <<"4", rest:bits>> -> integer(bit_array.append(buffer, <<"4">>), rest, done)
    <<"5", rest:bits>> -> integer(bit_array.append(buffer, <<"5">>), rest, done)
    <<"6", rest:bits>> -> integer(bit_array.append(buffer, <<"6">>), rest, done)
    <<"7", rest:bits>> -> integer(bit_array.append(buffer, <<"7">>), rest, done)
    <<"8", rest:bits>> -> integer(bit_array.append(buffer, <<"8">>), rest, done)
    <<"9", rest:bits>> -> integer(bit_array.append(buffer, <<"9">>), rest, done)
    <<"0", rest:bits>> -> integer(bit_array.append(buffer, <<"0">>), rest, done)
    _ -> done(t.Integer(to_string(buffer)), bit_array.byte_size(buffer), rest)
  }
}

fn is_lower_grapheme(grapheme) {
  case grapheme {
    <<"a">>
    | <<"b">>
    | <<"c">>
    | <<"d">>
    | <<"e">>
    | <<"f">>
    | <<"g">>
    | <<"h">>
    | <<"i">>
    | <<"j">>
    | <<"k">>
    | <<"l">>
    | <<"m">>
    | <<"n">>
    | <<"o">>
    | <<"p">>
    | <<"q">>
    | <<"r">>
    | <<"s">>
    | <<"t">>
    | <<"u">>
    | <<"v">>
    | <<"w">>
    | <<"x">>
    | <<"y">>
    | <<"z">> -> True
    _ -> False
  }
}

fn is_upper_grapheme(grapheme) {
  case grapheme {
    <<"A">>
    | <<"B">>
    | <<"C">>
    | <<"D">>
    | <<"E">>
    | <<"F">>
    | <<"G">>
    | <<"H">>
    | <<"I">>
    | <<"J">>
    | <<"K">>
    | <<"L">>
    | <<"M">>
    | <<"N">>
    | <<"O">>
    | <<"P">>
    | <<"Q">>
    | <<"R">>
    | <<"S">>
    | <<"T">>
    | <<"U">>
    | <<"V">>
    | <<"W">>
    | <<"X">>
    | <<"Y">>
    | <<"Z">> -> True
    _ -> False
  }
}

fn is_digit_grapheme(grapheme) {
  case grapheme {
    <<"1">>
    | <<"2">>
    | <<"3">>
    | <<"4">>
    | <<"5">>
    | <<"6">>
    | <<"7">>
    | <<"8">>
    | <<"9">>
    | <<"0">> -> True
    _ -> False
  }
}

fn bytes_take_first(raw) {
  case raw {
    <<byte, _:bits>> -> <<byte>>
    <<>> -> <<>>
    // because the public interface only accepts a string binaries will always be byte aligned
    _ -> panic as "unexpected bit string"
  }
}

fn bytes_drop_first(raw) {
  case raw {
    <<_byte, slice:bits>> -> slice
    <<>> -> <<>>
    // because the public interface only accepts a string binaries will always be byte aligned
    _ -> panic as "unexpected bit string"
  }
}
