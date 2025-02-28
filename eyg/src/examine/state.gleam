import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/compile
import eyg/interpreter/cast
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parse
import eyg/runtime/interpreter/live
import eyg/text/text
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import harness/effect as impl
import javascript/mutable_reference as ref
import lustre/effect
import plinth/browser/document
import plinth/browser/element

pub type View {
  Inference
  Interpret
  Compilation
}

pub type State {
  State(source: String, cursor: Option(Int), view: View)
}

pub fn source(state: State) {
  state.source
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
      list.map(text.line_offsets(source(state)), fn(x) { #(x, []) }),
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
        [_, ..] -> #(acc, Some("bg-yellow-1"))
      }
    },
  ).1
}

pub fn information(state) {
  case parse.from_string(source(state)) {
    Ok(#(tree, _rest)) -> {
      let spans = ir.get_annotation(tree)
      let #(exp, bindings) =
        j.infer(tree, t.Empty, dict.new(), 0, j.new_state())
      let acc = ir.get_annotation(exp)
      let acc =
        list.map(acc, fn(node) {
          let #(error, typed, effect, _env) = node
          let typed = binding.resolve(typed, bindings)

          let effect = binding.resolve(effect, bindings)
          #(error, typed, effect)
        })

      Ok(#(highlights(state, spans, acc), tree, spans, acc))
    }
    Error(reason) -> Error(reason)
  }
}

pub fn interpret(state) {
  let ref = ref.new("")
  let h =
    dict.from_list([
      #("Log", impl.debug_logger().2),
      #("Choose", impl.choose().2),
      #("Render", fn(v) {
        use content <- result.then(cast.as_string(v))
        ref.set(ref, content)
        Ok(v.unit())
      }),
    ])
  case parse.from_string(source(state)) {
    Ok(#(tree, _rest)) -> {
      let #(r, assignments) = live.execute(tree, h)
      let lines = list.map(text.line_offsets(source(state)), fn(x) { #(x, []) })
      let output =
        list.fold(assignments, lines, fn(lines, sp) {
          apply_span(lines, sp.2, Ok(#(sp.0, sp.1)), [])
        })
      let output = case r {
        Ok(_) -> output
        Error(#(reason, span, _env, _stack)) ->
          apply_span(output, span, Error(reason), [])
      }
      Ok(#(output, ref.get(ref)))
    }
    Error(reason) -> Error(reason)
  }
}

pub fn compile(state) {
  case parse.from_string(source(state)) {
    Ok(#(tree, _rest)) -> {
      Ok(compile.to_js(tree, dict.new()))
    }
    Error(reason) -> Error(reason)
  }
}

pub fn init(_) {
  #(
    State("", None, Inference),
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
  Switch(View)
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
    Switch(to) -> {
      let state = State(..state, view: to)
      #(state, effect.none())
    }
  }
}
