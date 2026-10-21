import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import pamphlet/lustre
import website/guide_highlight

pub fn supported_languages_and_aliases_test() {
  list.each(
    [
      #("gleam", "pub fn main() { 42 }"),
      #("erlang", "main() -> {ok, 42}."),
      #("erl", "main() -> {ok, 42}."),
      #("eyg", "let answer = 42\nanswer"),
      #("sh", "echo \"hello\""),
      #("js", "const answer = 42;"),
      #("python", "def answer():\n    return 42"),
    ],
    fn(example) {
      let #(language, source) = example
      let render =
        guide_highlight.renderer().render_code_block(
          dict.new(),
          Some(language),
          source,
        )
      let html = render(element.to_string)
      assert string.contains(html, "class=\"shiki\"")
      assert string.contains(html, "class=\"language-" <> language <> "\"")
      assert string.contains(html, "<span style=\"color:")
    },
  )
}

pub fn unknown_and_unlabelled_fences_use_default_renderer_test() {
  list.each(
    [None, Some("unknown-language"), Some("__proto__"), Some("text")],
    fn(language) {
      let attrs = dict.from_list([#("class", "example")])
      let source = "<script>alert('hello')</script>\nplain text"
      let render =
        guide_highlight.renderer().render_code_block(attrs, language, source)
      let default = lustre.default().render_code_block(attrs, language, source)
      assert render(element.to_string) == default(element.to_string)
    },
  )
}

pub fn highlighted_code_escapes_html_and_preserves_attributes_test() {
  let render =
    guide_highlight.renderer().render_code_block(
      dict.from_list([#("class", "example"), #("id", "sample")]),
      Some("gleam"),
      "let html = \"<script>&</script>\"",
    )
  let html = render(element.to_string)
  assert string.contains(html, "class=\"example language-gleam\"")
  assert string.contains(html, "id=\"sample\"")
  assert !string.contains(html, "<script>")
  assert string.contains(html, "&lt;script&gt;&amp;&lt;/script&gt;")
}
