//// The snippet component is the base of editing context for EYG programs,
//// for example the Reload, Shell and example components
//// 
//// It builds upon the morph library, it aims to be separate from type checking and runtime considerations
//// 
//// This separation is not perfect as edits want to be informed by type information.
//// Type information is optional as type checking can be slow and we want to be able to edit programs without type information rather than blocking
//// 
//// Some information for helping with edits is not just based on the type situation.
//// 
////  1. Releases can be identified by their hash, but we want to show the package name and version number
////    The index on analysis carries this extra data
////  2. Most functions are defined in an effect free context, hence the suggested list of effects is hardcoded
////    It is part of the context on the analysis
//// 
//// The type checker shouldn't need to know all the different states a release might be in. i.e. not requested yet.
//// I also don't want to pass an arbitray function from ref to promise of result of type
//// Doing so would make type checking async even when all referenes are loaded
//// Instead we inefficiently pass a map of references in.
//// Inefficient because it involves building from the whole cache.
//// 
//// ## Improvements
//// 
////  - The type checking context should always be available even if analysis isn't
////  - Inversion of control so that the typechecking has a callback that is called when a reference is needed.
////    This is ok in the morph analysis that is explicitly for editor help

import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/dynamicx
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/string
import gleroglero/outline
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/action
import morph/analysis
import morph/editable as e
import morph/input
import morph/lustre/frame
import morph/lustre/highlight
import morph/lustre/render
import morph/navigation
import morph/picker
import morph/projection as p
import morph/transformation
import morph/utils
import plinth/browser/clipboard
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/browser/event as pevent
import plinth/browser/window
import plinth/javascript/console
import website/components/autocomplete
import website/components/snippet/menu
import website/components/vertical_menu

pub const neo_blue_3 = "#87ceeb"

pub const neo_green_3 = "#90ee90"

pub const neo_orange_4 = "#ff6b6b"

const embed_area_styles = [
  #("box-shadow", "6px 6px black"),
  #("border-style", "solid"),
  #(
    "font-family",
    "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
  ),
  #("background-color", "rgb(255, 255, 255)"),
  #("border-color", "rgb(0, 0, 0)"),
  #("border-width", "1px"),
  #("flex-direction", "column"),
  #("display", "flex"),
  #("margin-bottom", "1.5rem"),
  #("margin-top", ".5rem"),
]

const code_area_styles = [
  #("outline", "2px solid transparent"),
  #("outline-offset", "2px"),
  #("padding", ".5rem"),
  #("white-space", "nowrap"),
  #("overflow", "auto"),
  #("margin-top", "auto"),
  #("margin-bottom", "auto"),
  #("height", "100%"),
]

pub fn footer_area(color, contents) {
  h.div(
    [
      a.style([
        #("border-color", color),
        #("padding-left", ".5rem"),
        #("padding-right", ".5rem"),
        #("border-style", "solid"),
        #("border-width", "2px"),
        #("overflow", "auto"),
      ]),
    ],
    contents,
  )
}

pub type Status {
  Idle
  Editing(Mode)
}

pub type History {
  History(undo: List(p.Projection), redo: List(p.Projection))
}

pub type Failure {
  NoKeyBinding(key: String)
  ActionFailed(action: String)
  // RunFailed(istate.Debug(Path))
}

