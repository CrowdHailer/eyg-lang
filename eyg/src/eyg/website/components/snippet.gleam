import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/break
import eyg/runtime/interpreter/block
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/sync/sync
import eyg/website/components/output
import eyg/website/run
import eygir/annotated
import eygir/decode
import eygir/encode
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/action
import morph/analysis
import morph/editable as e
import morph/input
import morph/lustre/render
import morph/navigation
import morph/picker
import morph/projection as p
import morph/transformation
import plinth/browser/clipboard
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/browser/event as pevent
import plinth/browser/window

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
}

pub type Mode {
  Command(failure: Option(Failure))
  Pick(picker: picker.Picker, rebuild: fn(String) -> p.Projection)
  EditText(String, fn(String) -> p.Projection)
  EditInteger(Int, fn(Int) -> p.Projection)
}

pub type Snippet {
  Snippet(
    status: Status,
    source: #(p.Projection, e.Expression, Option(analysis.Analysis)),
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
    new_source(proj, editable, scope, effects, cache),
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
    Editing(Command(None)),
    new_source(proj, editable, scope, effects, cache),
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
      analysis.within_environment(scope, sync.types(cache)),
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
  Snippet(..state, run: run, cache: cache)
}

pub fn references(state) {
  e.to_annotated(source(state), []) |> annotated.list_references()
}

pub type Message {
  UserFocusedOnCode
  UserClickRunEffects
  UserPressedCommandKey(String)
  UserClickedPath(List(Int))
  MessageFromInput(input.Message)
  MessageFromPicker(picker.Message)
  RuntimeRepliedFromExternalEffect(run.Value)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
}

pub type Effect {
  Nothing
  FocusOnCode
  FocusOnInput
  ToggleHelp
  MoveAbove
  MoveBelow
  WriteToClipboard(String)
  ReadFromClipboard
  AwaitRunningEffect(promise.Promise(Value))
  Conclude(Option(Value), Scope)
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
  let status = Editing(Command(None))
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
  let status = Editing(Command(None))
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
  let state = Snippet(..state, status: Editing(Command(None)))
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

fn show_error(state, error) {
  let status = Editing(Command(Some(error)))
  let state = Snippet(..state, status: status)
  #(state, Nothing)
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
      Snippet(..state, status: Editing(Command(None))),
      Nothing,
    )
    UserFocusedOnCode, Editing(_) -> #(
      Snippet(..state, status: Editing(Command(None))),
      Nothing,
    )
    UserPressedCommandKey(key), Editing(Command(_)) -> {
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
        "d" -> delete(state)
        "f" -> insert_function(state)
        "g" -> select_field(state)
        "h" -> insert_handle(state)
        "j" -> insert_builtin(state)
        "k" -> toggle_open(state)
        "l" -> insert_list(state)
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
        "." -> spread_list(state)
        "?" -> #(state, ToggleHelp)
        "Enter" -> execute(state)
        _ -> show_error(state, NoKeyBinding(key))
      }
    }
    UserPressedCommandKey(_), _ -> panic as "should never get a buffer message"
    UserClickedPath(path), _ ->
      navigate_source(p.focus_at(editable, path), state)
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
    UserClickRunEffects, _ -> run_effects(state)
    RuntimeRepliedFromExternalEffect(reply), Editing(Command(_)) -> {
      let assert run.Run(run.Handling(label, lift, env, k, _), effect_log) = run

      let effect_log = [#(label, #(lift, reply)), ..effect_log]
      let status = case block.resume(reply, env, k) {
        Ok(#(value, env)) -> run.Done(value, env)
        Error(debug) -> run.handle_extrinsic_effects(debug, effects)
      }
      let run = run.Run(status, effect_log)
      let state = Snippet(..state, run: run)
      case status {
        run.Done(_, _) | run.Failed(_) -> #(state, Nothing)

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
    RuntimeRepliedFromExternalEffect(_), _ ->
      panic as "should never get a runtime message"
    ClipboardReadCompleted(return), _ -> {
      let assert Editing(Command(_)) = status
      case return {
        Ok(text) ->
          case decode.from_json(text) {
            Ok(expression) -> {
              let assert #(p.Exp(_), zoom) = proj
              let proj = #(p.Exp(e.from_expression(expression)), zoom)
              update_source_from_buffer(proj, state)
            }
            Error(_) -> show_error(state, ActionFailed("paste"))
          }
        Error(_) -> show_error(state, ActionFailed("paste"))
      }
    }
    ClipboardWriteCompleted(return), _ ->
      case return {
        Ok(Nil) -> #(state, Nothing)
        Error(_) -> show_error(state, ActionFailed("paste"))
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
    _ -> show_error(state, ActionFailed("copy"))
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

  let #(focus, zoom) = proj
  let focus = case focus {
    p.Exp(e.Block(assigns, then, open)) -> p.Exp(e.Block(assigns, then, !open))
    p.Assign(label, e.Block(assigns, inner, open), pre, post, final) ->
      p.Assign(label, e.Block(assigns, inner, !open), pre, post, final)
    _ -> focus
  }
  let proj = #(focus, zoom)
  navigate_source(proj, state)
}

fn call_with(state) {
  let Snippet(source: #(proj, _, _), ..) = state
  case transformation.call_with(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> show_error(state, ActionFailed("call as argument"))
  }
}

fn assign_to(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.assign(proj) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      change_mode(state, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("assign to"))
  }
}

fn assign_above(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.assign_before(proj) {
    Ok(rebuild) -> {
      let rebuild = fn(new) { rebuild(e.Bind(new)) }
      change_mode(state, Pick(picker.new("", []), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("assign above"))
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
    Error(Nil) -> show_error(state, ActionFailed("create record"))
  }
}

fn overwrite_record(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.overwrite_record(proj, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("create record"))
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
    Error(Nil) -> show_error(state, ActionFailed("tag expression"))
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
    Error(Nil) -> show_error(state, ActionFailed("extend"))
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
        Error(Nil) -> show_error(state, ActionFailed("edit"))
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
    Error(Nil) -> show_error(state, ActionFailed("perform"))
  }
}

fn increase(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case navigation.increase(proj) {
    Ok(new) -> navigate_source(new, state)
    Error(Nil) -> show_error(state, ActionFailed("increase selection"))
  }
}

fn insert_string(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.string(proj) {
    Ok(#(value, rebuild)) -> change_mode(state, EditText(value, rebuild))
    Error(Nil) -> show_error(state, ActionFailed("create text"))
  }
}

fn delete(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.delete(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> show_error(state, ActionFailed("delete"))
  }
}

fn insert_function(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.function(proj) {
    Ok(rebuild) -> change_mode(state, Pick(picker.new("", []), rebuild))
    Error(Nil) -> show_error(state, ActionFailed("create function"))
  }
}

fn select_field(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.select_field(proj, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new("", hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("select field"))
  }
}

fn insert_handle(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.handle(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_effect)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("perform"))
  }
}

fn insert_builtin(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case action.insert_builtin(proj, contextual.builtins()) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("insert builtin"))
  }
}

fn insert_list(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.list(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> show_error(state, ActionFailed("create list"))
  }
}

fn insert_reference(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case action.insert_reference(proj) {
    Ok(#(filter, rebuild)) -> {
      change_mode(state, Pick(picker.new(filter, []), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("insert reference"))
  }
}

fn call_function(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.call_function(proj, analysis) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> show_error(state, ActionFailed("call function"))
  }
}

fn insert_variable(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.insert_variable(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("create binary"))
  }
}

fn insert_binary(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.binary(proj) {
    Ok(#(value, rebuild)) -> update_source_from_buffer(rebuild(value), state)
    Error(Nil) -> show_error(state, ActionFailed("create binary"))
  }
}

fn insert_integer(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.integer(proj) {
    Ok(#(value, rebuild)) -> change_mode(state, EditInteger(value, rebuild))
    Error(Nil) -> show_error(state, ActionFailed("create number"))
  }
}

fn insert_case(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.make_case(proj, analysis) {
    Ok(action.Updated(new)) -> update_source_from_buffer(new, state)
    Ok(action.Choose(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, render_poly)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("create match"))
  }
}

fn insert_open_case(state) {
  let Snippet(source: #(proj, _, analysis), ..) = state

  case action.make_open_case(proj, analysis) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      change_mode(state, Pick(picker.new(filter, hints), rebuild))
    }
    Error(Nil) -> show_error(state, ActionFailed("create match"))
  }
}

fn spread_list(state) {
  let Snippet(source: #(proj, _, _), ..) = state

  case transformation.spread_list(proj) {
    Ok(new) -> update_source_from_buffer(new, state)
    Error(Nil) -> show_error(state, ActionFailed("create match"))
  }
}

fn undo(state) {
  let Snippet(source: #(proj, _, _), history: history, ..) = state
  case history.undo {
    [] -> show_error(state, ActionFailed("undo"))
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
      let status = Editing(Command(None))
      let state =
        Snippet(..state, status: status, source: source, history: history)
      #(state, Nothing)
    }
  }
}

fn redo(state) {
  let Snippet(source: #(proj, _, _), history: history, ..) = state
  case history.redo {
    [] -> show_error(state, ActionFailed("redo"))
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
      let status = Editing(Command(None))
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
    _ -> show_error(state, ActionFailed("copy"))
  }
}

fn execute(state) {
  let Snippet(run: run, ..) = state
  case run.status {
    run.Done(value, env) -> #(state, Conclude(value, env))
    run.Failed(_) -> show_error(state, ActionFailed("Execute"))
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

pub fn render(state: Snippet) {
  h.div(
    [
      a.class(
        "bg-white neo-shadow font-mono mt-2 mb-6 border border-black flex flex-col",
      ),
      // a.style([#("min-height", "18ch")]),
    ],
    bare_render(state),
  )
}

pub fn render_sticky(state: Snippet) {
  h.div(
    [
      a.class(
        "bg-white neo-shadow font-mono mt-2 sticky bottom-6 mb-6 border border-black flex flex-col",
      ),
    ],
    bare_render(state),
  )
}

pub fn render_editor(state: Snippet) {
  h.div(
    [
      a.class(
        "bg-white neo-shadow font-mono mt-2 mb-6 border border-black flex flex-col",
      ),
      a.style([
        #("min-height", "15em"),
        #("height", "100%"),
        #("max-height", "95%"),
      ]),
    ],
    bare_render(state),
  )
}

pub fn bare_render(state) {
  let Snippet(status: status, source: source, run: run, ..) = state
  let #(proj, _, analysis) = source
  let errors = case analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }

  case status {
    Editing(mode) ->
      case mode {
        Command(e) -> {
          [
            render_projection(proj, True),
            case e {
              Some(failure) ->
                h.div([a.class("border-2 border-orange-4 px-2")], [
                  element.text(fail_message(failure)),
                ])
              None -> render_current(errors, run)
            },
          ]
        }
        Pick(picker, _rebuild) -> [
          render_projection(proj, False),
          picker.render(picker)
            |> element.map(MessageFromPicker),
        ]

        EditText(value, _rebuild) -> [
          render_projection(proj, False),
          input.render_text(value)
            |> element.map(MessageFromInput),
        ]

        EditInteger(value, _rebuild) -> [
          render_projection(proj, False),
          input.render_number(value)
            |> element.map(MessageFromInput),
        ]
      }

    Idle -> [
      h.div(
        [
          a.class("p-2 outline-none my-auto"),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(source.1),
      ),
      render_current(errors, run),
    ]
  }
}

fn render_current(errors, run: run.Run) {
  case errors {
    [] -> render_run(run.status)
    _ ->
      h.div(
        [a.class("border-2 border-orange-3 px-2")],
        list.map(errors, fn(error) {
          let #(path, reason) = error
          h.div([event.on_click(UserClickedPath(path))], [
            element.text(debug.reason(reason)),
          ])
        }),
      )
  }
}

fn render_projection(proj, autofocus) {
  h.div(
    [
      a.class("p-2 outline-none my-auto"),
      ..case autofocus {
        True -> [
          a.attribute("tabindex", "0"),
          a.attribute("autofocus", "true"),
          // a.autofocus(True),
          event.on("keydown", fn(event) {
            let assert Ok(event) = pevent.cast_keyboard_event(event)
            let key = pevent.key(event)
            let shift = pevent.shift_key(event)
            let ctrl = pevent.ctrl_key(event)
            let alt = pevent.alt_key(event)
            case key {
              "Alt" | "Ctrl" | "Shift" | "Tab" -> Error([])
              k if shift -> {
                pevent.prevent_default(event)
                Ok(UserPressedCommandKey(string.uppercase(k)))
              }
              _ if ctrl || alt -> Error([])
              k -> {
                pevent.prevent_default(event)
                Ok(UserPressedCommandKey(k))
              }
            }
          }),
        ]
        False -> []
      }
    ],
    [render.projection(proj, False)],
  )
}

fn render_run(run) {
  case run {
    run.Done(value, _) ->
      h.pre(
        [
          a.class("border-2 border-green-3 px-2 overflow-auto"),
          a.style([#("max-height", "30vh")]),
        ],
        [
          case value {
            Some(value) -> output.render(value)
            None -> element.none()
          },
          // element.text(value.debug(value)),
        ],
      )
    run.Handling(label, _meta, _env, _stack, _blocking) ->
      h.pre(
        [
          a.class("border-2 border-blue-3 px-2"),
          event.on_click(UserClickRunEffects),
        ],
        [
          element.text("Will run "),
          element.text(label),
          element.text(" effect. click to continue."),
        ],
      )
    run.Failed(#(reason, _, _, _)) ->
      h.pre([a.class("border-2 border-orange-3 px-2")], [
        element.text(break.reason_to_string(reason)),
      ])
  }
}

pub fn fail_message(reason) {
  case reason {
    NoKeyBinding(key) -> string.concat(["No action bound for key '", key, "'"])
    ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
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
