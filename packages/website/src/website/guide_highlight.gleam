import gleam/dict
import gleam/javascript/array.{type Array}
import gleam/list
import gleam/option.{Some}
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import pamphlet/lustre

/// Highlight supported code fences during static rendering, using Shiki's bundled
/// languages and the shared EYG VS Code grammar. Unknown and unlabelled languages
/// use Pamphlet's default code-block renderer.
/// Reference tables scroll independently so long signatures fit narrow screens.
pub fn renderer() -> lustre.Renderer(msg, t) {
  let default = lustre.default()
  lustre.Renderer(
    ..default,
    render_table: fn(attrs, children) {
      fn(continue) {
        let render = default.render_table(attrs, children)
        use table <- render
        continue(
          h.div(
            [
              a.class("table-scroll"),
              a.tabindex(0),
              a.role("region"),
              a.attribute("aria-label", "Scrollable table"),
            ],
            [table],
          ),
        )
      }
    },
    render_code_block: fn(attrs, language, content) {
      let supported =
        language |> option.map(supports_language) |> option.unwrap(False)
      case language, supported {
        Some(language), True -> fn(continue) {
          let #(background, foreground, lines) = highlight(content, language)
          let attrs =
            attrs
            |> dict.upsert("class", fn(previous) {
              case previous {
                Some(previous) -> previous <> " language-" <> language
                _ -> "language-" <> language
              }
            })
            |> dict.to_list
            |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
            |> list.map(fn(pair) { a.attribute(pair.0, pair.1) })
          let lines =
            lines
            |> array.to_list
            |> list.map(fn(line) {
              h.span(
                [a.class("line")],
                list.map(array.to_list(line), fn(token) {
                  h.span([a.style("color", token.1)], [element.text(token.0)])
                }),
              )
            })
            |> list.intersperse(element.text("\n"))
          continue(
            h.pre(
              [
                a.class("shiki"),
                a.style("background-color", background),
                a.style("color", foreground),
                a.tabindex(0),
              ],
              [h.code(attrs, lines)],
            ),
          )
        }
        _, _ -> default.render_code_block(attrs, language, content)
      }
    },
  )
}

@external(javascript, "../guide_highlight_ffi.mjs", "supportsLanguage")
fn supports_language(language: String) -> Bool

@external(javascript, "../guide_highlight_ffi.mjs", "highlight")
fn highlight(
  source: String,
  language: String,
) -> #(String, String, Array(Array(#(String, String))))
