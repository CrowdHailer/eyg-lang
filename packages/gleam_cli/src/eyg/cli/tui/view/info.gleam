import etui/span
import etui/style
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic
import eyg/cli/tui/state
import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/ir/tree
import gleam/int
import gleam/list
import gleam/option.{None}
import morph/buffer
import morph/projection

fn focus_type(state: state.State) {
  case state.buffer.projection.0 {
    projection.Exp(_) -> {
      case buffer.target_info(state.buffer) {
        Ok(info) ->
          case info.status {
            Ok(Nil) -> Ok(info.type_)

            Error(reason) -> {
              debug.reason(reason)
              Error(reason)
            }
          }
        Error(_) -> Ok(isomorphic.Var(-1))
      }
    }
    projection.Assign(..) -> Ok(isomorphic.Var(-1))
    projection.FnParam(..) -> Ok(isomorphic.Var(-1))
    projection.Label(..) -> Ok(isomorphic.Var(-1))
    projection.Select(..) -> Ok(isomorphic.Var(-1))
    projection.Match(..) -> Ok(isomorphic.Var(-1))
  }
}

fn split(rest, errors, loading, state) {
  case rest {
    [] -> #(list.reverse(loading), list.reverse(errors))
    [#(_, error.MissingReference(reference)) as error, ..rest] ->
      case state.reference_loading(state, reference) {
        True -> split(rest, errors, [reference, ..loading], state)
        False -> split(rest, [error, ..errors], loading, state)
      }
    [error, ..rest] -> split(rest, [error, ..errors], loading, state)
  }
}

/// Keys to get started while the draft is empty.
fn empty_status(state: state.State) -> span.Line {
  case state.mode {
    state.Navigating -> {
      let hints = case state.history {
        [] -> "Ctrl+Q quit"
        _ -> "↑ history · Ctrl+Q quit"
      }
      span.line_new([
        span.span_styled(
          hints,
          style.default_style() |> style.add_modifier(style.dim()),
        ),
      ])
    }
    _ -> span.line_plain("")
  }
}

pub fn status(state: state.State) -> List(span.Line) {
  case state.mode {
    state.Navigating
    | state.FreeInput(..)
    | state.PickSingle(..)
    | state.PickRelease(..)
    | state.PickImport(..) ->
      case state.message, state.empty_draft(state) {
        None, True -> empty_status(state)
        None, False if state.buffer.analysis == None ->
          span.line_plain("unchecked")
        None, False -> {
          let #(loading, errors) =
            split(buffer.block_errors(state.buffer), [], [], state)

          let infer = case list.length(loading), list.length(errors) {
            0, 0 ->
              span.span_styled(
                "✔  ",
                style.default_style() |> style.with_fg(style.Indexed(2)),
              )
            0, n if n < 10 ->
              span.span_styled(
                "!" <> int.to_string(n) <> " ",
                style.default_style() |> style.with_fg(style.Indexed(1)),
              )
            0, _ ->
              span.span_styled(
                "!9+",
                style.default_style() |> style.with_fg(style.Indexed(1)),
              )
            n, _ if n < 10 ->
              span.span_styled(
                "◌" <> int.to_string(n) <> " ",
                style.default_style() |> style.with_fg(style.Indexed(3)),
              )
            _, _ ->
              span.span_styled(
                "◌9+",
                style.default_style() |> style.with_fg(style.Indexed(3)),
              )
          }
          let space = span.span_plain("· ")
          let focus = case focus_type(state) {
            Ok(isomorphic.Var(-1)) -> span.span_plain("")
            Ok(type_) -> span.span_plain(debug.mono(type_))
            Error(error.MissingReference(reference) as reason) ->
              case state.reference_loading(state, reference) {
                True ->
                  span.span_styled(
                    "loading " <> tree.reference_to_string(reference),
                    style.default_style() |> style.with_fg(style.Indexed(3)),
                  )
                False ->
                  span.span_styled(
                    debug.reason(reason),
                    style.default_style() |> style.with_fg(style.Indexed(1)),
                  )
              }
            Error(reason) ->
              span.span_styled(
                debug.reason(reason),
                style.default_style() |> style.with_fg(style.Indexed(1)),
              )
          }
          span.line_new([infer, space, focus])
        }
        option.Some(message), _ ->
          span.line_new([
            span.span_styled(
              "! " <> message,
              style.default_style() |> style.with_fg(style.Indexed(1)),
            ),
          ])
      }
      |> list.wrap
    state.History(selected:) -> [
      span.line_new([
        span.span_styled(
          "history "
            <> int.to_string(selected + 1)
            <> "/"
            <> int.to_string(list.length(state.history))
            <> " · ↑↓ select · Enter recall · Esc edit",
          style.default_style() |> style.with_fg(style.Indexed(6)),
        ),
      ]),
    ]
    state.Running(active:, env: _, k: _, occured:) -> {
      let display = case active {
        state.Handling(task_id: _, label:, lift:) ->
          label <> "(" <> simple_debug.inspect(lift) <> ")"
        state.Blocked(dep: cache.Content(cid:)) ->
          tree.reference_to_string(tree.Content(cid))
        state.Blocked(dep: cache.Pinned(release)) ->
          tree.release_to_string(release)
      }
      let last =
        span.line_new([
          span.span_styled(
            "◌ " <> display,
            style.default_style() |> style.with_fg(style.Indexed(3)),
          ),
        ])
      let effects =
        list.take(occured, 5)
        |> list.map(fn(effect) {
          let #(label, #(lift, reply)) = effect
          let message =
            "✔ "
            <> label
            <> "("
            <> simple_debug.inspect(lift)
            <> ") -> "
            <> simple_debug.inspect(reply)
          span.line_new([
            span.span_styled(
              message,
              style.default_style() |> style.with_fg(style.Indexed(7)),
            ),
          ])
        })
      list.reverse([last, ..effects])
    }
  }
}
