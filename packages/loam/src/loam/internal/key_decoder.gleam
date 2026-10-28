//// Pure terminal key decoding, retaining escape prefixes between stream chunks.

import gleam/list
import gleam/string

pub type Decoder {
  Decoder(buffer: String)
}

pub type Event {
  Key(String)
  Interrupt
}

pub fn new() {
  Decoder("")
}

pub fn feed(decoder: Decoder, text: String) {
  parse(string.to_graphemes(decoder.buffer <> text), [], False)
}

pub fn flush(decoder: Decoder) {
  parse(string.to_graphemes(decoder.buffer), [], True)
}

fn parse(chars, events, flush) {
  case chars {
    [] -> #(new(), list.reverse(events))
    ["\u{1b}", "[", "A", ..rest] | ["\u{1b}", "O", "A", ..rest] ->
      parse(rest, [Key("ArrowUp"), ..events], flush)
    ["\u{1b}", "[", "B", ..rest] | ["\u{1b}", "O", "B", ..rest] ->
      parse(rest, [Key("ArrowDown"), ..events], flush)
    ["\u{1b}", "[", "C", ..rest] | ["\u{1b}", "O", "C", ..rest] ->
      parse(rest, [Key("ArrowRight"), ..events], flush)
    ["\u{1b}", "[", "D", ..rest] | ["\u{1b}", "O", "D", ..rest] ->
      parse(rest, [Key("ArrowLeft"), ..events], flush)
    ["\u{1b}", "[", "H", ..rest] | ["\u{1b}", "O", "H", ..rest] ->
      parse(rest, [Key("Home"), ..events], flush)
    ["\u{1b}", "[", "F", ..rest] | ["\u{1b}", "O", "F", ..rest] ->
      parse(rest, [Key("End"), ..events], flush)
    ["\u{1b}", "[", "1", "~", ..rest] | ["\u{1b}", "[", "7", "~", ..rest] ->
      parse(rest, [Key("Home"), ..events], flush)
    ["\u{1b}", "[", "4", "~", ..rest] | ["\u{1b}", "[", "8", "~", ..rest] ->
      parse(rest, [Key("End"), ..events], flush)
    ["\u{1b}", "[", "3", "~", ..rest] ->
      parse(rest, [Key("Delete"), ..events], flush)
    ["\u{1b}", "[", "2", "~", ..rest] ->
      parse(rest, [Key("Insert"), ..events], flush)
    ["\u{1b}", "[", "5", "~", ..rest] ->
      parse(rest, [Key("PageUp"), ..events], flush)
    ["\u{1b}", "[", "6", "~", ..rest] ->
      parse(rest, [Key("PageDown"), ..events], flush)
    ["\u{1b}", "[", digit]
      if !flush
      && {
        digit == "1"
        || digit == "2"
        || digit == "3"
        || digit == "4"
        || digit == "5"
        || digit == "6"
        || digit == "7"
        || digit == "8"
      }
    -> #(Decoder(string.join(chars, "")), list.reverse(events))
    ["\u{1b}"] | ["\u{1b}", "["] | ["\u{1b}", "O"] if !flush -> #(
      Decoder(string.join(chars, "")),
      list.reverse(events),
    )
    [char, ..rest] -> {
      let event = case char {
        "\u{1b}" -> Key("Escape")
        "\r" | "\n" -> Key("Enter")
        "\u{7f}" | "\u{8}" -> Key("Backspace")
        "\t" -> Key("Tab")
        "\u{3}" -> Interrupt
        char -> Key(char)
      }
      parse(rest, [event, ..events], flush)
    }
  }
}
