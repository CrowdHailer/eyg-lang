import etui/span
import etui/style
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic
import eyg/cli/tui/state
import gleam/int
import gleam/list
import gleam/option.{None}
import morph/buffer
import morph/projection

pub fn block_errors(state: state.State) {
  // TODO move to block errors
  infer.all_errors(state.buffer.analysis)
  |> list.filter(fn(error) {
    let #(path, reason) = error
    let is_vacant = reason == error.Todo
    let last = case path {
      [] | [_] -> True
      _ -> False
    }
    !{ last && is_vacant }
  })
}

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

pub fn status(state: state.State) {
  case state.message {
    None -> {
      let count = list.length(block_errors(state))
      let infer = case count {
        0 ->
          span.span_styled(
            "✔  ",
            style.default_style() |> style.with_fg(style.Indexed(2)),
          )
        n if n < 10 ->
          span.span_styled(
            "✗" <> int.to_string(n) <> " ",
            style.default_style() |> style.with_fg(style.Indexed(1)),
          )
        _ ->
          span.span_styled(
            "✗9+",
            style.default_style() |> style.with_fg(style.Indexed(1)),
          )
      }
      let space = span.span_plain("· ")
      let focus = case focus_type(state) {
        Ok(isomorphic.Var(-1)) -> span.span_plain("")
        Ok(type_) -> span.span_plain(debug.mono(type_))
        Error(reason) ->
          span.span_styled(
            debug.reason(reason),
            style.default_style() |> style.with_fg(style.Indexed(1)),
          )
      }
      span.line_new([infer, space, focus])
    }
    option.Some(message) ->
      span.line_new([
        span.span_styled(
          "! " <> message,
          style.default_style() |> style.with_fg(style.Indexed(1)),
        ),
      ])
  }
}
