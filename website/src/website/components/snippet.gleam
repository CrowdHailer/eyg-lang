import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/break
import eyg/runtime/interpreter/block
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/sync/sync
import eyg/website/run
import eygir/annotated
import eygir/decode
import eygir/encode
import gleam/dict
import gleam/dynamicx
import gleam/int
import gleam/io
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
import website/components/output
import website/components/snippet/menu

const neo_blue_3 = "#87ceeb"

const neo_green_3 = "#90ee90"

const neo_orange_4 = "#ff6b6b"

const embed_area_styles = [
  #("box-shadow", "6px 6px black"), #("border-style", "solid"),
  #(
    "font-family",
    "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
  ), #("background-color", "rgb(255, 255, 255)"),
  #("border-color", "rgb(0, 0, 0)"), #("border-width", "1px"),
  #("flex-direction", "column"), #("display", "flex"),
  #("margin-bottom", "1.5rem"), #("margin-top", ".5rem"),
]

const code_area_styles = [
  #("outline", "2px solid transparent"), #("outline-offset", "2px"),
  #("padding", ".5rem"), #("white-space", "nowrap"), #("overflow", "auto"),
  #("margin-top", "auto"), #("margin-bottom", "auto"),
]

fn footer_area(color, contents) {
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

type ExternalBlocking =
  fn(run.Value) -> Result(promise.Promise(run.Value), run.Reason)

type EffectSpec =
  #(binding.Mono, binding.Mono, ExternalBlocking)

pub type Status {
  Idle
  Editing(Mode)
}

type Path =
  Nil

type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

type Scope =
  List(#(String, Value))

pub type History {
  History(undo: List(p.Projection), redo: List(p.Projection))
}

pub type Failure {
  NoKeyBinding(key: String)
  ActionFailed(action: String)
  RunFailed(istate.Debug(run.Meta))
}

pub type Mode {
  Command
  Pick(picker: picker.Picker, rebuild: fn(String) -> p.Projection)
  EditText(String, fn(String) -> p.Projection)
  EditInteger(Int, fn(Int) -> p.Projection)
}

pub type Snippet {
  Snippet(
    status: Status,
    expanding: Option(List(Int)),
    source: #(p.Projection, e.Expression, Option(analysis.Analysis)),
    menu: menu.State,
    history: History,
    run: run.Run,
    scope: Scope,
    effects: List(#(String, EffectSpec)),
    cache: sync.Sync,
  )
}

pub fn init(editable, scope, effects, cache) {
  let editable = e.open_all(editable)
  let proj = navigation.first(editable)
  Snippet(
    Idle,
    None,
    new_source(proj, editable, scope, effects, cache),
    menu.init(),
    History([], []),
    run.start(editable, scope, effects, cache),
    scope,
    effects,
    cache,
  )
}

pub fn active(editable, scope, effects, cache) {
  let editable = e.open_all(editable)
  let proj = navigation.first(editable)

  Snippet(
    Editing(Command),
    None,
    new_source(proj, editable, scope, effects, cache),
    menu.init(),
    History([], []),
    run.start(editable, scope, effects, cache),
    scope,
    effects,
    cache,
  )
}

fn new_source(proj, editable, scope, effects, cache) {
  let eff =
    effect_types(effects)
    |> list.fold(t.Empty, fn(acc, new) {
      let #(label, #(lift, reply)) = new
      t.EffectExtend(label, #(lift, reply), acc)
    })
  let analysis =
    analysis.do_analyse(
      editable,
      analysis.within_environment(
        scope,
        sync.named_types(cache) |> dict.from_list(),
      ),
      eff,
    )
  #(proj, editable, Some(analysis))
}

fn effect_types(effects: List(#(String, EffectSpec))) {
  listx.value_map(effects, fn(details) { #(details.0, details.1) })
}

pub fn run(state) {
  let Snippet(run: run, ..) = state
  run
}

pub fn source(state) {
  let Snippet(source: #(_, source, _), ..) = state
  source
}

pub fn set_references(state, cache) {
  let run = run.start(source(state), state.scope, state.effects, cache)
  let source = state.source
  let source = new_source(source.0, source.1, state.scope, state.effects, cache)
  Snippet(..state, source: source, run: run, cache: cache)
}

pub fn references(state) {
  e.to_annotated(source(state), []) |> annotated.list_references()
}

pub type Message {
  UserFocusedOnCode
  UserClickRunEffects
  UserPressedCommandKey(String)
  UserClickedPath(List(Int))
  UserClickedCode(List(Int))
  MessageFromInput(input.Message)
  MessageFromPicker(picker.Message)
  MessageFromMenu(menu.Message)
  RuntimeRepliedFromExternalEffect(run.Value)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
}

pub fn user_message(message) {
  case message {
    RuntimeRepliedFromExternalEffect(_)
    | ClipboardReadCompleted(_)
    | ClipboardWriteCompleted(_) -> False
    _ -> True
  }
}

pub type Effect {
  Nothing
  Failed(Failure)
  FocusOnCode
  FocusOnInput
  ToggleHelp
  MoveAbove
  MoveBelow
  WriteToClipboard(String)
  ReadFromClipboard
  AwaitRunningEffect(promise.Promise(Value))
  Conclude(Option(Value), List(#(String, #(Value, Value))), Scope)
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

pub fn focus_on_input() {
  window.request_animation_frame(fn(_) {
    case document.query_selector("[autofocus]") {
      Ok(el) -> {
        dom_element.focus(el)
        // This can only be done when we move to a new focus
        // error is something specifically to do with numbers
        dom_element.set_selection_range(el, 0, -1)
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

pub fn await_running_effect(promise) {
  promise.map(promise, RuntimeRepliedFromExternalEffect)
}

fn navigate_source(proj, state) {
  let Snippet(source: #(_, editable, analysis), ..) = state
  let source = #(proj, editable, analysis)
  let status = Editing(Command)
  let state = Snippet(..state, status: status, source: source)
  #(state, Nothing)
}

fn update_source(proj, state) {
  let Snippet(source: #(old, _, _), history: history, ..) = state
  let editable = p.rebuild(proj)
  let source =
    new_source(proj, editable, state.scope, state.effects, state.cache)
  let History(undo: undo, ..) = history
  let undo = [old, ..undo]
  let history = History(undo: undo, redo: [])
  let status = Editing(Command)
  let run = run.start(editable, state.scope, state.effects, state.cache)
  Snippet(..state, status: status, source: source, history: history, run: run)
}

fn update_source_from_buffer(proj, state) {
  #(update_source(proj, state), Nothing)
}

fn update_source_from_pallet(proj, state) {
  #(update_source(proj, state), FocusOnCode)
}

fn return_to_buffer(state) {
  let state = Snippet(..state, status: Editing(Command))
  #(state, FocusOnCode)
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
  let Snippet(
    status: status,
    source: #(proj, editable, _),
    run: run,
    effects: effects,
    ..,
  ) = state
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
        "@" -> insert_named_reference(state)
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
        "Enter" -> execute(state)
        _ -> #(state, Failed(NoKeyBinding(key)))
      }
    }
    UserPressedCommandKey(_), _ -> panic as "should never get a buffer message"
    UserClickedPath(path), _ ->
      navigate_source(p.focus_at(editable, path), state)

    // This is unhelpful as hard if big blocks are selected
    // case listx.starts_with(path, p.path(proj)) && p.path(proj) != [] {
    UserClickedCode(path), _ -> {
      let state = Snippet(..state, status: Editing(Command))
      case proj, p.path(proj) == path {
        #(p.Assign(p.AssignStatement(_), _, _, _, _), _), True ->
          toggle_open(state)
        _, _ ->
          case
            // listx.starts_with(path, p.path(proj))
            // path expanding real just means it was the last thing clicked
            Some(path) == state.expanding && p.path(proj) != []
          {
            True -> increase(state)
            False -> {
              let state = Snippet(..state, expanding: Some(path))
              navigate_source(p.focus_at(editable, path), state)
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

    MessageFromMenu(message), _ -> {
      let #(menu, action) = menu.update(state.menu, message)
      let state = Snippet(..state, menu: menu)
      case action {
        None -> #(state, Nothing)
        Some(key) -> update(state, UserPressedCommandKey(key))
      }
    }
    UserClickRunEffects, _ -> run_effects(state)
    RuntimeRepliedFromExternalEffect(reply), Editing(Command)
    | RuntimeRepliedFromExternalEffect(reply), Idle
    -> {
      let assert run.Run(run.Handling(label, lift, env, k, _), effect_log) = run

      let effect_log = [#(label, #(lift, reply)), ..effect_log]
      let status = case block.resume(reply, env, k) {
        Ok(#(value, env)) -> run.Done(value, env)
        Error(debug) -> run.handle_extrinsic_effects(debug, effects)
      }
      let run = run.Run(status, effect_log)
      let state = Snippet(..state, run: run)
      case status {
        run.Failed(_) -> #(state, Nothing)
        run.Done(value, env) -> #(state, Conclude(value, run.effects, env))

        run.Handling(_label, lift, env, k, blocking) ->
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Snippet(..state, run: run)
              #(state, AwaitRunningEffect(promise))
            }
            Error(reason) -> {
              let run = run.Run(run.Failed(#(reason, Nil, env, k)), effect_log)
              let state = Snippet(..state, run: run)
              #(state, Nothing)
            }
          }
      }
    }
    RuntimeRepliedFromExternalEffect(_), Editing(mode) -> {
      io.debug(mode)
      panic as "Should never be editing while running effects"
    }
    ClipboardReadCompleted(return), _ -> {
      let assert Editing(Command) = status
      case return {
        Ok(text) ->
          case decode.from_json(text) {
            Ok(expression) -> {
              let assert #(p.Exp(_), zoom) = proj
              let proj = #(p.Exp(e.from_expression(expression)), zoom)
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
  let Snippet(source: #(proj, _, _), ..) = state
  navigate_source(navigation.next(proj), state)
}

fn move_left(state) {
  let Snippet(source: #(proj, _, _), ..) = state
  navigate_source(navigation.previous(proj), state)
}

fn move_up(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case navigation.move_up(proj) {
    Ok(new) -> navigate_source(navigation.next(new), state)
    Error(Nil) -> #(state, MoveAbove)
  }
}

fn move_down(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case navigation.move_down(proj) {
    Ok(new) -> navigate_source(navigation.next(new), state)
    Error(Nil) -> #(state, MoveBelow)
  }
}

fn copy(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case proj {
    #(p.Exp(expression), _) -> {
      let text = encode.to_json(e.to_expression(expression))
      #(state, WriteToClipboard(text))
    }
    _ -> action_failed(state, "copy")
  }
}

fn paste(state) {
  #(state, ReadFromClipboard)
}

fn search_vacant(state) {
  let Snippet(source: #(proj, _, _), ..) = state
  let new = do_search_vacant(proj)
  navigate_source(new, state)
}

fn do_search_vacant(proj) {
  let next = navigation.next(proj)
  case next {
    #(p.Exp(e.Vacant("")), _zoom) -> next
    // If at the top break, can search again to loop around
    #(p.Exp(_), []) -> next
    _ -> do_search_vacant(next)
  }
}

fn toggle_open(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  let proj = navigation.toggle_open(proj)
  navigate_source(proj, state)
}

fn call_with(state) {
  let Snippet(source: #(proj, _, _), ..) = state
  case transformation.call_with(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "call as argument")
  }
}

fn assign_to(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.assign(proj) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      change_mode(state, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> action_failed(state, "assign to")
  }
}

fn assign_above(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.assign_before(proj) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      change_mode(state, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> action_failed(state, "assign above")
  }
}

fn insert_record(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state
  case action.make_record(proj, analysis) {
    Ok(action.Updated(proj)) -> update_source_from_buffer(proj, state)
    Ok(action.Choose(value, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(value, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create record")
  }
}

fn overwrite_record(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.overwrite_record(proj, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create record")
  }
}

fn insert_tag(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

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
  let Snippet(source: #(proj, _, analysis), ..) = state

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
  let Snippet(source: #(proj, _, analysis), ..) = state

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
  let Snippet(source: #(proj, _, _), ..) = state

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
  let Snippet(source: #(proj, _, _), effects: effects, ..) = state
  let hints = effect_types(effects)
  case action.perform(proj) {
    Ok(#(filter, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "perform")
  }
}

fn increase(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case navigation.increase(proj) {
    Ok(new) -> navigate_source(new, state)
    Error(Nil) -> action_failed(state, "increase selection")
  }
}

fn insert_string(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.string(proj) {
    Ok(#(value, rebuild)) -> change_mode(state, EditText(value, rebuild))
    Error(Nil) -> action_failed(state, "create text")
  }
}

fn delete(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.delete(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "delete")
  }
}

fn insert_function(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.function(proj) {
    Ok(rebuild) -> change_mode(state, Pick(picker.new("", []), rebuild))
    Error(Nil) -> action_failed(state, "create function")
  }
}

fn select_field(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.select_field(proj, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "select field")
  }
}

fn insert_handle(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.handle(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "perform")
  }
}

fn insert_builtin(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case action.insert_builtin(proj, contextual.builtins()) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert builtin")
  }
}

fn insert_list(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.list(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "create list")
  }
}

fn insert_named_reference(state) {
  let Snippet(source: #(proj, _, _), cache: cache, ..) = state

  let index =
    sync.package_index(cache)
    |> listx.value_map(render_poly)

  case action.insert_named_reference(proj) {
    Ok(#(filter, rebuild)) -> {
      change_mode(state, Pick(picker.new(filter, index), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert reference")
  }
}

fn insert_reference(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case action.insert_reference(proj) {
    Ok(#(filter, rebuild)) -> {
      change_mode(state, Pick(picker.new(filter, []), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert named reference")
  }
}

fn call_function(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.call_function(proj, analysis) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "call function")
  }
}

fn insert_variable(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.insert_variable(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "insert variable")
  }
}

fn insert_binary(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.binary(proj) {
    Ok(#(value, rebuild)) -> update_source_from_buffer(rebuild(value), state)
    Error(Nil) -> action_failed(state, "create binary")
  }
}

fn insert_integer(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.integer(proj) {
    Ok(#(value, rebuild)) -> change_mode(state, EditInteger(value, rebuild))
    Error(Nil) -> action_failed(state, "create number")
  }
}

fn insert_case(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

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
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.make_open_case(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> action_failed(state, "create match")
  }
}

fn spread_list(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.spread_list(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "spread list")
  }
}

fn toggle_spread(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.toggle_spread(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "toggle spread")
  }
}

fn toggle_otherwise(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.toggle_otherwise(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> action_failed(state, "create match")
  }
}

fn undo(state) {
  let Snippet(source: #(proj, _, _), history: history, ..) = state
  case history.undo {
    [] -> action_failed(state, "undo")
    [saved, ..rest] -> {
      let source =
        new_source(
          saved,
          p.rebuild(saved),
          state.scope,
          state.effects,
          state.cache,
        )
      let history = History(undo: rest, redo: [proj, ..history.redo])
      let status = Editing(Command)
      let state =
        Snippet(..state, status: status, source: source, history: history)
      #(state, Nothing)
    }
  }
}

fn redo(state) {
  let Snippet(source: #(proj, _, _), history: history, ..) = state
  case history.redo {
    [] -> action_failed(state, "redo")
    [saved, ..rest] -> {
      let source =
        new_source(
          saved,
          p.rebuild(saved),
          state.scope,
          state.effects,
          state.cache,
        )
      let history = History(undo: [proj, ..history.undo], redo: rest)
      let status = Editing(Command)
      let state =
        Snippet(..state, status: status, source: source, history: history)
      #(state, Nothing)
    }
  }
}

pub fn copy_escaped(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case proj {
    #(p.Exp(expression), _) -> {
      let text =
        encode.to_json(e.to_expression(expression))
        |> string.replace("\\", "\\\\")
        |> string.replace("\"", "\\\"")
      #(state, WriteToClipboard(text))
    }
    _ -> action_failed(state, "copy")
  }
}

fn execute(state) {
  let Snippet(run: run, ..) = state
  case run.status {
    run.Done(value, env) -> #(state, Conclude(value, run.effects, env))
    run.Failed(debug) -> {
      #(state, Failed(RunFailed(debug)))
    }
    _ -> run_effects(state)
  }
}

fn run_effects(state) {
  let Snippet(run: run, ..) = state
  let run.Run(status, effect_log) = run
  case status {
    run.Handling(_label, lift, env, k, blocking) -> {
      case blocking(lift) {
        Ok(promise) -> {
          let run = run.Run(status, effect_log)
          let state = Snippet(..state, run: run)
          #(state, AwaitRunningEffect(promise))
        }
        Error(reason) -> {
          let run = run.Run(run.Failed(#(reason, Nil, env, k)), effect_log)
          let state = Snippet(..state, run: run)
          #(state, Nothing)
        }
      }
    }
    _ -> #(state, Nothing)
  }
}

pub fn finish_editing(state) {
  Snippet(..state, status: Idle)
}

pub fn render_embedded(state: Snippet, failure) {
  h.div([a.style(embed_area_styles)], bare_render(state, failure))
}

pub fn bare_render(state, failure) {
  let Snippet(status: status, source: source, run: run, ..) = state
  let #(proj, _, analysis) = source
  let errors = case analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }

  case status {
    Editing(mode) ->
      case mode {
        Command -> [
          actual_render_projection(proj, True, errors),
          case failure {
            Some(failure) ->
              footer_area(neo_orange_4, [element.text(fail_message(failure))])
            None -> render_current(errors, run)
          },
        ]
        Pick(picker, _rebuild) -> [
          actual_render_projection(proj, False, errors),
          picker.render(picker)
            |> element.map(MessageFromPicker),
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
        render.statements(source.1, errors),
      ),
      render_current(errors, run),
    ]
  }
}

// TODO remove
pub fn render_current(errors, run: run.Run) {
  case errors {
    [] -> render_run(run.status)
    _ -> render_errors(errors)
  }
}

pub fn render_errors(errors) {
  footer_area(
    neo_orange_4,
    list.map(errors, fn(error) {
      let #(path, reason) = error
      h.div([event.on_click(UserClickedPath(path))], [
        debug.reason_to_html(reason),
      ])
    }),
  )
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

pub fn render_just_projection(state, autofocus) {
  let Snippet(status: status, source: source, ..) = state
  let #(proj, _, analysis) = source
  let errors = case analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }
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
        render.statements(source.1, errors),
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

fn render_run(run) {
  case run {
    run.Done(value, _) ->
      footer_area(neo_green_3, [
        case value {
          Some(value) -> output.render(value)
          None -> element.none()
        },
      ])
    run.Handling(label, _meta, _env, _stack, _blocking) ->
      footer_area(neo_blue_3, [
        h.span([event.on_click(UserClickRunEffects)], [
          element.text("Will run "),
          element.text(label),
          element.text(" effect. click to continue."),
        ]),
      ])
    run.Failed(#(reason, _, _, _)) ->
      footer_area(neo_orange_4, [element.text(break.reason_to_string(reason))])
  }
}

pub fn fail_message(reason) {
  case reason {
    NoKeyBinding(key) -> string.concat(["No action bound for key '", key, "'"])
    ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
    RunFailed(#(reason, _, _, _)) -> break.reason_to_string(reason)
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

pub fn render_embedded_with_top_menu(snippet, failure) {
  let display_help = True
  let Snippet(status: status, source: source, menu: menu, ..) = snippet
  let #(top, subcontent) = menu_content(status, source.0, menu)

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
    bare_render(snippet, failure)
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
                    button(k, [icon(i, text, display_help)])
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
                  button(k, [icon(i, text, display_help)])
                }),
              )
              |> element.map(MessageFromMenu)
          },
        ]
      }),
  )
}

pub fn render_embedded_with_menu(snippet, failure) {
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
      ..bare_render(snippet, failure)
    ],
  )
}

fn render_menu(snippet, display_help) {
  let Snippet(status: status, source: source, menu: menu, ..) = snippet
  let #(top, subcontent) = menu_content(status, source.0, menu)
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
      button(k, [icon(i, text, display_help)])
    }),
  )
}

pub fn button(action, content) {
  h.button(
    [
      a.class("morph button"),
      a.style([
        // #("background", "none"),
        #("outline", "none"),
        #("border", "none"),
        #("padding-left", ".5rem"),
        #("padding-right", ".5rem"),
        #("padding-top", ".25rem"),
        #("padding-bottom", ".25rem"),
        #("cursor", "pointer"),
        // TODO hover color
      ]),
      event.on_click(action),
    ],
    content,
  )
}

pub fn icon(image, text, display_help) {
  h.span(
    [
      a.style([
        #("align-items", "center"),
        #("border-radius", ".25rem"),
        #("display", "flex"),
      ]),
    ],
    [
      h.span(
        [
          a.style([
            #("font-size", "1.25rem"),
            #("line-height", "1.75rem"),
            #("text-align", "center"),
            #("width", "1.5rem"),
            #("height", "1.75rem"),
            #("display", "inline-block"),
          ]),
        ],
        [image],
      ),
      case display_help {
        True ->
          h.span([a.class("ml-2 border-l border-opacity-25 pl-2")], [
            element.text(text),
          ])
        False -> element.none()
      },
    ],
  )
}
