import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/input
import etui/widgets/paragraph
import eyg/cli/etui/widgets/combobox
import eyg/cli/tui/state
import eyg/cli/tui/view/info
import eyg/interpreter/simple_debug
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import morph/buffer as morph_buffer
import morph/lustre/frame
import morph/lustre/render
import morph/projection
import morph/repl/history

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
    | state.Running(..) -> False
  }
  let errors = morph_buffer.block_errors(state.buffer)
  let input_lines =
    render.projection(state.buffer.projection, render.Statements, errors)
    |> code(active)
    |> list.index_map(fn(line, index) {
      let prefix = case index {
        0 -> "> "
        _ -> "  "
      }
      span.Line(..line, spans: [span.span_plain(prefix), ..line.spans])
    })
  let selected = case state.mode {
    state.History(selected:) -> Some(selected)
    _ -> None
  }
  let groups =
    state.history
    |> list.index_map(fn(entry, i) {
      let lines =
        history_lines(entry, code_area.size.width)
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
    state.PickSingle(box, _) | state.PickRelease(box, _) -> {
      let title = case state.mode {
        state.PickRelease(..) -> "Choose a package"
        _ -> "Choose a value"
      }
      let border =
        block.block_new()
        |> block.with_border(block.Rounded)
        |> block.with_title(title, block.Top)
        |> block.with_padding(0, 0, 1, 1)
      let area = dialog_area(code_area, 12)
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
        state.EnterImport(_) -> "Import a file"
        state.PickCid(_) -> "Content reference"
        state.ReplyStandardIn(..) -> "Standard input"
      }
      let message = case input.validate(widget, editing.value) {
        Ok(_) ->
          span.span_styled(
            "Enter apply · Esc cancel",
            style.default_style() |> style.add_modifier(style.dim()),
          )
        Error(message) ->
          span.span_styled(
            message,
            style.default_style() |> style.with_fg(widget.error_fg),
          )
      }
      let border =
        block.block_new()
        |> block.with_border(block.Rounded)
        |> block.with_title(title, block.Top)
        |> block.with_padding(0, 0, 1, 1)
      let area = dialog_area(code_area, 5)
      let inner = block.inner(area, border)
      let buf = buf |> clear.render(area) |> block.render(area, border)
      case inner.size.width > 0 && inner.size.height > 0 {
        True -> {
          let assert [field, _, feedback] =
            geometry.split_v(inner, [
              geometry.Length(1),
              geometry.Fill,
              geometry.Length(1),
            ])
          buf
          |> input.render(field, widget, editing)
          |> paragraph.render_styled(feedback, [span.line_new([message])])
        }
        False -> buf
      }
    }
  }
}

fn dialog_area(area: geometry.Rect, height: Int) -> geometry.Rect {
  let margin = case area.size.width >= 40 {
    True -> 4
    False -> 0
  }
  geometry.centered_rect(int.min(72, area.size.width - margin), height, area)
}

fn history_lines(entry: history.Entry(a), width: Int) -> List(span.Line) {
  let lines =
    entry.buffer.projection
    |> projection.rebuild
    |> render.statements([])
    |> list.flat_map(code(_, False))
    |> list.append(
      entry.effects
      |> list.reverse
      |> list.map(fn(effect) {
        let #(label, #(lift, reply)) = effect
        span.line_new([
          span.span_styled(
            "✔ "
              // TODO extract helpers to print effects
              <> label
              <> "("
              <> simple_debug.inspect(lift)
              <> ") -> "
              <> simple_debug.inspect(reply),
            style.default_style() |> style.with_fg(style.Indexed(7)),
          ),
        ])
      }),
    )
  case entry.outcome {
    history.Success(None) -> lines
    history.Success(Some(value)) -> {
      let value_lines =
        simple_debug.render(value, int.max(1, width - 2))
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

fn code(value: frame.Frame, active: Bool) -> List(span.Line) {
  case value {
    frame.Inline(spans) -> list.wrap(line(spans, active))
    frame.Multiline([], inner, []) | frame.Statements(inner) ->
      list.flat_map(inner, code(_, active))
    frame.Multiline(pre, inner, post) -> {
      // Indent the whole selected structure, but not a selected child alone.
      // Its boundary lines may also contain unselected context or delimiters.
      let focused =
        list.any(pre, fn(s) { s.focus })
        && list.any(post, fn(s) { s.focus })
        && list.all(inner, frame.fully_focused)
      let indent =
        span.span_styled(
          "  ",
          focus_style(style.default_style(), focused, active),
        )
      list.flatten([
        [line(pre, active)],
        list.flat_map(inner, code(_, active))
          |> list.map(fn(line) {
            span.Line(..line, spans: [indent, ..line.spans])
          }),
        [line(post, active)],
      ])
    }
  }
}

fn line(spans: List(frame.Span), active: Bool) -> span.Line {
  let red = style.Rgb(255, 0, 0)

  list.map(spans, fn(span) {
    let base = syntax_style(span.token_type)
    let style = case span.error {
      True ->
        base
        |> style.add_modifier(style.underline())
        |> style.with_underline_color(red)
      False -> base
    }
    let style = focus_style(style, span.focus, active)
    span.span_styled(span.text, style)
  })
  |> span.line_new
}

fn focus_style(base: style.Style, focused: Bool, active: Bool) -> style.Style {
  case focused, active {
    False, _ -> base
    True, True ->
      base
      |> style.with_fg(style.Default)
      |> style.with_bg(style.Default)
      |> style.add_modifier(style.reverse())
    True, False ->
      base
      |> style.add_modifier(style.dim())
      |> style.add_modifier(style.underline())
  }
}

fn syntax_style(token_type: frame.TokenType) -> style.Style {
  case token_type {
    frame.Plain | frame.Punctuation -> style.default_style()

    frame.Comment ->
      style.default_style()
      |> style.add_modifier(style.dim())

    frame.Number | frame.Symbol ->
      style.default_style()
      |> style.with_fg(style.Indexed(5))

    frame.String | frame.Char | frame.Builtin ->
      style.default_style()
      |> style.with_fg(style.Indexed(2))

    frame.Keyword ->
      style.default_style()
      |> style.with_fg(style.Indexed(6))

    frame.Variable ->
      style.default_style()
      |> style.with_fg(style.Indexed(3))

    frame.Important ->
      style.default_style()
      |> style.with_fg(style.Indexed(3))
      |> style.add_modifier(style.bold())
    frame.ClassName ->
      style.default_style()
      |> style.with_fg(style.Indexed(12))
      |> style.add_modifier(style.bold())
  }
}
