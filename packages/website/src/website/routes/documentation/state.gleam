import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/dag_json
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import morph/editable as e
import morph/navigation
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/flip
import touch_grass/print
import touch_grass/random
import website/config
import website/harness/browser
import website/harness/harness
import website/routes/documentation/examples

import website/routes/workspace/buffer
import website/sync/client

pub type State {
  State(cache: client.Client, mode: Mode, examples: Dict(String, Example))
}

pub type Example {
  Example(buffer: buffer.Buffer)
}

pub type Rebuild(t) =
  fn(t, infer.Context) -> buffer.Buffer

pub type Mode {
  Editing(id: String, failure: Option(Failure))
  ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  Running(id: String, status: Status)
  Nothing
}

/// Run Status
pub type Status {
  Concluded(Value)
  Handling(label: String, env: state.Env(Meta), k: state.Stack(Meta))
  Failed(String)
}

pub type Meta =
  List(Int)

pub type Value =
  state.Value(Meta)

pub type Debug =
  state.Debug(Meta)

pub type Return =
  Result(Value, Debug)

pub type Failure {
  NoKeyBinding(key: String)
  ActionFailed(action: String)
  // RunFailed(istate.Debug(Path))
}

pub fn fail_message(reason) {
  case reason {
    NoKeyBinding(key) -> string.concat(["No action bound for key '", key, "'"])
    ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
    // RunFailed(#(reason, _, _, _)) -> simple_debug.reason_to_string(reason)
  }
}

pub type Message {
  UserClickedCode(id: String, path: List(Int))
  UserPressedKey(key: String)
  SyncMessage(client.Message)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
  Ignore
}

pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

// snippet failure goes at top level
pub fn init(config) {
  let config.Config(origin:) = config
  let #(client, init_task) = client.init(origin)

  let examples = examples.all()

  let missing_cids = []
  let examples =
    list.map(examples, fn(example) {
      let #(key, editable) = example
      let projection = navigation.first(editable)
      let example = Example(buffer.from_projection(projection, infer.pure()))
      #(key, example)
    })
  let examples = dict.from_list(examples)
  // let missing_cids = missing_refs(examples)
  let #(client, sync_task) = client.fetch_fragments(client, missing_cids)
  let state = State(client, Nothing, examples)
  #(state, [])
}

