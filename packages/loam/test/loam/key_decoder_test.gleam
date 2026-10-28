import loam/internal/key_decoder as keys

pub fn terminal_sequences_and_unicode_keep_key_order_test() {
  let #(decoder, events) =
    keys.feed(keys.new(), "a🌱緑\u{1b}[A\u{1b}OD\r\t\u{7f}")
  assert events
    == [
      keys.Key("a"),
      keys.Key("🌱"),
      keys.Key("緑"),
      keys.Key("ArrowUp"),
      keys.Key("ArrowLeft"),
      keys.Key("Enter"),
      keys.Key("Tab"),
      keys.Key("Backspace"),
    ]
  assert decoder == keys.new()
}

pub fn split_escape_sequences_and_standalone_escape_are_distinct_test() {
  let #(decoder, events) = keys.feed(keys.new(), "\u{1b}[")
  assert events == []
  let #(decoder, events) = keys.feed(decoder, "B")
  assert decoder == keys.new()
  assert events == [keys.Key("ArrowDown")]
  let #(decoder, _) = keys.feed(keys.new(), "\u{1b}")
  assert keys.flush(decoder) == #(keys.new(), [keys.Key("Escape")])
}

pub fn unknown_sequences_preserve_their_characters_and_interrupts_test() {
  let #(_, events) = keys.feed(keys.new(), "\u{1b}x\u{3}")
  assert events == [keys.Key("Escape"), keys.Key("x"), keys.Interrupt]
}

pub fn numeric_console_sequences_can_arrive_in_separate_chunks_test() {
  let #(decoder, events) = keys.feed(keys.new(), "\u{1b}[3")
  assert events == []
  let #(decoder, events) = keys.feed(decoder, "~\u{1b}[1~\u{1b}[4~")
  assert events == [keys.Key("Delete"), keys.Key("Home"), keys.Key("End")]
  assert decoder == keys.new()
}
