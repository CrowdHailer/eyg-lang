import drafting/view/picker
import drafting/view/utilities
import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding as t
import eyg/analysis/type_/binding/debug
import eygir/annotated
import eygir/decode
import eygir/encode
import gleam/dict
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/effect
import morph/action
import morph/analysis
import morph/editable as e
import morph/navigation
import morph/projection as p
import morph/transformation
import plinth/browser/clipboard

// TODO spotless shouldn't depend on drafing and vica versa

pub type Failure {
  NoKeyBinding(key: String)
  ActionFailed(action: String)
}

pub type Mode {
  Command(failure: Option(Failure))
  Pick(picker: picker.Picker, rebuild: fn(String) -> p.Projection)
  EditText(String, fn(String) -> p.Projection)
  EditInteger(Int, fn(Int) -> p.Projection)
}

// Session could be renamed buffer
// TODO rename this buffer
pub type State {
  State(
    context: analysis.Context,
    source: p.Projection,
    mode: Mode,
    analysis: Option(analysis.Analysis),
  )
}

pub fn init(_) {
  let source = p.focus_at(e.Vacant(""), [])
  // builtins are all qualified so no bindings needed
  let context = analysis.Context(dict.new(), [], contextual.builtins())
  let mode = Command(None)
  let state = State(context, source, mode, None)
  #(state, effect.none())
}

pub type Message {
  KeyDown(String)
  UpdateInput(String)
  Submit
  UpdatePicker(picker.Message)
  Loading(Promise(Result(e.Expression, String)))
  Loaded(p.Projection)
  JumpTo(List(Int))
}

fn search_vacant(source) {
  let next = navigation.next(source)
  case next {
    #(p.Exp(e.Vacant("")), _zoom) -> next
    // If at the top break, can search again to loop around
    #(p.Exp(_), []) -> next
    _ -> search_vacant(next)
  }
}

// e -> extend
// a -> assign
// q -> increase
// This is the new concept of a session state but it's worth working separatly with picking requirements
// in the cases where you know ther is a picker
// Don't think I want to add the concept of Yanking into the buffer
// TODO the is a A/B type here for new source or new mode

pub fn handle_command(key, source, context) {
  case key {
    "ArrowRight" -> #(navigation.next(source), Command(None))
    "ArrowLeft" -> #(navigation.previous(source), Command(None))
    "ArrowUp" ->
      case navigation.move_up(source) {
        Ok(source) -> #(source, Command(None))
        Error(Nil) -> #(source, Command(Some(ActionFailed("move up"))))
      }
    "ArrowDown" ->
      case navigation.move_down(source) {
        Ok(source) -> #(source, Command(None))
        Error(Nil) -> #(source, Command(Some(ActionFailed("move down"))))
      }
    // space is fine for seek because the command pallat is for beginners
    " " -> #(search_vacant(source), Command(None))

    "w" -> call_with(source)
    "E" -> assign_above(source)
    "e" -> assign_to(source)
    "r" -> insert_record(source, context)
    "t" -> insert_tag(source, context)
    "y" -> extend_before(source, context)
    // "u" ->
    "i" -> insert_mode(source)
    "o" -> overwrite_record(source, context)
    "p" -> insert_perform(source, context)
    "a" -> increase(source)
    "s" -> insert_string(source)
    "d" -> delete(source)
    "f" -> insert_function(source)
    "g" -> select_field(source, context)
    // "h" ->
    "j" -> insert_builtin(source, context)
    "k" -> toggle_open(source)
    "l" -> insert_list(source)
    // "z" ->
    // "x" ->
    "c" -> call_function(source, context)
    "v" -> insert_variable(source, context)
    "b" -> insert_binary(source)
    "n" -> insert_integer(source)
    "m" -> insert_case(source, context)
    "M" -> insert_open_case(source, context)
    _ -> {
      let mode = Command(Some(NoKeyBinding(key)))
      #(source, mode)
    }
  }
}

// Should existing mode be in live/working state or work only happens in command mode
// Or a list of tasks on the side
// fn copy(source) {
//   let #(focus, zoom) = source
//   case focus {
//     p.Exp(exp) -> {
//       let snippet = e.to_expression(exp)
//       let dump = encode.to_json(snippet)
//       promise.map(clipboard.write_text(dump), fn(result) {
//         case result {
//           Ok(Nil) -> Nil
//           Error(reason) -> {
//             io.debug(reason)
//             Nil
//           }
//         }
//       })
//       #(source, Command(None))
//     }
//     _ -> #(source, Command(Some(ActionFailed("copy"))))
//   }
// }

// fn paste(source) {
//   clipboard.read_text
//   todo
// }