pub type Mode {
  Command
  Pick(picker: picker.Picker, rebuild: fn(String) -> p.Projection)
  SelectRelease(
    autocomplete: autocomplete.State(#(String, Int, String)),
    rebuild: fn(String, Int, String) -> p.Projection,
  )
  EditText(String, fn(String) -> p.Projection)
  EditInteger(Int, fn(Int) -> p.Projection)
}

pub type Snippet {
  Snippet(
    // ------------------
    // Editor state
    status: Status,
    expanding: Option(List(Int)),
    menu: menu.State,
    // edit history
    history: History,
    projection: p.Projection,
    // editable is derived from projection
    editable: e.Expression,
    // ---------------------
    // analaysis can be cached as an object
    analysis: Option(analysis.Analysis),
  )
}

pub fn init(editable) {
  let editable = e.open_all(editable)
  let proj = navigation.first(editable)
  Snippet(
    status: Idle,
    expanding: None,
    menu: menu.init(),
    history: History([], []),
    projection: proj,
    editable: editable,
    analysis: None,
  )
}

pub fn active(editable) {
  let editable = e.open_all(editable)
  let proj = navigation.first(editable)
  Snippet(
    Editing(Command),
    expanding: None,
    menu: menu.init(),
    history: History([], []),
    projection: proj,
    editable: editable,
    analysis: None,
  )
}

pub fn source(state) {
  let Snippet(editable:, ..) = state
  editable
}

pub fn references(state) {
  e.to_annotated(source(state), []) |> ir.list_references()
}

pub type Message {
  UserFocusedOnCode
  UserPressedCommandKey(String)
  UserClickedPath(List(Int))
  UserClickedCode(List(Int))
  MessageFromInput(input.Message)
  MessageFromPicker(picker.Message)
  SelectReleaseMessage(autocomplete.Message)
  MessageFromMenu(menu.Message)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
}

pub fn user_message(message) {
  case message {
    ClipboardReadCompleted(_) | ClipboardWriteCompleted(_) -> False
    _ -> True
  }
}

pub type Effect {
  Nothing
  Failed(Failure)
  // This always assume code hasn't changed
  ReturnToCode
  FocusOnInput
  ToggleHelp
  MoveAbove
  MoveBelow
  WriteToClipboard(String)
  ReadFromClipboard
  NewCode
  Confirm
}

pub fn focus_on_buffer() {
  window.request_animation_frame(fn(_) {
    case document.query_selector("[autofocus]") {
      Ok(el) -> dom_element.focus(el)
      Error(Nil) -> Nil
    }
  })
  Nil
}

@external(javascript, "../../website_ffi.mjs", "selectAllInput")
fn select_all_input(element: dom_element.Element) -> Nil

pub fn focus_on_input() {
  window.request_animation_frame(fn(_) {
    case document.query_selector("[autofocus]") {
      Ok(el) -> {
        dom_element.focus(el)
        // This can only be done when we move to a new focus
        // error is something specifically to do with numbers
        // dom_element.set_selection_range(el, 0, -1)
        select_all_input(el)
      }
      Error(Nil) -> Nil
    }
  })
  Nil
}

pub fn write_to_clipboard(text) {
  promise.map(clipboard.write_text(text), ClipboardWriteCompleted)
}

pub fn read_from_clipboard() {
  promise.map(clipboard.read_text(), ClipboardReadCompleted)
  // TODO make busy
}

fn navigate_source(proj, state) {
  let status = Editing(Command)
  let state = Snippet(..state, status: status, projection: proj)
  #(state, Nothing)
}

fn update_source(proj, state) {
  let Snippet(projection: old, history: history, ..) = state
  let editable = p.rebuild(proj)
  let History(undo: undo, ..) = history
  let undo = [old, ..undo]
  let history = History(undo: undo, redo: [])
  let status = Editing(Command)

  let analysis = None
  //   Some(do_analysis(editable, state.scope, state.cache, state.effects))
  Snippet(
    ..state,
    status: status,
    projection: proj,
    editable: editable,
    history: history,
    analysis:,
    // evaluated: evaluate(editable, state.scope, state.cache),
  // run: NotRunning,
  )
}

fn update_source_from_buffer(proj, state) {
  #(update_source(proj, state), NewCode)
}

fn update_source_from_pallet(proj, state) {
  #(update_source(proj, state), NewCode)
}

fn return_to_buffer(state) {
  let state = Snippet(..state, status: Editing(Command))
  #(state, ReturnToCode)
}

fn change_mode(state, mode) {
  let status = Editing(mode)
  let state = Snippet(..state, status: status)
  #(state, FocusOnInput)
}

fn keep_editing(state, mode) {
  let state = Snippet(..state, status: Editing(mode))
  #(state, Nothing)
}

fn action_failed(state, error) {
  #(state, Failed(ActionFailed(error)))
}

pub fn update(state, message) {
  let Snippet(status: status, ..) = state
  case message, status {
    UserFocusedOnCode, Idle -> #(
      Snippet(..state, status: Editing(Command)),
      Nothing,
    )
    UserFocusedOnCode, Editing(_) -> #(
      Snippet(..state, status: Editing(Command)),
      Nothing,
    )
    UserPressedCommandKey(key), Editing(Command) -> {
      case key {
        "ArrowRight" -> move_right(state)
        "ArrowLeft" -> move_left(state)
        "ArrowUp" -> move_up(state)
        "ArrowDown" -> move_down(state)
        " " -> search_vacant(state)
        // Needed for my examples while Gleam doesn't have file embedding
        "Q" -> copy_escaped(state)
        "w" -> call_with(state)
        "E" -> assign_above(state)
        "e" -> assign_to(state)
        "r" -> insert_record(state)
        "R" -> insert_empty_record(state)
        "t" -> insert_tag(state)
        "y" -> copy(state)
        "Y" -> paste(state)
        // "u" ->
        "i" -> insert_mode(state)
        "o" -> overwrite_record(state)
        "p" -> insert_perform(state)
        "a" -> increase(state)
        "s" -> insert_string(state)
        "d" | "Delete" -> delete(state)
        "f" -> insert_function(state)
        "g" -> select_field(state)
        "h" -> insert_handle(state)
        "j" -> insert_builtin(state)
        "k" -> toggle_open(state)
        "l" -> insert_list(state)
        "@" -> insert_release(state)
        "#" -> insert_reference(state)
        "z" -> undo(state)
        "Z" -> redo(state)
        // "x" ->
        "c" -> call_function(state)
        "v" -> insert_variable(state)
        "b" -> insert_binary(state)
        "n" -> insert_integer(state)
        "m" -> insert_case(state)
        "M" -> insert_open_case(state)
        "," -> extend_before(state)
        "EXTEND AFTER" -> extend_after(state)
        "." -> spread_list(state)
        "TOGGLE SPREAD" -> toggle_spread(state)
        "TOGGLE OTHERWISE" -> toggle_otherwise(state)

        "?" -> #(state, ToggleHelp)
        "Enter" -> confirm(state)
        _ -> #(state, Failed(NoKeyBinding(key)))
      }
    }
    UserPressedCommandKey(key), _ -> action_failed(state, key)
    UserClickedPath(path), _ ->
      navigate_source(p.focus_at(state.editable, path), state)

    // This is unhelpful as hard if big blocks are selected
    // case listx.starts_with(path, p.path(proj)) && p.path(proj) != [] {
    UserClickedCode(path), _ -> {
      let state = Snippet(..state, status: Editing(Command))
      case state.projection, p.path(state.projection) == path {
        #(p.Assign(p.AssignStatement(_), _, _, _, _), _), True ->
          toggle_open(state)
        _, _ ->
          case
            // listx.starts_with(path, p.path(state.projection))
            // path expanding real just means it was the last thing clicked
            Some(path) == state.expanding && p.path(state.projection) != []
          {
            True -> increase(state)
            False -> {
              let state = Snippet(..state, expanding: Some(path))
              navigate_source(p.focus_at(state.editable, path), state)
            }
          }
      }
    }

    MessageFromInput(message), Editing(EditText(value, rebuild)) ->
      case input.update_text(value, message) {
        input.Continue(value) -> keep_editing(state, EditText(value, rebuild))
        input.Confirmed(value) ->
          update_source_from_pallet(rebuild(value), state)
        input.Cancelled -> return_to_buffer(state)
      }
    MessageFromInput(message), Editing(EditInteger(value, rebuild)) ->
      case input.update_number(value, message) {
        input.Continue(value) ->
          keep_editing(state, EditInteger(value, rebuild))
        input.Confirmed(value) ->
          update_source_from_pallet(rebuild(value), state)
        input.Cancelled -> return_to_buffer(state)
      }
    MessageFromInput(_), _ -> panic as "shouldn't reach input message"
    MessageFromPicker(picker.Updated(picker)), Editing(Pick(_, rebuild)) ->
      keep_editing(state, Pick(picker, rebuild))
    MessageFromPicker(picker.Decided(value)), Editing(Pick(_, rebuild)) ->
      update_source_from_pallet(rebuild(value), state)
    MessageFromPicker(picker.Dismissed), Editing(Pick(_, _rebuild)) ->
      return_to_buffer(state)
    MessageFromPicker(_), _ -> panic as "shouldn't reach picker message"
    SelectReleaseMessage(message), Editing(SelectRelease(autocomplete, rebuild))
    -> {
      let #(autocomplete, event) = autocomplete.update(autocomplete, message)
      case event {
        autocomplete.Nothing ->
          keep_editing(state, SelectRelease(autocomplete, rebuild))
        autocomplete.ItemSelected(#(p, r, cid)) ->
          update_source_from_pallet(rebuild(p, r, cid), state)
        autocomplete.Dismiss -> return_to_buffer(state)
      }
    }
    SelectReleaseMessage(_message), _ ->
      panic as "shouldn;t have select release message in this state"

    MessageFromMenu(message), _ -> {
      let #(menu, action) = menu.update(state.menu, message)
      let state = Snippet(..state, menu: menu)
      case action {
        None -> #(state, Nothing)
        Some(key) -> update(state, UserPressedCommandKey(key))
      }
    }
    // UserClickRunEffects, _ -> run_effects(state)
    // RuntimeRepliedFromExternalEffect(#(task_id, reply)), _ ->
    //   run_handle_effect(state, task_id, reply)
    ClipboardReadCompleted(return), _ -> {
      let assert Editing(Command) = status
      case return {
        Ok(text) ->
          case dag_json.from_block(bit_array.from_string(text)) {
            Ok(expression) -> {
              let assert #(p.Exp(_), zoom) = state.projection
              let proj = #(p.Exp(e.from_annotated(expression)), zoom)
              update_source_from_buffer(proj, state)
            }
            Error(_) -> action_failed(state, "paste")
          }
        Error(_) -> action_failed(state, "paste")
      }
    }
    ClipboardWriteCompleted(return), _ ->
      case return {
        Ok(Nil) -> #(state, Nothing)
        Error(_) -> action_failed(state, "paste")
      }
  }
}

