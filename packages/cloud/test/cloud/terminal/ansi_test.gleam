import cloud/terminal/ansi
import etui/span.{Span}
import etui/style

fn base() {
  style.default_style()
}

fn text(lines) {
  case lines {
    [] -> []
    [span.Line(spans:, ..), ..rest] -> [spans, ..text(rest)]
  }
}

pub fn plain_text_test() {
  assert text(ansi.parse("hello", base())) == [[Span("hello", base(), "")]]
}

pub fn lines_test() {
  assert text(ansi.parse("a\nb", base()))
    == [[Span("a", base(), "")], [Span("b", base(), "")]]
  assert text(ansi.parse("a\n", base())) == [[Span("a", base(), "")]]
  assert text(ansi.parse("a\n\nb", base()))
    == [[Span("a", base(), "")], [], [Span("b", base(), "")]]
  assert text(ansi.parse("", base())) == [[]]
}

pub fn foreground_colour_test() {
  let red = style.with_fg(base(), style.Indexed(1))
  assert text(ansi.parse("\u{1b}[31mred\u{1b}[0m plain", base()))
    == [[Span("red", red, ""), Span(" plain", base(), "")]]
}

pub fn bright_and_extended_colours_test() {
  assert text(ansi.parse("\u{1b}[92mx", base()))
    == [[Span("x", style.with_fg(base(), style.Indexed(10)), "")]]
  assert text(ansi.parse("\u{1b}[38;5;200mx", base()))
    == [[Span("x", style.with_fg(base(), style.Indexed(200)), "")]]
  assert text(ansi.parse("\u{1b}[48;2;1;2;3mx", base()))
    == [[Span("x", style.with_bg(base(), style.Rgb(1, 2, 3)), "")]]
}

pub fn style_carries_across_lines_test() {
  let bold = style.add_modifier(base(), style.bold())
  assert text(ansi.parse("\u{1b}[1ma\nb\u{1b}[22mc", base()))
    == [[Span("a", bold, "")], [Span("b", bold, ""), Span("c", base(), "")]]
}

pub fn reset_returns_to_base_test() {
  let red = style.with_fg(base(), style.Indexed(1))
  let blue = style.with_fg(base(), style.Indexed(4))
  assert text(ansi.parse("\u{1b}[34mb\u{1b}[mr", red))
    == [[Span("b", blue, ""), Span("r", red, "")]]
}

pub fn other_sequences_are_dropped_test() {
  assert text(ansi.parse("a\u{1b}[2Kb", base()))
    == [[Span("a", base(), ""), Span("b", base(), "")]]
}