fn toggle_open(source) {
  let #(focus, zoom) = source
  let focus = case focus {
    p.Exp(e.Block(assigns, then, open)) -> p.Exp(e.Block(assigns, then, !open))
    p.Assign(label, e.Block(assigns, inner, open), pre, post, final) ->
      p.Assign(label, e.Block(assigns, inner, !open), pre, post, final)
    _ -> focus
  }
  let source = #(focus, zoom)
  #(source, Command(None))
}

fn call_with(source) {
  case transformation.call_with(source) {
    Ok(source) -> #(source, Command(None))
    Error(Nil) -> #(source, Command(Some(ActionFailed("call as argument"))))
  }
}

fn assign_to(source) {
  case transformation.assign(source) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      #(source, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("assign to"))))
  }
}

fn assign_above(source) {
  case transformation.assign_before(source) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      #(source, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("assign above"))))
  }
}

fn insert_record(source, context) {
  case action.make_record(source, context) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.render_type)
      #(source, Pick(picker.new(value, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create record"))))
  }
}

fn overwrite_record(source, context) {
  case action.overwrite_record(source, context) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.render_type)
      #(source, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create record"))))
  }
}

fn insert_tag(source, context) {
  case action.make_tagged(source, context) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.render_type)
      #(source, Pick(picker.new(value, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("tag expression"))))
  }
}

fn extend_before(source, context) {
  case action.extend_before(source, context) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("extend"))))
  }
}

fn insert_mode(source) {
  case source {
    #(p.Exp(e.String(value)), zoom) -> #(
      source,
      EditText(value, fn(value) { #(p.Exp(e.String(value)), zoom) }),
    )
    _ ->
      case p.text(source) {
        Ok(#(value, rebuild)) -> #(source, Pick(picker.new(value, []), rebuild))
        Error(Nil) -> #(source, Command(Some(ActionFailed("edit"))))
      }
  }
}

fn insert_perform(source, context) {
  case action.perform(source, context) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("perform"))))
  }
}

fn increase(source) {
  #(navigation.increase(source), Command(None))
}

fn insert_string(source) {
  case transformation.string(source) {
    Ok(#(value, rebuild)) -> #(source, EditText(value, rebuild))
    Error(Nil) -> #(source, Command(Some(ActionFailed("create text"))))
  }
}

fn delete(source) {
  #(transformation.delete(source), Command(None))
}

fn insert_function(source) {
  case transformation.function(source) {
    Ok(rebuild) -> #(source, Pick(picker.new("", []), rebuild))
    Error(Nil) -> #(source, Command(Some(ActionFailed("create function"))))
  }
}

fn select_field(source, context) {
  case action.select_field(source, context) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.render_type)
      #(source, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("select field"))))
  }
}

fn insert_builtin(source, context) {
  case action.insert_builtin(source, context) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("insert builtin"))))
  }
}

fn insert_list(source) {
  case transformation.list(source) {
    Ok(source) -> #(source, Command(None))
    Error(Nil) -> #(source, Command(Some(ActionFailed("create list"))))
  }
}

fn call_function(source, context) {
  case action.call_function(source, context) {
    Ok(source) -> #(source, Command(None))
    Error(Nil) -> #(source, Command(Some(ActionFailed("call function"))))
  }
}

fn insert_variable(source, context) {
  case action.insert_variable(source, context) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create binary"))))
  }
}

fn insert_binary(source) {
  case transformation.binary(source) {
    Ok(#(value, rebuild)) -> #(rebuild(value), Command(None))
    Error(Nil) -> #(source, Command(Some(ActionFailed("create binary"))))
  }
}

fn insert_integer(source) {
  case transformation.integer(source) {
    Ok(#(value, rebuild)) -> #(source, EditInteger(value, rebuild))
    Error(Nil) -> #(source, Command(Some(ActionFailed("create number"))))
  }
}

fn insert_case(source, context) {
  case action.make_case(source, context) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create match"))))
  }
}

fn insert_open_case(source, context) {
  case action.make_open_case(source, context) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.render_type)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create match"))))
  }
}

fn render_effect(eff) {
  let #(lift, reply) = eff
  string.concat([debug.render_type(lift), " : ", debug.render_type(reply)])
}

fn render_poly(poly) {
  let #(type_, _) = t.instantiate(poly, 0, dict.new())
  debug.render_type(type_)
}

pub fn copy(source) {
  let #(focus, _zoom) = source
  case focus {
    p.Exp(exp) -> {
      let snippet = e.to_expression(exp)
      let dump = encode.to_json(snippet)
      use result <- promise.map(clipboard.write_text(dump))
      case result {
        Ok(Nil) -> Ok(Nil)
        Error(reason) -> Error(reason)
      }
    }
    _ -> promise.resolve(Error("not on an expression"))
  }
}

