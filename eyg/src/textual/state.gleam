import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import plinth/browser/document
import plinth/browser/selection
import plinth/browser/range
import plinth/browser/element
import eyg/parse/expression
import eyg/parse/lexer
import eyg/parse/parser
import eyg/analysis/type_/isomorphic as t
import eyg/analysis/fast_j as j

pub type State {
  State(source: String, cursor: Option(Int))
}

pub fn source(state: State) {
  state.source
}

fn parse(src) {
  src
  |> lexer.lex()
  |> parser.parse()
}

pub fn information(state) {
  case parse(source(state)) {
    Ok(tree) -> {
      let #(tree, spans) = expression.strip_meta(tree)
      let #(acc, bindings) = j.infer(tree, t.Empty, 0, j.new_state())
      let acc =
        list.map(acc, fn(node) {
          let #(error, typed, effect, env) = node
          let typed = j.resolve(typed, bindings)

          let effect = j.resolve(effect, bindings)
          #(error, typed, effect)
        })
      Ok(#(tree, spans, acc))
    }
    Error(reason) -> Error(reason)
  }
}

pub fn init(_) {
  #(
    State("", None),
    effect.from(fn(d) {
      document.add_event_listener("selectionchange", fn(_) {
        // case selection.get_selection() {
        //   Ok(selection) ->
        //     case selection.get_range_at(selection, 0) {
        //       Ok(range) -> {
        //         io.debug(range.start_offset(range))
        //         io.debug(range.end_offset(range))
        //       }
        //     }
        // }
        // selection API gives number elements
        case document.query_selector("#source") {
          Ok(area) ->
            case element.selection_start(area) {
              Ok(start) -> d(Cursor(start))
              _ -> Nil
            }
          _ -> Nil
        }
        Nil
      })
    }),
  )
  // Nil
}

pub type Update {
  Input(text: String)
  Cursor(start: Int)
  Highlight(#(Int, Int))
}

pub fn update(state, msg) {
  case msg {
    Input(text) -> {
      let state = State(..state, source: text)
      #(state, effect.none())
    }
    Cursor(start) -> {
      let state = State(..state, cursor: Some(start))
      #(state, effect.none())
    }
    Highlight(#(start, end)) -> {
      #(
        state,
        effect.from(fn(_d) {
          case document.query_selector("#source") {
            Ok(area) -> {
              io.debug(area)
              element.focus(area)
              element.set_selection_range(area, start, end)
            }
            _ -> Nil
          }
        }),
      )
    }
  }
}