fn move_right(state) {
  let Snippet(projection: proj, ..) = state
  navigate_source(navigation.next(proj), state)
}

fn move_left(state) {
  let Snippet(projection: proj, ..) = state
  navigate_source(navigation.previous(proj), state)
}

fn move_up(state) {
  let Snippet(projection: proj, ..) = state

  case navigation.move_up(proj) {
    Ok(new) -> navigate_source(navigation.next(new), state)
    Error(Nil) -> #(state, MoveAbove)
  }
}

fn move_down(state) {
  let Snippet(projection: proj, ..) = state

  case navigation.move_down(proj) {
    Ok(new) -> navigate_source(navigation.next(new), state)
    Error(Nil) -> #(state, MoveBelow)
  }
}

fn copy(state) {
  let Snippet(projection: proj, ..) = state

  case proj {
    #(p.Exp(expression), _) -> {
      let assert Ok(text) =
        e.to_annotated(expression, [])
        |> dag_json.to_block
        |> bit_array.to_string
      #(state, WriteToClipboard(text))
    }
    _ -> action_failed(state, "copy")
  }
}

fn paste(state) {
  #(state, ReadFromClipboard)
}

fn search_vacant(state) {
  let Snippet(projection: proj, ..) = state
  let bottom = p.zoom_in(proj)
  let initial = p.path(bottom)
  case do_search_vacant(bottom, initial) {
    Ok(new) -> navigate_source(new, state)
    Error(Nil) -> action_failed(state, "jump to error")
  }
}