pub fn update(state: State, message) {
  case message {
    UserClickedCode(id:, path:) -> {
      let Example(buffer:) = get_example(state, id)
      let buffer = buffer.focus_at(buffer, path) |> result.unwrap(buffer)
      let state = set_example(state, id, Example(buffer:))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    UserPressedKey(key:) -> user_pressed_key(state, key)
    SyncMessage(message) -> {
      let State(cache: sync_client, ..) = state
      let #(sync_client, effect) = client.update(sync_client, message)

      let state = State(..state, cache: sync_client)
      // let effects = [, ..effects]
      #(state, todo as "client.lustre_run(effect, SyncMessage)")
    }
    ClipboardReadCompleted(return) -> {
      case state.mode {
        ReadingFromClipboard(id, rebuild) ->
          case return {
            Ok(text) ->
              case json.parse(text, dag_json.decoder(Nil)) {
                Ok(expression) -> {
                  let buffer =
                    rebuild(e.from_annotated(expression), infer.pure())
                  let example = Example(buffer:)
                  let state = set_example(state, id, example)
                  let state = State(..state, mode: Editing(id, None))
                  #(state, [])
                }

                Error(_) -> action_failed(state, id, "paste")
              }
            Error(_) -> action_failed(state, id, "paste")
          }
        _ -> #(state, [])
      }
    }
    ClipboardWriteCompleted(result) -> {
      case state.mode {
        Running(id, Handling(label: "Copy", env:, k:)) -> {
          let #(mode, effects) =
            loop(expression.resume(copy.encode(result), env, k))
          let mode = Running(id, mode)
          #(State(..state, mode:), effects)
        }
        _ -> #(state, [])
      }
    }
    Ignore -> #(state, [])
  }
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  // set error to nothing
  case mode, key {
    // "Escape" -> #(State(..state, mode: Nothing), [])
    _, "ArrowRight" -> navigate(state, "move right", buffer.next)
    _, "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    _, "ArrowUp" -> navigate(state, "move up", buffer.up)
    _, "ArrowDown" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)
    // "q" -> choose_module(state)
    _, "w" -> transform(state, "call", buffer.call_with)
    // "E" -> pick_any(state, "assign", buffer.assign_before)
    // "e" -> pick_any(state, "assign", buffer.assign)
    // "R" -> transform(state, "create record", buffer.create_empty_record)
    // "r" -> create_record(state)
    // "t" -> insert_tag(state)
    _, "y" -> copy(state)
    _, "Y" -> paste(state)
    // // TODO mode is authenticating
    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    // "i" -> insert(state)
    // "o" -> overwrite(state)
    // "p" -> perform(state)
    // "a" -> navigate(state, "increase selection", buffer.increase)
    // "s" -> insert_string(state)
    // "d" -> transform(state, "delete", buffer.delete)
    // "f" -> pick_any(state, "insert function", buffer.insert_function)
    // "g" -> select_field(state)
    // "h" -> insert_handle(state)
    // "j" -> insert_builtin(state)
    // "k" -> navigate(state, "toggle", buffer.toggle_open)
    // "L" -> transform(state, "create list", buffer.create_empty_list)
    // "l" -> transform(state, "create list", buffer.create_list)
    // "@" -> choose_release(state)
    // "#" -> insert_reference(state)
    // // choose release just checks is expression
    // "Z" -> map_buffer(state, "redo", buffer.redo)
    // "z" -> map_buffer(state, "undo", buffer.undo)
    // "x" -> transform(state, "spread", buffer.spread)
    // "c" -> call_function(state)
    // "C" -> transform(state, "call", buffer.call_once)
    // "b" -> transform(state, "create list", buffer.insert_binary)
    // "n" -> insert_integer(state)
    // "m" -> insert_case(state)
    // "v" -> insert_variable(state)
    // "<" -> transform_or_pick(state, "insert before", buffer.insert_before)
    // ">" -> transform_or_pick(state, "insert after", buffer.insert_after)
    _, "Enter" -> confirm(state)
    // " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    // _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
    Editing(id, _error), _ -> {
      let mode = Editing(id, Some(NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
    Nothing, _ -> #(state, [])
    ReadingFromClipboard(id:, rebuild: _), _ -> #(state, [])
    Running(id:, status:), _ -> todo
  }
}

fn navigate(state: State, name, func) {
  use id, Example(buffer:) <- is_editing(state)

  case func(buffer) {
    Ok(buffer) -> {
      let state = set_example(state, id, Example(buffer:))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    Error(_reason) -> action_failed(state, id, name)
  }
}

fn transform(state: State, name, func) {
  use id, Example(buffer:) <- is_editing(state)

  // this returns a generator that will only complete with the typing context. 
  // Where do we look for updated ref's
  // type checking could return them later
  case func(buffer) {
    Ok(gen) -> {
      let state = set_example(state, id, Example(buffer: gen(infer.pure())))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    Error(_reason) -> action_failed(state, id, name)
  }
}

/// don't do key press under a mode switch
fn copy(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.copy_source(buffer) {
    Ok(text) -> #(state, [
      browser.WriteToClipboard(text:, resume: fn(_) { Ignore }),
    ])
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn paste(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.set_expression(buffer) {
    Ok(rebuild) -> {
      let state = State(..state, mode: ReadingFromClipboard(id:, rebuild:))
      #(state, [browser.ReadFromClipboard(ClipboardReadCompleted)])
    }
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn confirm(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  let #(mode, effects) = loop(expression.execute(buffer.source(buffer), []))
  let mode = Running(id, mode)
  #(State(..state, mode:), effects)
}

fn loop(return: Return) {
  case return {
    Ok(value) -> #(Concluded(value), [])
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) ->
      case harness.cast(label, lift) {
        Ok(harness.Abort(reason)) -> #(Failed(reason), [])
        Ok(harness.Alert(message)) -> #(Handling(label, env, k), [
          browser.Alert(message, fn() { Ignore }),
        ])
        Ok(harness.Copy(text)) -> #(Handling(label, env, k), [
          browser.WriteToClipboard(text, ClipboardWriteCompleted),
        ])
        Ok(harness.DecodeJson(raw)) ->
          loop(expression.resume(decode_json.sync(raw), env, k))
        Ok(harness.Download(input)) -> #(Handling(label, env, k), [
          browser.Download(input, fn() { Ignore }),
        ])
        Ok(harness.Fetch(_)) -> todo
        Ok(harness.Flip) ->
          loop(expression.resume(flip.encode(flip.sync()), env, k))
        Ok(harness.Paste) -> todo
        Ok(harness.Print(message)) ->
          loop(expression.resume(print.encode(print.sync(message)), env, k))
        Ok(harness.Prompt(_)) -> todo
        Ok(harness.Random(max)) ->
          loop(expression.resume(random.encode(random.sync(max)), env, k))
        Ok(harness.Visit(_)) -> todo
        Ok(harness.Spotless(service:, operation:)) -> todo
        Error(_) -> todo
      }
    Error(_) -> todo
  }
}

fn is_editing(state: State, then) {
  case state.mode {
    Editing(id:, failure: _) -> then(id, get_example(state, id))
    Nothing -> #(state, [])
    ReadingFromClipboard(..) -> #(state, [])
    Running(id:, status:) -> todo
  }
}

fn action_failed(state, id, name) {
  let state =
    State(..state, mode: Editing(id:, failure: Some(ActionFailed(name))))
  #(state, [])
}