pub fn paste(source) {
  use result <- promise.map(clipboard.read_text())
  case result {
    Ok(text) ->
      case source {
        #(p.Exp(_), zoom) -> {
          let assert Ok(snippet) = decode.from_json(text)
          let exp = annotated.add_annotation(snippet, Nil)
          let exp = e.from_annotated(exp)
          Ok(#(p.Exp(exp), zoom))
        }
        _ -> Error("not in expression")
      }
    Error(reason) -> Error(reason)
  }
}

// TODO maybe rename handle
pub fn update(state, message) {
  let State(context, source, mode, analysis) = state
  utilities.update_focus()
  case message {
    // async so outside buffer logic
    KeyDown("Enter") -> {
      let state =
        State(..state, analysis: Some(analysis.analyse(source, context)))
      #(state, effect.none())
    }
    KeyDown("q") -> {
      let task = fn(d) {
        use result <- promisex.aside(copy(source))
        case result {
          Ok(Nil) -> Nil
          Error(reason) -> {
            io.debug(reason)
            Nil
          }
        }
      }
      #(state, effect.from(task))
    }

    KeyDown("Q") -> {
      let task = fn(d) {
        use result <- promisex.aside(paste(source))
        case result {
          Ok(source) -> d(Loaded(source))
          Error(_reason) -> panic as "failed to paste"
        }
      }
      #(state, effect.from(task))
    }
    KeyDown(key) -> {
      let #(source, mode) = handle_keydown(key, context, source, mode)
      let state = State(..state, source: source, mode: mode, analysis: None)
      #(state, effect.none())
    }
    UpdateInput(new) -> {
      let mode = handle_input(mode, new)
      let state = State(..state, mode: mode)
      #(state, effect.none())
    }
    Submit -> {
      let state = case handle_submit(mode) {
        Ok(#(source, mode)) ->
          State(..state, source: source, mode: mode, analysis: None)
        Error(Nil) -> state
      }
      #(state, effect.none())
    }

    Loading(task) -> #(
      state,
      effect.from(fn(d) {
        promise.map(task, fn(r) {
          case r {
            Ok(editable) -> d(Loaded(p.focus_at(editable, [])))
            Error(_) -> Nil
          }
        })
        Nil
      }),
    )
    Loaded(source) -> {
      let state = State(context, source, Command(None), None)
      #(state, effect.none())
    }
    UpdatePicker(picker.Updated(picker)) -> {
      let assert Pick(_, rebuild) = mode
      let mode = Pick(picker, rebuild)
      let state = State(..state, mode: mode)
      #(state, effect.none())
    }
    UpdatePicker(picker.Decided(value)) -> {
      let assert Pick(_, rebuild) = mode
      let mode = Command(None)
      let state = State(..state, source: rebuild(value), mode: mode)
      #(state, effect.none())
    }
    UpdatePicker(picker.Dismissed) -> {
      let mode = Command(None)
      let state = State(..state, mode: mode)
      #(state, effect.none())
    }
    JumpTo(path) -> {
      let editable = p.rebuild(source)
      let source = p.focus_at(editable, path)
      let state = State(..state, source: source, mode: Command(None))
      #(state, effect.none())
    }
  }
}

pub fn handle_keydown(key, context, source, mode) {
  case mode, key {
    _, "Escape" -> #(source, Command(None))

    Command(_failure), _any -> handle_command(key, source, context)

    _, _ -> #(source, mode)
  }
}

pub fn handle_input(mode, new) {
  case mode {
    Command(message) -> {
      io.debug("input update shouldn't happen in command mode")
      Command(message)
    }
    Pick(picker, rebuild) -> {
      io.debug("input update shouldn't happen in command mode")
      Pick(picker, rebuild)
    }

    EditText(_old, rebuild) -> EditText(new, rebuild)
    EditInteger(old, rebuild) ->
      case int.parse(new) {
        Ok(new) -> EditInteger(new, rebuild)
        Error(Nil) -> EditInteger(old, rebuild)
      }
  }
}

pub fn handle_submit(mode) {
  case mode {
    Command(_message) -> {
      io.debug("submit shouldn't happen in command mode")
      Error(Nil)
    }
    Pick(_picker, _rebuild) -> {
      io.debug("submit shouldn't happen in command mode")
      Error(Nil)
    }

    EditText(value, rebuild) -> {
      let mode = Command(None)
      Ok(#(rebuild(value), mode))
    }
    EditInteger(value, rebuild) -> {
      let mode = Command(None)
      Ok(#(rebuild(value), mode))
    }
  }
}