fn do_search_vacant(proj, initial) {
  let next = navigation.next(proj)
  case p.path(next) == initial {
    True -> Error(Nil)
    False ->
      case next {
        #(p.Exp(e.Vacant), _zoom) -> Ok(next)
        // If at the top break, can search again to loop around
        #(p.Exp(_), []) -> Error(Nil)
        _ -> do_search_vacant(next, initial)
      }
  }
}

fn toggle_open(state) {
  let Snippet(projection: proj, ..) = state

  let proj = navigation.toggle_open(proj)
  navigate_source(proj, state)
}

fn call_with(state) {
  let Snippet(projection: proj, ..) = state
  case transformation.call_with(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "call as argument")
  }
}

fn assign_to(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.assign(proj) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      change_mode(state, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> action_failed(state, "assign to")
  }
}

fn assign_above(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.assign_before(proj) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      change_mode(state, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> action_failed(state, "assign above")
  }
}

fn insert_record(state) {
  let Snippet(projection: proj, analysis:, ..) = state
  case action.make_record(proj, analysis) {
    Ok(action.Updated(proj)) -> update_source_from_buffer(proj, state)
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(value, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create record")
  }
}

fn insert_empty_record(state) {
  let Snippet(projection:, ..) = state
  case action.make_empty_record(projection) {
    Ok(projection) -> update_source_from_buffer(projection, state)
    Error(Nil) -> action_failed(state, "create record")
  }
}

fn overwrite_record(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.overwrite_record(proj, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create record")
  }
}

fn insert_tag(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.make_tagged(proj, analysis) {
    Ok(action.Updated(new)) -> update_source_from_buffer(new, state)
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(value, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "tag expression")
  }
}

fn extend_before(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.extend_before(proj, analysis) {
    Ok(action.Updated(new)) -> update_source_from_buffer(new, state)
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "extend")
  }
}

