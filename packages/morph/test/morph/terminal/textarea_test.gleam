import etui/span
import etui/style
import gleam/list
import gleam/string
import morph/terminal
import morph/terminal/textarea

fn press(state, keys) {
  list.fold(keys, state, fn(state, key) {
    let assert Ok(state) = textarea.key(state, key)
    state
  })
}

fn type_(state, text) {
  press(state, string.to_graphemes(text))
}

// The text with a | at the cursor.
fn show(state: textarea.Textarea) {
  let assert Ok(cursor) = textarea.insert(state, "|") |> textarea.value |> Ok
  cursor
}

pub fn type_and_move_test() {
  let state = textarea.new() |> type_("let total = 1")
  assert "let total = 1|" == show(state)
  let state = press(state, ["ctrl+left"])
  assert "let total = |1" == show(state)
  let state = press(state, ["alt+left"])
  assert "let |total = 1" == show(state)
  let state = press(state, ["ctrl+right"])
  assert "let total| = 1" == show(state)
  let state = press(state, ["home"])
  assert "|let total = 1" == show(state)
  let state = press(state, ["end", "left", "shift+left"])
  assert "let total =| 1" == show(state)
  assert Error(Nil) == textarea.key(state, "pageup")
}

pub fn lines_test() {
  let state = textarea.new() |> type_("one") |> press(["shift+enter"])
  let state = type_(state, "two")
  assert "one\ntwo|" == show(state)
  let state = press(state, ["up"])
  assert "one|\ntwo" == show(state)
  // Words and characters are deleted across the end of a line.
  let state = press(state, ["delete"])
  assert "one|two" == show(state)
  let state = press(state, ["ctrl+home"])
  assert "|onetwo" == show(state)
  let state = press(state, ["ctrl+end", "ctrl+left", "ctrl+right"])
  assert "onetwo|" == show(state)
  let state =
    textarea.from_string("a\nb")
    |> press(["ctrl+home", "ctrl+right", "ctrl+right"])
  assert "a\nb|" == show(state)
}

pub fn delete_test() {
  let state = textarea.from_string("perform Log(message)")
  let state = press(state, ["ctrl+backspace"])
  assert "perform Log(|" == show(state)
  let state = press(state, ["alt+backspace", "backspace"])
  assert "perform|" == show(state)
  let state = press(state, ["home", "ctrl+delete"])
  assert "|" == show(state)
  let state =
    textarea.from_string("let x = 1") |> press(["ctrl+left", "ctrl+u"])
  assert "|1" == show(state)
  let state = textarea.from_string("let x = 1") |> press(["home", "ctrl+k"])
  assert "|" == show(state)
}

pub fn insert_text_test() {
  let state = textarea.from_string("{}") |> press(["left"])
  let state = textarea.insert(state, "a: 1,\r\nb: 2")
  assert "{a: 1,\nb: 2|}" == show(state)
  assert !textarea.is_empty(state)
  assert textarea.is_empty(textarea.from_string("  \n "))
}

fn text(lines: List(span.Line)) {
  list.map(lines, fn(line) {
    list.map(line.spans, fn(span) { span.content }) |> string.concat
  })
}

pub fn wrap_with_cursor_test() {
  let state =
    textarea.from_string("abcdef\ngh") |> press(["up", "home", "right"])
  let #(lines, row) = textarea.lines(state, textarea.plain, 4, True)
  assert ["abcd", "ef", "gh"] == text(lines)
  assert 0 == row
  // The cell at the cursor is reversed.
  let assert [first, ..] = lines
  let assert [_, span.Span(content: "b", style:, ..), ..] = first.spans
  assert style.has(style.modifier, style.reverse())
  // At the end of a line the cursor is a space after it.
  let #(lines, row) =
    textarea.lines(textarea.from_string("abcdef\ngh"), textarea.plain, 4, True)
  assert ["abcd", "ef", "gh "] == text(lines)
  assert 2 == row
  let #(lines, _) =
    textarea.lines(textarea.from_string("abcdef\ngh"), textarea.plain, 4, False)
  assert ["abcd", "ef", "gh"] == text(lines)
}

pub fn highlight_eyg_test() {
  let source = "let x = !int_add(1, \"two\") // sum\n@std.list ^"
  let lines = terminal.highlight(source)
  // The text is kept exactly.
  assert string.split(source, "\n")
    == list.map(lines, fn(spans) {
      list.map(spans, fn(span) { span.content }) |> string.concat
    })
  let assert [first, second] = lines
  let style_of = fn(spans, content) {
    let assert Ok(span.Span(style:, ..)) =
      list.find(spans, fn(span: span.Span) { span.content == content })
    style
  }
  let keyword = style_of(first, "let")
  let variable = style_of(first, "x")
  let builtin = style_of(first, "int_add")
  let number = style_of(first, "1")
  let text = style_of(first, "\"two\"")
  assert list.unique([keyword, variable, builtin, number])
    |> list.length
    == 4
  assert builtin == style_of(first, "!")
  assert text == builtin
  assert style.has(style_of(first, "// sum").modifier, style.dim())
  assert style_of(second, "std") == style_of(second, "@")
  assert style.has(style_of(second, "^").modifier, style.underline())
}

pub fn wrap_spans_test() {
  let spans = [span.span_plain("abc"), span.span_plain("def")]
  assert ["abcd", "ef"] == text(textarea.wrap(spans, 4))
  assert [""] == text(textarea.wrap([], 4))
}
