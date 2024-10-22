import eyg/analysis/type_/binding as t
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic
import eygir/annotated as a
import eygir/encode
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/string
import morph/action
import morph/analysis
import morph/editable as e
import morph/navigation
import morph/picker
import morph/projection as p
import morph/transformation
import plinth/browser/clipboard

fn render_effect(eff) {
  let #(lift, reply) = eff
  string.concat([debug.mono(lift), " : ", debug.mono(reply)])
}

pub fn render_poly(poly) {
  let #(type_, _) = t.instantiate(poly, 0, dict.new())
  debug.mono(type_)
}

pub type Message {
  KeyDown(String)
  JumpTo(List(Int))
}

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

pub type Buffer =
  #(p.Projection, Mode)

pub fn empty() -> Buffer {
  from(#(p.Exp(e.Vacant("")), []))
}

pub fn from(projection) -> Buffer {
  let mode = Command(None)
  #(projection, mode)
}

pub fn handle_command(key, source, context, effects) {
  let eff =
    effects
    |> list.fold(isomorphic.Empty, fn(acc, new) {
      let #(label, #(lift, reply)) = new
      isomorphic.EffectExtend(label, #(lift, reply), acc)
    })
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

    // Needed for my examples while Gleam doesn't have file embedding
    "Q" -> copy_escaped(source)
    "w" -> call_with(source)
    "E" -> assign_above(source)
    "e" -> assign_to(source)
    "r" -> insert_record(source, context, eff)
    "t" -> insert_tag(source, context, eff)
    // "y" -> copy(source)
    // "Y" -> paste(source)
    // "u" ->
    "i" -> insert_mode(source)
    "o" -> overwrite_record(source, context, eff)
    "p" -> insert_perform(source, effects)
    "a" -> increase(source)
    "s" -> insert_string(source)
    "d" -> delete(source)
    "f" -> insert_function(source)
    "g" -> select_field(source, context, eff)
    "h" -> insert_handle(source, context)
    "j" -> insert_builtin(source, context)
    "k" -> toggle_open(source)
    "l" -> insert_list(source)
    "#" -> insert_reference(source)
    // "z" ->
    // "x" ->
    "c" -> call_function(source, context, eff)
    "v" -> insert_variable(source, context, eff)
    "b" -> insert_binary(source)
    "n" -> insert_integer(source)
    "m" -> insert_case(source, context, eff)
    "M" -> insert_open_case(source, context, eff)
    "," -> extend_before(source, context)
    "." -> spread_list(source)
    _ -> {
      let mode = Command(Some(NoKeyBinding(key)))
      #(source, mode)
    }
  }
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

fn insert_record(source, context, eff) {
  case action.make_record(source, context, eff) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      #(source, Pick(picker.new(value, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create record"))))
  }
}

fn overwrite_record(source, context, eff) {
  case action.overwrite_record(source, context, eff) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      #(source, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create record"))))
  }
}

fn insert_tag(source, context, eff) {
  case action.make_tagged(source, context, eff) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
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

fn insert_perform(source, hints) {
  case action.perform(source) {
    Ok(#(filter, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("perform"))))
  }
}

fn increase(source) {
  case navigation.increase(source) {
    Ok(source) -> #(source, Command(None))
    Error(Nil) -> #(source, Command(Some(ActionFailed("increase selection"))))
  }
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

fn select_field(source, context, eff) {
  case action.select_field(source, context, eff) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      #(source, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("select field"))))
  }
}

fn insert_handle(source, context) {
  case action.handle(source, context) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("perform"))))
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

fn insert_reference(source) {
  case action.insert_reference(source) {
    Ok(#(filter, rebuild)) -> {
      #(source, Pick(picker.new(filter, []), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("insert reference"))))
  }
}

fn call_function(source, context, eff) {
  case action.call_function(source, context, eff) {
    Ok(source) -> #(source, Command(None))
    Error(Nil) -> #(source, Command(Some(ActionFailed("call function"))))
  }
}

fn insert_variable(source, context, eff) {
  case action.insert_variable(source, context, eff) {
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

fn insert_case(source, context, eff) {
  case action.make_case(source, context, eff) {
    Ok(action.Updated(source)) -> #(source, Command(None))
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create match"))))
  }
}

fn insert_open_case(source, context, eff) {
  case action.make_open_case(source, context, eff) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      #(source, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create match"))))
  }
}

fn spread_list(source) {
  case transformation.spread_list(source) {
    Ok(source) -> {
      #(source, Command(None))
    }
    Error(Nil) -> #(source, Command(Some(ActionFailed("create match"))))
  }
}

pub fn references(buffer) {
  let #(projection, _mode) = buffer
  a.list_references(e.to_annotated(p.rebuild(projection), []))
}

pub fn final_scope(proj, context, eff) {
  let path = case p.rebuild(proj) {
    e.Block(assigns, _, _) -> [list.length(assigns)]
    _ -> []
  }
  // This analysis should work on editable
  analysis.env_at(proj, context, eff, path)
  |> listx.key_reject("_")
  |> listx.key_reject("$")
}

pub fn insert_some(buffer, expression) {
  let #(#(focus, zoom), mode) = buffer
  case focus {
    p.Exp(_) -> Ok(#(#(p.Exp(expression), zoom), mode))
    _ -> Error("not focused on an expression")
  }
}

pub fn all_to_json(buffer) {
  let #(proj, _mode) = buffer
  proj
  |> p.rebuild()
  |> e.to_expression
  |> encode.to_json()
}

pub fn focus_to_json(buffer) {
  let #(proj, _mode) = buffer
  let #(focus, _zoom) = proj
  case focus {
    p.Exp(exp) -> {
      let snippet = e.to_expression(exp)
      Ok(encode.to_json(snippet))
    }
    _ -> Error("not on an expression")
  }
}

pub fn all_escaped(buffer) {
  all_to_json(buffer)
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

pub fn copy_escaped(proj) {
  case proj {
    #(p.Exp(expression), _) -> {
      clipboard.write_text(
        encode.to_json(e.to_expression(expression))
        |> string.replace("\\", "\\\\")
        |> string.replace("\"", "\\\""),
      )
      // TODO better copy error
      |> promise.map(io.debug)
      #(proj, Command(None))
    }
    _ -> {
      #(proj, Command(Some(ActionFailed("copy"))))
    }
  }
}