fn extend_after(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.extend_after(proj, analysis) {
    Ok(action.Updated(new)) -> update_source_from_buffer(new, state)
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "extend")
  }
}

fn insert_mode(state) {
  let Snippet(projection: proj, ..) = state

  case proj {
    #(p.Exp(e.String(value)), zoom) ->
      change_mode(
        state,
        EditText(value, fn(value) { #(p.Exp(e.String(value)), zoom) }),
      )
    _ ->
      case p.text(proj) {
        Ok(#(value, rebuild)) ->
          change_mode(state, Pick(picker.new(value, []), rebuild))
        Error(Nil) -> action_failed(state, "edit")
      }
  }
}

fn insert_perform(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.perform(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "perform")
  }
}

fn increase(state) {
  let Snippet(projection: proj, ..) = state

  case navigation.increase(proj) {
    Ok(new) -> navigate_source(new, state)
    Error(Nil) -> action_failed(state, "increase selection")
  }
}

fn insert_string(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.string(proj) {
    Ok(#(value, rebuild)) -> change_mode(state, EditText(value, rebuild))
    Error(Nil) -> action_failed(state, "create text")
  }
}

fn delete(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.delete(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "delete")
  }
}

fn insert_function(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.function(proj) {
    Ok(rebuild) -> change_mode(state, Pick(picker.new("", []), rebuild))
    Error(Nil) -> action_failed(state, "create function")
  }
}

fn select_field(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.select_field(proj, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "select field")
  }
}

fn insert_handle(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.handle(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "perform")
  }
}

fn insert_builtin(state) {
  let Snippet(projection: proj, ..) = state

  case action.insert_builtin(proj, contextual.builtins()) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert builtin")
  }
}

fn insert_list(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.list(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "create list")
  }
}

fn insert_release(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  let index = case analysis {
    Some(analysis.Analysis(context:, ..)) -> context.index
    None -> []
  }

  case action.insert_named_reference(proj) {
    Ok(#(_filter, rebuild)) -> {
      change_mode(
        state,
        SelectRelease(autocomplete.init(index, release_to_string), rebuild),
      )
    }
    Error(Nil) -> action_failed(state, "insert reference")
  }
}

fn release_to_string(release) {
  let #(package, release, _) = release
  package <> ":" <> int.to_string(release)
}

fn insert_reference(state) {
  let Snippet(projection: proj, ..) = state

  case action.insert_reference(proj) {
    Ok(#(filter, rebuild)) -> {
      change_mode(state, Pick(picker.new(filter, []), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert named reference")
  }
}

fn call_function(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.call_function(proj, analysis) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "call function")
  }
}

fn insert_variable(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.insert_variable(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert variable")
  }
}

fn insert_binary(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.binary(proj) {
    Ok(#(value, rebuild)) -> update_source_from_buffer(rebuild(value), state)
    Error(Nil) -> action_failed(state, "create binary")
  }
}

fn insert_integer(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.integer(proj) {
    Ok(#(value, rebuild)) -> change_mode(state, EditInteger(value, rebuild))
    Error(Nil) -> action_failed(state, "create number")
  }
}

fn insert_case(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.make_case(proj, analysis) {
    Ok(action.Updated(new)) -> update_source_from_buffer(new, state)
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create match")
  }
}

fn insert_open_case(state) {
  let Snippet(projection: proj, analysis:, ..) = state

  case action.make_open_case(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create match")
  }
}

fn spread_list(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.spread_list(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "spread list")
  }
}

fn toggle_spread(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.toggle_spread(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "toggle spread")
  }
}

fn toggle_otherwise(state) {
  let Snippet(projection: proj, ..) = state

  case transformation.toggle_otherwise(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "create match")
  }
}

