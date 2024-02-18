import gleam/bit_array
import gleam/io
import gleam/list
import gleam/string
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
import eyg/analysis/type_/binding
import eyg/analysis/inference/levels_j/contextual as j

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

pub fn lines(source) {
  list.reverse(do_lines(source, 0, 0, []))
}

fn do_lines(source, offset, start, acc) {
  case source {
    "\r\n" <> rest -> {
      let offset = offset + 2
      do_lines(rest, offset, offset, [start, ..acc])
    }
    "\n" <> rest -> {
      let offset = offset + 1
      do_lines(rest, offset, offset, [start, ..acc])
    }
    _ ->
      case string.pop_grapheme(source) {
        Ok(#(g, rest)) -> {
          let offset = offset + byte_size(g)
          do_lines(rest, offset, start, acc)
        }
        Error(Nil) -> [start, ..acc]
      }
  }
}

fn byte_size(string: String) -> Int {
  bit_array.byte_size(<<string:utf8>>)
}

pub fn apply_span(lines, span, thing, acc) {
  let #(from, to) = span
  case lines {
    // span is wholly before current line keep building accumulator
    [#(start, values), ..rest] if to <= start -> {
      let acc = [#(start, values), ..acc]
      apply_span(rest, span, thing, acc)
    }
    // span totally after, keep looking 
    [#(start, values), #(end, v), ..rest] if end <= from -> {
      let acc = [#(start, values), ..acc]
      apply_span([#(end, v), ..rest], span, thing, acc)
    }
    [#(start, values), ..rest] -> {
      let values = [thing, ..values]
      apply_span(rest, span, thing, [#(start, values), ..acc])
    }
    [] -> list.reverse(acc)
  }
}

pub fn effect_lines(spans, acc) {
  let assert Ok(pairs) = list.strict_zip(spans, acc)
  let effects =
    list.filter_map(pairs, fn(p) {
      let #(span, #(_, _, effect)) = p
      case effect {
        t.Empty -> Error(Nil)
        _ -> Ok(#(span, effect))
      }
    })
}

pub fn highlights(state, spans, acc) {
  let with_effects =
    list.fold(
      effect_lines(spans, acc),
      list.map(lines(source(state)), fn(x) { #(x, []) }),
      fn(lines, sp) { apply_span(lines, sp.0, sp.1, []) },
    )

  list.map_fold(
    with_effects,
    #([], [
      "bg-orange-2", "bg-green-1", "bg-purple-3", "bg-blue-2", "bg-yellow-3",
    ]),
    fn(acc, line) {
      let #(_start, effects) = line
      case effects {
        [] -> #(acc, None)
        [t.EffectExtend(label, _, _), ..] -> {
          let #(keyed, left) = acc
          case list.key_find(keyed, label) {
            Ok(value) -> #(acc, Some(value))
            Error(Nil) -> {
              let assert [v, ..left] = left
              let keyed = [#(label, v), ..keyed]
              #(#(keyed, left), Some(v))
            }
          }
        }
      }
    },
  ).1
}

pub fn information(state) {
  case parse(source(state)) {
    Ok(tree) -> {
      let #(tree, spans) = expression.strip_meta(tree)
      let #(acc, bindings) = j.infer(tree, t.Empty, 0, j.new_state())
      let acc =
        list.map(acc, fn(node) {
          let #(error, typed, effect, env) = node
          let typed = binding.resolve(typed, bindings)

          let effect = binding.resolve(effect, bindings)
          #(error, typed, effect)
        })

      Ok(#(highlights(state, spans, acc), tree, spans, acc))
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
