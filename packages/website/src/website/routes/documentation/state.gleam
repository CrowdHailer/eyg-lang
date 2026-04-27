import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/dag_json
import gleam/dict.{type Dict}
import gleam/http/response
import gleam/json
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import morph/analysis
import morph/editable as e
import morph/input
import morph/navigation
import morph/picker
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/print
import touch_grass/prompt
import touch_grass/random
import website/components/snippet
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
  EditingInteger(id: String, value: Int, rebuild: Rebuild(Int))
  EditingText(id: String, value: String, rebuild: Rebuild(String))
  Picking(id: String, picker: picker.Picker, rebuild: Rebuild(String))
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
  InputMessage(input.Message)
  PickerMessage(picker.Message)
  SyncMessage(client.Message)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
  PromptCompleted(Result(String, Nil))
  FetchCompleted(Result(response.Response(BitArray), String))
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
      // keep evaluation on example, if it runs don't print type errors. but show them in the code
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
    InputMessage(message) -> {
      let State(mode:, ..) = state
      case mode, message {
        EditingInteger(id:, value:, rebuild:), _ ->
          case input.update_number(value, message) {
            input.Continue(new) -> {
              let mode = EditingInteger(..mode, value: new)
              let state = State(..state, mode:)
              #(state, [])
            }
            input.Confirmed(value) -> {
              let state =
                set_example(state, id, Example(rebuild(value, infer.pure())))
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
            input.Cancelled -> {
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
          }
        EditingText(id:, value:, rebuild:), _ ->
          case input.update_text(value, message) {
            input.Continue(new) -> {
              let mode = EditingText(..mode, value: new)
              let state = State(..state, mode:)
              #(state, [])
            }
            input.Confirmed(value) -> {
              let state =
                set_example(state, id, Example(rebuild(value, infer.pure())))
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
            input.Cancelled -> {
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
          }
        _, _ -> #(state, [])
      }
    }
    PickerMessage(message) -> {
      let State(mode:, ..) = state
      case mode {
        Picking(id:, rebuild:, ..) ->
          case message {
            picker.Updated(picker:) -> #(
              State(..state, mode: Picking(id:, picker:, rebuild:)),
              [],
            )
            picker.Decided(label) -> {
              let state =
                set_example(state, id, Example(rebuild(label, infer.pure())))
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
            picker.Dismissed -> #(
              State(..state, mode: Editing(id:, failure: None)),
              [],
            )
          }
        _ -> todo
      }
    }
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
        Running(id, Handling(label: "Copy", env:, k:)) ->
          resume(copy.encode(result), env, k, state, id)
        _ -> #(state, [])
      }
    }
    PromptCompleted(result) -> {
      case state.mode {
        Running(id, Handling(label: "Prompt", env:, k:)) ->
          resume(prompt.encode(result), env, k, state, id)
        _ -> #(state, [])
      }
    }
    FetchCompleted(result) -> {
      case state.mode {
        Running(id, Handling(label: "Fetch", env:, k:)) -> {
          let result = result.map_error(result, string.inspect)
          resume(fetch.encode(result), env, k, state, id)
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
    _, "E" -> pick_any(state, "assign", buffer.assign_before)
    _, "e" -> pick_any(state, "assign", buffer.assign)
    _, "R" -> transform(state, "create record", buffer.create_empty_record)
    _, "r" -> create_record(state)
    _, "t" -> insert_tag(state)
    _, "y" -> copy(state)
    _, "Y" -> paste(state)
    // // TODO mode is authenticating
    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    _, "i" -> insert(state)
    _, "o" -> overwrite(state)
    _, "p" -> perform(state)
    _, "a" -> navigate(state, "increase selection", buffer.increase)
    _, "s" -> insert_string(state)
    _, "d" -> transform(state, "delete", buffer.delete)
    _, "f" -> pick_any(state, "insert function", buffer.insert_function)
    // _, "g" -> select_field(state)
    // _, "h" -> insert_handle(state)
    // _, "j" -> insert_builtin(state)
    _, "k" -> navigate(state, "toggle", buffer.toggle_open)
    _, "L" -> transform(state, "create list", buffer.create_empty_list)
    _, "l" -> transform(state, "create list", buffer.create_list)
    // _, "@" -> choose_release(state)
    // _, "#" -> insert_reference(state)
    // _, // _, choose release just checks is expression
    // _, "Z" -> map_buffer(state, "redo", buffer.redo)
    // _, "z" -> map_buffer(state, "undo", buffer.undo)
    _, "x" -> transform(state, "spread", buffer.spread)
    // _, "c" -> call_function(state)
    _, "C" -> transform(state, "call", buffer.call_once)
    _, "b" -> transform(state, "create list", buffer.insert_binary)
    _, "n" -> insert_integer(state)
    // _, "m" -> insert_case(state)
    // _, "v" -> insert_variable(state)
    // _, "<" -> transform_or_pick(state, "insert before", buffer.insert_before)
    // _, ">" -> transform_or_pick(state, "insert after", buffer.insert_after)
    _, "Enter" -> confirm(state)
    _, " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    // _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
    Editing(id, _error), _ -> {
      let mode = Editing(id, Some(NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
    Nothing, _ -> #(state, [])
    ReadingFromClipboard(id: _, rebuild: _), _ -> #(state, [])
    Running(id: _, status: _), _ -> #(state, [])
    Picking(id: _, picker: _, rebuild: _), _ -> #(state, [])
    EditingInteger(id: _, value: _, rebuild: _), _ -> #(state, [])
    EditingText(id: _, value: _, rebuild: _), _ -> #(state, [])
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

fn pick_any(state, name, func) {
  use id, Example(buffer:) <- is_editing(state)
  case func(buffer) {
    Ok(rebuild) -> {
      let state = State(..state, mode: Picking(id, picker.new("", []), rebuild))
      #(state, [])
    }
    Error(_) -> action_failed(state, id, name)
  }
}

fn create_record(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.create_record(buffer) {
    Ok(rebuild) -> {
      let hints = case buffer.target_type(buffer) {
        Ok(t.Record(rows)) -> listx.value_map(analysis.rows(rows), debug.mono)
        _ -> []
      }
      case hints {
        [] -> {
          let rebuild = fn(label, context) { rebuild([label], context) }
          let state =
            State(..state, mode: Picking(id, picker.new("", []), rebuild))
          #(state, [])
        }
        _ -> {
          let buffer = rebuild(listx.keys(hints), _)(infer.pure())
          let state = set_example(state, id, Example(buffer:))
          let state = State(..state, mode: Editing(id:, failure: None))
          #(state, [])
        }
      }
    }
    Error(_) -> todo
  }
}

fn insert_tag(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.tag(buffer) {
    Ok(rebuild) -> {
      let hints = case buffer.target_type(buffer) {
        Ok(t.Union(variants)) ->
          listx.value_map(analysis.rows(variants), debug.mono)
        _ -> []
      }
      let state =
        State(..state, mode: Picking(id, picker.new("", hints), rebuild))
      #(state, [])
    }
    Error(_) -> action_failed(state, id, "tag")
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

fn insert(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.insert(buffer) {
    Ok(#(value, rebuild)) -> #(
      State(..state, mode: Picking(id, picker.new(value, []), rebuild:)),
      [],
    )
    Error(Nil) -> action_failed(state, id, "insert")
  }
}

fn overwrite(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.overwrite(buffer) {
    Ok(rebuild) -> {
      let hints = case buffer.target_type(buffer) {
        Ok(t.Record(rows)) -> listx.value_map(analysis.rows(rows), debug.mono)
        _ -> []
      }
      let state =
        State(..state, mode: Picking(id, picker.new("", hints), rebuild))
      #(state, [])
    }
    Error(_) -> action_failed(state, id, "record")
  }
}

fn perform(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.perform(buffer) {
    Ok(rebuild) -> {
      let hints = effect_hints()
      #(State(..state, mode: Picking(id, picker.new("", hints), rebuild:)), [])
    }
    Error(Nil) -> action_failed(state, id, "perform")
  }
}

fn effect_hints() {
  list.map(harness.types(harness.effects()), fn(effect) {
    let #(key, types) = effect
    #(key, snippet.render_effect(types))
  })
}

fn insert_string(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.insert_string(buffer) {
    Ok(#(value, rebuild)) -> #(
      State(..state, mode: EditingText(id, value:, rebuild:)),
      [],
    )
    Error(_) -> action_failed(state, id, "insert string")
  }
}

fn insert_integer(state) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.insert_integer(buffer) {
    Ok(#(value, rebuild)) -> {
      #(State(..state, mode: EditingInteger(id:, value:, rebuild:)), [])
    }
    Error(Nil) -> action_failed(state, id, "insert integer")
  }
}

fn confirm(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  let #(mode, effects) = loop(expression.execute(buffer.source(buffer), []))
  let mode = Running(id, mode)
  #(State(..state, mode:), effects)
}

fn resume(value, env, k, state, id) {
  let #(mode, effects) = loop(expression.resume(value, env, k))
  let mode = Running(id, mode)
  #(State(..state, mode:), effects)
}

// This could be something not called a runner. loop function in this module would reuse it.
// This cant be reused by workspace as the shell keeps history of effects
// if cast takes a list of interfaces we can have runners with a subset of effects
// Normally it is best to copy paste this function
fn loop(return: Return) -> #(Status, List(browser.Effect(Message))) {
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
        Ok(harness.Fetch(request)) -> #(Handling(label, env, k), [
          browser.fetch(request, FetchCompleted),
        ])
        Ok(harness.Flip) ->
          loop(expression.resume(flip.encode(flip.sync()), env, k))
        Ok(harness.Paste) -> #(Handling(label, env, k), [
          browser.ReadFromClipboard(ClipboardReadCompleted),
        ])
        Ok(harness.Print(message)) ->
          loop(expression.resume(print.encode(print.sync(message)), env, k))
        Ok(harness.Prompt(question)) -> #(Handling(label, env, k), [
          browser.Prompt(question, PromptCompleted),
        ])
        Ok(harness.Random(max)) ->
          loop(expression.resume(random.encode(random.sync(max)), env, k))
        Ok(harness.Visit(uri)) -> #(Handling(label, env, k), [
          browser.Visit(uri:, resume: fn(_) { Ignore }),
        ])
        Ok(harness.Spotless(service:, operation:)) -> todo
        Error(break) -> #(Failed(simple_debug.describe(break)), [])
      }
    Error(#(break, _, _, _)) -> #(Failed(simple_debug.describe(break)), [])
  }
}

fn is_editing(state: State, then) {
  case state.mode {
    Editing(id:, failure: _) -> then(id, get_example(state, id))
    Nothing -> #(state, [])
    ReadingFromClipboard(..) -> #(state, [])
    Running(id: _, status: _) -> #(state, [])
    Picking(id: _, picker: _, rebuild: _) -> #(state, [])
    _ -> #(state, [])
  }
}

fn action_failed(state, id, name) {
  let state =
    State(..state, mode: Editing(id:, failure: Some(ActionFailed(name))))
  #(state, [])
}