fn undo(state) {
  let Snippet(projection: proj, history: history, ..) = state
  case history.undo {
    [] -> action_failed(state, "undo")
    [saved, ..rest] -> {
      let editable = p.rebuild(saved)
      let analysis = None
      // TODO
      // Some(do_analysis(editable, state.scope, state.cache, state.effects))
      let history = History(undo: rest, redo: [proj, ..history.redo])
      let status = Editing(Command)
      let state =
        Snippet(
          ..state,
          status: status,
          projection: saved,
          editable:,
          history: history,
          analysis:,
          // evaluated: evaluate(editable, state.scope, state.cache),
        // run: NotRunning,
        )
      #(state, Nothing)
    }
  }
}

fn redo(state) {
  let Snippet(projection: proj, history: history, ..) = state
  case history.redo {
    [] -> action_failed(state, "redo")
    [saved, ..rest] -> {
      let editable = p.rebuild(saved)
      let analysis = None
      // Some(do_analysis(editable, state.scope, state.cache, state.effects))
      let history = History(undo: [proj, ..history.undo], redo: rest)
      let status = Editing(Command)
      let state =
        Snippet(
          ..state,
          status: status,
          projection: saved,
          editable:,
          history: history,
          analysis:,
          // evaluated: evaluate(editable, state.scope, state.cache),
        // run: NotRunning,
        )
      #(state, Nothing)
    }
  }
}

pub fn copy_escaped(state) {
  let Snippet(projection: proj, ..) = state

  case proj {
    #(p.Exp(expression), _) -> {
      let assert Ok(text) =
        e.to_annotated(expression, [])
        |> dag_json.to_block
        |> bit_array.to_string
      let text =
        text
        |> string.replace("\\", "\\\\")
        |> string.replace("\"", "\\\"")
      #(state, WriteToClipboard(text))
    }
    _ -> action_failed(state, "copy")
  }
}

fn confirm(state) {
  #(state, Confirm)
}

pub fn finish_editing(state) {
  Snippet(..state, status: Idle)
}

