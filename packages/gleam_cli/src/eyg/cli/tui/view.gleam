import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/paragraph
import eyg/cli/tui/state
import eyg/cli/tui/view/info
import eyg/interpreter/simple_debug
import eyg/interpreter/value
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import morph/buffer as morph_buffer
import morph/lustre/render
import morph/projection
import morph/repl/history
import morph/terminal
import morph/terminal/combobox
import morph/terminal/field

pub fn render(state: state.State, screen: geometry.Rect) {
  let status_lines = info.status(state)
  let assert [code_area, status_line] =
    geometry.split_v(screen, [
      geometry.Fill,
      geometry.Length(list.length(status_lines)),
    ])
  let active = case state.mode {
    state.Navigating -> True
    state.History(..)
    | state.FreeInput(..)
    | state.PickSingle(..)
    | state.PickRelease(..)
    | state.PickImport(..)
    | state.Running(..) -> False
  }
  let errors = morph_buffer.block_errors(state.buffer)
  let input_lines = case state.empty_draft(state) {
    True -> empty_lines(state, active)
    False ->
      render.projection(state.buffer.projection, render.Statements, errors)
      |> terminal.lines(active)
      |> list.index_map(fn(line, index) {
        let prefix = case index {
          0 -> "> "
          _ -> "  "
        }
        span.Line(..line, spans: [span.span_plain(prefix), ..line.spans])
      })
  }
  let #(selected, open_code, open_effects) = case state.mode {
    state.History(selected:, code:, effects:) -> #(
      Some(selected),
      code,
      effects,
    )
    _ -> #(None, set.new(), set.new())
  }
  let groups =
    state.history
    |> list.index_map(fn(entry, i) {
      let lines =
        history_lines(
          entry,
          code_area.size.width,
          set.contains(open_code, i),
          set.contains(open_effects, i),
        )
        |> list.index_map(fn(line, index) {
          let prefix = case index {
            0 -> "· "
            _ -> "  "
          }
          span.Line(..line, spans: [span.span_plain(prefix), ..line.spans])
        })
      case selected == Some(i) {
        True -> [span.line_plain("◆ selected history"), ..lines]
        False -> lines
      }
    })
    |> list.reverse
  let lines =
    list.flatten(groups)
    |> list.append([span.line_plain("")])
    |> list.append(input_lines)
  let line_count = list.length(lines)
  let visible_height = int.min(line_count, code_area.size.height)
  let content_area =
    geometry.rect_new(
      code_area.position.x,
      geometry.bottom(code_area) - visible_height,
      code_area.size.width,
      visible_height,
    )
  // Like a shell, keep the end of the program visible as it grows upward,
  // or while browsing, the end of the selected entry.
  let end = case selected {
    Some(selected) ->
      list.take(groups, list.length(groups) - selected)
      |> list.map(list.length)
      |> int.sum
      |> int.max(visible_height)
    None -> line_count
  }
  let lines = list.take(lines, end) |> list.drop(end - visible_height)

  let buf =
    buffer.buffer_new(screen)
    |> paragraph.render_styled(content_area, lines)
    // |> paragraph.render_styled(error_area, error_lines(errors))
    // |> buffer.set_style(message_area, message_style)
    |> paragraph.render_styled(status_line, status_lines)

  case state.mode {
    state.Navigating | state.History(..) | state.Running(..) -> buf
    state.PickSingle(box, _)
    | state.PickRelease(box, _)
    | state.PickImport(box:, ..) -> {
      let title = case state.mode {
        state.PickRelease(..) -> "Choose a package"
        state.PickImport(..) -> "Import a file"
        _ -> "Choose a value"
      }
      let border =
        block.block_new()
        |> block.with_border(block.Rounded)
        |> block.with_title(title, block.Top)
        |> block.with_padding(0, 0, 1, 1)
      let area = field.centered(code_area, 12)
      buf
      |> clear.render(area)
      |> block.render(area, border)
      |> combobox.render(block.inner(area, border), box)
    }
    state.FreeInput(editing, kind) -> {
      let widget = state.input_widget(kind)
      let title = case kind {
        state.EnterText(_) -> "Text"
        state.EnterInteger(_) -> "Integer"
        state.PickCid(_) -> "Content reference"
        state.ReplyStandardIn(..) -> "Standard input"
      }
      field.dialog(buf, code_area, title, widget, editing)
    }
  }
}

/// A prompt in place of the empty draft, after a welcome in a new session.
fn empty_lines(state: state.State, active: Bool) -> List(span.Line) {
  let prompt =
    span.line_new([
      span.span_plain("> "),
      span.span_styled(
        "Write EYG…",
        terminal.focus_style(style.default_style(), True, active),
      ),
    ])
  case state.history {
    [] -> [
      span.line_new([
        span.span_styled(
          "EYG shell",
          style.default_style() |> style.add_modifier(style.bold()),
        ),
      ]),
      dim("Paste a program or build one with keys, then press Enter to run it."),
      dim("Try pasting  !int_add(20, 22)  or press n for an integer."),
      dim("q imports a file · @ adds a package · # a content reference"),
      span.line_plain(""),
      prompt,
    ]
    _ -> [prompt]
  }
}

fn dim(text: String) -> span.Line {
  span.line_new([
    span.span_styled(
      text,
      style.default_style() |> style.add_modifier(style.dim()),
    ),
  ])
}

/// Show the first code line and an effect count until expanded.
fn history_lines(
  entry: history.Entry(a),
  width: Int,
  open_code: Bool,
  open_effects: Bool,
) -> List(span.Line) {
  let source =
    entry.buffer.projection
    |> projection.rebuild
    |> render.statements([])
    |> list.flat_map(terminal.lines(_, False))
  let source = case source, open_code {
    [first, _, ..], False -> [
      first,
      dim("▸ " <> count(list.length(source) - 1, "more line")),
    ]
    _, _ -> source
  }
  let effects = case entry.effects, open_effects {
    [], _ -> []
    effects, False -> [dim("▸ " <> count(list.length(effects), "effect"))]
    effects, True ->
      effects
      |> list.reverse
      |> list.map(info.show_effect)
  }
  let lines = list.append(source, effects)
  case entry.outcome {
    history.Success(None) -> lines
    history.Success(Some(value)) -> {
      let value_lines =
        render_value(value, int.max(1, width - 2))
        |> string.split("\n")
        |> list.index_map(fn(line, index) {
          let prefix = case index {
            0 -> "= "
            _ -> "  "
          }
          span.line_new([
            span.span_styled(prefix <> line, style.default_style()),
          ])
        })
      list.append(lines, value_lines)
    }
    history.Aborted(message) ->
      list.append(lines, [
        span.line_new([
          span.span_styled(
            "■ " <> message,
            style.default_style() |> style.with_fg(style.Indexed(3)),
          ),
        ]),
      ])
    history.Exception(#(reason, _, _, _)) ->
      list.append(lines, [
        span.line_new([
          span.span_styled(
            "✘ " <> simple_debug.describe(reason),
            style.default_style() |> style.with_fg(style.Indexed(1)),
          ),
        ]),
      ])
  }
}

fn render_value(value, width) {
  case value {
    value.String(string) -> string
    _ -> simple_debug.render(value, int.max(1, width - 2))
  }
}

fn count(n: Int, noun: String) -> String {
  case n {
    1 -> "1 " <> noun
    n -> int.to_string(n) <> " " <> noun <> "s"
  }
}