pub fn release_to_option(release) {
  let #(package, release, _cid) = release

  [
    h.span([a.style([#("font-weight", "700")])], [
      element.text(package <> ":" <> int.to_string(release)),
    ]),
    h.span([a.style([#("flex-grow", "1")])], [element.text(" ")]),
    h.span(
      [
        a.style([
          #("padding-left", ".5rem"),
          #("overflow", "hidden"),
          #("text-overflow", "ellipsis"),
          #("white-space", "nowrap"),
        ]),
      ],
      [element.text("")],
    ),
  ]
}

fn bare_render(proj, errors, status, slot) {
  case status {
    Editing(mode) ->
      case mode {
        Command -> [
          actual_render_projection(proj, True, errors),
          ..slot
          // case failure {
        //   Some(failure) ->
        //     footer_area(neo_orange_4, [element.text(fail_message(failure))])
        //   None -> element.text("render_current(errors, run, evaluated)")
        // },
        ]
        Pick(picker, _rebuild) -> [
          actual_render_projection(proj, False, errors),
          picker.render(picker)
            |> element.map(MessageFromPicker),
        ]

        SelectRelease(autocomplete, _) -> [
          actual_render_projection(proj, False, errors),
          autocomplete.render(autocomplete, release_to_option)
            |> element.map(SelectReleaseMessage),
        ]

        EditText(value, _rebuild) -> [
          actual_render_projection(proj, False, errors),
          input.render_text(value)
            |> element.map(MessageFromInput),
        ]

        EditInteger(value, _rebuild) -> [
          actual_render_projection(proj, False, errors),
          input.render_number(value)
            |> element.map(MessageFromInput),
        ]
      }

    Idle -> [
      h.pre(
        [
          a.class("language-eyg"),
          a.style(code_area_styles),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(p.rebuild(proj), errors),
      ),
      ..slot
    ]
  }
}

pub fn render_pallet(state) {
  let Snippet(status: status, ..) = state
  case status {
    Editing(mode) ->
      case mode {
        Command -> []

        Pick(picker, _rebuild) -> [
          picker.render(picker)
          |> element.map(MessageFromPicker),
        ]
        SelectRelease(_, _) -> [
          element.text("TODO are we rendering this pallet"),
        ]

        EditText(value, _rebuild) -> [
          input.render_text(value)
          |> element.map(MessageFromInput),
        ]

        EditInteger(value, _rebuild) -> [
          input.render_number(value)
          |> element.map(MessageFromInput),
        ]
      }

    Idle -> []
  }
}

fn type_errors(snippet) {
  let Snippet(analysis:, ..) = snippet
  case analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }
}

pub fn render_just_projection(state, autofocus) {
  let Snippet(status: status, projection: proj, editable:, ..) = state
  let errors = type_errors(state)
  case status {
    Editing(_mode) -> {
      actual_render_projection(proj, autofocus, errors)
    }
    Idle ->
      h.pre(
        [
          a.class("language-eyg"),
          a.style(code_area_styles),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(editable, errors),
      )
  }
}

fn actual_render_projection(proj, autofocus, errors) {
  h.pre(
    [
      a.class("language-eyg"),
      a.style(code_area_styles),
      ..case autofocus {
        True -> [
          a.attribute("tabindex", "0"),
          a.attribute("autofocus", "true"),
          // a.autofocus(True),
          event.on("click", fn(event) {
            let assert Ok(e) = pevent.cast_event(event)
            let target = pevent.target(e)
            let rev =
              target
              |> dynamicx.unsafe_coerce
              |> dom_element.dataset_get("rev")
            case rev {
              Ok(rev) -> {
                let assert Ok(rev) = case rev {
                  "" -> Ok([])
                  _ ->
                    string.split(rev, ",")
                    |> list.try_map(int.parse)
                }
                Ok(UserClickedCode(list.reverse(rev)))
              }
              Error(_) -> {
                console.log(target)
                Error([])
              }
            }
          }),
          utils.on_hotkey(UserPressedCommandKey),
        ]
        False -> [
          event.on("click", fn(event) {
            let assert Ok(e) = pevent.cast_event(event)
            let target = pevent.target(e)
            let rev =
              target
              |> dynamicx.unsafe_coerce
              |> dom_element.dataset_get("rev")
            case rev {
              Ok(rev) -> {
                let assert Ok(rev) = case rev {
                  "" -> Ok([])
                  _ ->
                    string.split(rev, ",")
                    |> list.try_map(int.parse)
                }
                Ok(UserClickedCode(list.reverse(rev)))
              }
              Error(_) -> {
                console.log(target)
                Error([])
              }
            }
          }),
        ]
      }
    ],
    [render_projection(proj, errors)],
  )
}

fn render_projection(proj, errors) {
  let #(focus, zoom) = proj
  case focus, zoom {
    p.Exp(e), [] ->
      frame.Statements(render.statements(e, errors))
      |> highlight.frame(highlight.focus())
      |> frame.to_fat_line
    _, _ -> {
      // This is NOT reversed because zoom works from inside out
      let frame = render.projection_frame(proj, render.Statements, errors)
      render.push_render(frame, zoom, render.Statements, errors)
      |> frame.to_fat_line
    }
  }
}

pub fn fail_message(reason) {
  case reason {
    NoKeyBinding(key) -> string.concat(["No action bound for key '", key, "'"])
    ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
    // RunFailed(#(reason, _, _, _)) -> simple_debug.reason_to_string(reason)
  }
}

// fn handle_dragover(event) {
//   event.prevent_default(event)
//   event.stop_propagation(event)
//   Error([])
// }

// needs to handle dragover otherwise browser will open file
// https://stackoverflow.com/questions/43180248/firefox-ondrop-event-datatransfer-is-null-after-update-to-version-52
// fn handle_drop(event) {
//   event.prevent_default(event)
//   event.stop_propagation(event)
//   let files =
//     drag.data_transfer(dynamicx.unsafe_coerce(event))
//     |> drag.files
//     |> array.to_list()
//   case files {
//     [file] -> {
//       let work =
//         promise.map(file.text(file), fn(content) {
//           let assert Ok(source) = decode.from_json(content)
//           //  going via annotated is inefficient
//           let source = annotated.add_annotation(source, Nil)
//           let source = e.from_annotated(source)
//           Ok(source)
//         })

//       Ok(state.Loading(work))
//     }
//     _ -> {
//       console.log(#(event, files))
//       Error([])
//     }
//   }
// }
fn render_effect(eff) {
  let #(lift, reply) = eff
  string.concat([debug.mono(lift), " : ", debug.mono(reply)])
}

pub fn render_poly(poly) {
  let #(type_, _) = binding.instantiate(poly, 0, dict.new())
  debug.mono(type_)
}

pub fn menu_content(status, projection, submenu) {
  case status {
    Idle -> #([menu.delete()], None)
    Editing(Command) -> {
      let subcontent = case submenu {
        menu.Collection -> Some(#("wrap", menu.submenu_wrap(projection)))
        menu.More -> Some(#("more", menu.submenu_more()))
        menu.Closed -> None
      }
      #(menu.top_content(projection), subcontent)
    }
    Editing(_) -> #([], None)
  }
}

pub fn render_embedded_with_top_menu(snippet, slot) {
  let display_help = True
  let Snippet(status: status, projection:, menu: menu, ..) = snippet
  let #(top, subcontent) = menu_content(status, projection, menu)

  h.pre(
    [
      a.class("language-eyg"),
      a.style([
        #("position", "relative"),
        #("margin", "0"),
        #("padding", "0"),
        #("overflow", "initial"),
        ..embed_area_styles
      ]),
      // This is needed to stop the component interfering with remark slides
      event.on("keypress", fn(event) {
        event.stop_propagation(event)
        Error([])
      }),
    ],
    bare_render(projection, type_errors(snippet), status, slot)
      |> list.append(case status {
        Idle -> []
        _ -> [
          case subcontent {
            Some(#(_key, subitems)) ->
              h.div(
                [
                  a.style([
                    // #("padding-top", ".5rem"),
                    // #("padding-bottom", ".5rem"),
                    #("justify-content", "flex-end"),
                    #("flex-direction", "column"),
                    #("display", "flex"),
                  ]),
                ],
                list.map(
                  [
                    #(outline.chevron_left(), "Back", menu.Toggle(menu.Closed)),
                    ..subitems
                  ],
                  fn(entry) {
                    let #(i, text, k) = entry
                    vertical_menu.button(k, [
                      vertical_menu.icon(i, text, display_help),
                    ])
                  },
                ),
              )
              |> element.map(MessageFromMenu)
            None ->
              h.div(
                [
                  a.style([
                    // #("padding-top", ".5rem"),
                    // #("padding-bottom", ".5rem"),
                    #("justify-content", "flex-end"),
                    #("flex-direction", "column"),
                    #("display", "flex"),
                  ]),
                ],
                list.map(top, fn(entry) {
                  let #(i, text, k) = entry
                  vertical_menu.button(k, [
                    vertical_menu.icon(i, text, display_help),
                  ])
                }),
              )
              |> element.map(MessageFromMenu)
          },
        ]
      }),
  )
}

pub fn render_embedded_with_menu(snippet, _failure) {
  h.pre(
    [
      a.class("eyg-embed language-eyg"),
      a.style([
        #("position", "relative"),
        #("margin", "0"),
        #("padding", "0"),
        #("overflow", "initial"),
      ]),
      // This is needed to stop the component interfering with remark slides
      event.on("keypress", fn(event) {
        event.stop_propagation(event)
        Error([])
      }),
    ],
    [
      render_menu(snippet, False) |> element.map(MessageFromMenu),
      // ..bare_render(snippet, failure)
    ],
  )
}

fn render_menu(snippet, display_help) {
  let Snippet(status: status, projection:, menu: menu, ..) = snippet
  let #(top, subcontent) = menu_content(status, projection, menu)
  h.div(
    [
      a.class("eyg-menu-container"),
      a.style([
        #("position", "absolute"),
        #("left", "0"),
        #("top", "50%"),
        #("transform", "translate(calc(-100% - 10px), -50%)"),
        #("grid-template-columns", "max-content max-content"),
        #("overflow-x", "hidden"),
        #("overflow-y", "auto"),
        #("display", "grid"),
      ]),
    ],
    [
      render_column(top, display_help),
      case subcontent {
        None -> element.none()
        Some(#(_key, subitems)) -> render_column(subitems, display_help)
      },
    ],
  )
}

fn render_column(items, display_help) {
  h.div(
    [
      a.style([
        #("padding-top", ".5rem"),
        #("padding-bottom", ".5rem"),
        #("justify-content", "flex-end"),
        #("flex-direction", "column"),
        #("display", "flex"),
      ]),
    ],
    list.map(items, fn(entry) {
      let #(i, text, k) = entry
      vertical_menu.button(k, [vertical_menu.icon(i, text, display_help)])
    }),
  )
}
