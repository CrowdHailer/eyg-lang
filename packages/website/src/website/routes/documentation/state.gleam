import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/client
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import morph/editable as e
import morph/input
import morph/navigation
import morph/picker
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/paste
import touch_grass/print
import touch_grass/prompt
import touch_grass/random
import untethered/ledger/client.{NetworkError} as _
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation
import website/routes/documentation/examples
import website/routes/workspace/buffer

pub type State {
  State(mode: Mode, examples: Dict(String, Example))
}

pub type Example {
  Example(buffer: buffer.Buffer)
}

pub type Rebuild(t) =
  fn(t, infer.Context) -> buffer.Buffer

// An edit status could be reused over the applications but viewing it would be separate
// Change Editing -> Focused/Navigating
// Manipulating is called editing, EditingStatus is there
pub type Mode {
  Editing(id: String, failure: Option(Failure))
  EditingInteger(id: String, value: Int, rebuild: Rebuild(Int))
  EditingText(id: String, value: String, rebuild: Rebuild(String))
  Picking(id: String, picker: picker.Picker, rebuild: Rebuild(String))
  ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  Running(id: String, status: Status)
  UnFocused
}

/// Run Status
pub type Status {
  Concluded(Value)
  Handling(ref: Int, env: state.Env(Meta), k: state.Stack(Meta))
  Fetching(env: state.Env(Meta), k: state.Stack(Meta))
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

  ClipboardReadCompleted(Result(String, String))
  EffectHandled(ref: Int, value: Value)
  ModuleFetched(v1.Cid, ir.Node(List(Int)))
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
  // let #(client, init_task) = client.init(origin)

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
  // let #(client, sync_task) = client.fetch_fragments(client, missing_cids)
  let state = State(UnFocused, examples)
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

    // SyncMessage(message) -> {
    //   let State(cache: sync_client, ..) = state
    //   let #(sync_client, effect) = client.update(sync_client, message)
    //   let state = State(..state, cache: sync_client)
    //   // let effects = [, ..effects]
    //   #(state, todo as "client.lustre_run(effect, SyncMessage)")
    // }
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
    EffectHandled(ref:, value:) -> {
      case state.mode {
        Running(id, Handling(ref: r, env:, k:)) if r == ref ->
          resume(ref, value, env, k, state, id)
        _ -> #(state, [])
      }
    }
    ModuleFetched(cid, value) -> todo
    Ignore -> #(state, [])
  }
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  // set error to nothing
  case mode, key {
    _, "Escape" -> #(State(..state, mode: UnFocused), [])
    _, "ArrowRight" -> navigate(state, "move right", buffer.next)
    _, "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    _, "ArrowUp" -> navigate(state, "move up", buffer.up)
    _, "ArrowDown" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)
    // "q" -> choose_module(state)
    _, "w" -> edit(state, manipulation.call_with())
    _, "E" -> edit(state, manipulation.assign_before())
    _, "e" -> edit(state, manipulation.assign())
    _, "R" -> edit(state, manipulation.create_empty_record())
    _, "r" -> edit(state, manipulation.create_record())
    _, "t" -> edit(state, manipulation.insert_tag())
    _, "y" -> copy(state)
    _, "Y" -> paste(state)
    // // TODO mode is authenticating
    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    _, "i" -> edit(state, manipulation.insert())
    _, "o" -> edit(state, manipulation.overwrite())
    _, "p" -> edit(state, manipulation.perform())
    _, "a" -> navigate(state, "increase selection", buffer.increase)
    _, "s" -> edit(state, manipulation.insert_string())
    _, "d" -> edit(state, manipulation.delete())
    _, "f" -> edit(state, manipulation.insert_function())
    _, "g" -> edit(state, manipulation.select_field())
    _, "h" -> edit(state, manipulation.insert_handle())
    _, "j" -> edit(state, manipulation.insert_builtin())
    _, "k" -> navigate(state, "toggle", buffer.toggle_open)
    _, "L" -> edit(state, manipulation.create_empty_list())
    _, "l" -> edit(state, manipulation.create_list())
    // choose release is different type returned i.e. cid
    // _, "@" -> choose_release(state)
    // _, "#" -> insert_reference(state)
    // _, // _, choose release just checks is expression
    _, "Z" -> edit(state, manipulation.redo())
    _, "z" -> edit(state, manipulation.undo())
    _, "x" -> edit(state, manipulation.spread())
    _, "c" -> edit(state, manipulation.call_function())
    _, "C" -> edit(state, manipulation.call_once())
    _, "b" -> edit(state, manipulation.insert_binary())
    _, "n" -> edit(state, manipulation.insert_integer())
    _, "m" -> edit(state, manipulation.insert_case())
    _, "v" -> edit(state, manipulation.insert_variable())
    _, "<" -> edit(state, manipulation.insert_before())
    _, ">" -> edit(state, manipulation.insert_after())
    _, "Enter" -> confirm(state)
    _, " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    Editing(id, _error), _ -> {
      let mode = Editing(id, Some(NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
    UnFocused, _ -> #(state, [])
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

// can't 1 for 1 map over a working state for the buffer because of the gen -> buffer step in resolved
fn edit(state, manipulation) {
  use id, Example(buffer:) <- is_editing(state)
  let manipulation.Operation(name:, apply:) = manipulation
  case apply(buffer) {
    Ok(manipulation.Resolved(gen)) -> {
      let state = set_example(state, id, Example(buffer: gen(infer.pure())))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    Ok(manipulation.PickSingle(picker, rebuild)) -> {
      let mode = Picking(id, picker, rebuild:)
      #(State(..state, mode:), [])
    }
    Ok(manipulation.EnterText(value, rebuild)) -> {
      let mode = EditingText(id, value, rebuild:)
      #(State(..state, mode:), [])
    }
    Ok(manipulation.EnterInteger(value, rebuild)) -> {
      let mode = EditingInteger(id, value, rebuild:)
      #(State(..state, mode:), [])
    }
    Error(Nil) -> action_failed(state, id, name)
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
  let #(mode, effects) = loop(0, expression.execute(buffer.source(buffer), []))
  let mode = Running(id, mode)
  #(State(..state, mode:), effects)
}

fn resume(ref, value, env, k, state, id) {
  let #(mode, effects) = loop(ref + 1, expression.resume(value, env, k))
  let mode = Running(id, mode)
  #(State(..state, mode:), effects)
}

fn handled(ref, cast) {
  fn(r) { EffectHandled(ref:, value: cast(r)) }
}

// This could be something not called a runner. loop function in this module would reuse it.
// This cant be reused by workspace as the shell keeps history of effects
// if cast takes a list of interfaces we can have runners with a subset of effects
// Normally it is best to copy paste this function
// 
// This loop is tied to this route/app by the return message type
// The return of the effect could be a code return wot need counter but I don't know how you track trace/effect id
// Probably best to fix module lookup first, as well as spotless, where do we cache, but it should be the same as 
// spotless tokens last over different runs
// 
// Follow the elm pattern or the situation where I like midas pass in effect handlers, so we have a on handled
// on fetched
// hub has an API client
// hub DOES NOT have a state/cache or it's own message types
// The whole thing is a reference to the hub in the website
// hub might have a selection of remotes
// hub.module(cid)
// hub.release() -> current status
// hub.get_release -> tasks if invalid needs an error might always have come into existance
// get_release -> it is ok or refreshes, or errors if the hash is wrong
// pending and 
fn loop(ref: Int, return: Return) -> #(Status, List(browser.Effect(Message))) {
  case return {
    Ok(value) -> #(Concluded(value), [])
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) ->
      case harness.cast(label, lift) {
        Ok(harness.Abort(reason)) -> #(Failed(reason), [])
        Ok(harness.Alert(message)) -> #(Handling(ref, env, k), [
          browser.Alert(message, fn() { EffectHandled(ref, v.unit()) }),
        ])
        Ok(harness.Copy(text)) -> #(Handling(ref, env, k), [
          browser.WriteToClipboard(text, handled(ref, copy.encode)),
        ])
        Ok(harness.DecodeJson(raw)) ->
          loop(ref, expression.resume(decode_json.sync(raw), env, k))
        Ok(harness.Download(input)) -> #(Handling(ref, env, k), [
          browser.Download(input, fn() { EffectHandled(ref, v.unit()) }),
        ])
        Ok(harness.Fetch(request)) -> #(Handling(ref, env, k), [
          browser.fetch(request, handled(ref, fetch.encode)),
        ])
        Ok(harness.Flip) ->
          loop(ref, expression.resume(flip.encode(flip.sync()), env, k))
        Ok(harness.Paste) -> #(Handling(ref, env, k), [
          browser.ReadFromClipboard(handled(ref, paste.encode)),
        ])
        Ok(harness.Print(message)) ->
          loop(
            ref,
            expression.resume(print.encode(print.sync(message)), env, k),
          )
        Ok(harness.Prompt(question)) -> #(Handling(ref, env, k), [
          browser.Prompt(question, handled(ref, prompt.encode)),
        ])
        Ok(harness.Random(max)) ->
          loop(ref, expression.resume(random.encode(random.sync(max)), env, k))
        Ok(harness.Visit(uri)) -> #(Handling(ref, env, k), [
          browser.Visit(uri:, resume: fn(result) {
            let value = case result {
              Ok(_) -> v.ok(v.unit())
              Error(reason) -> v.error(v.String(reason))
            }
            EffectHandled(ref, value)
          }),
        ])
        Ok(harness.Spotless(service:, operation:)) -> todo
        Error(break) -> #(Failed(simple_debug.describe(break)), [])
      }
    Error(#(break.UndefinedReference(cid), _meta, env, k)) -> {
      let refs = todo
      case dict.get(refs, cid) {
        Ok(value) -> loop(ref, expression.resume(value, env, k))
        Error(Nil) -> #(Fetching(env, k), [get_module(cid)])
      }
    }
    Error(#(break, _, _, _)) -> #(Failed(simple_debug.describe(break)), [])
  }
}

fn get_module(cid: v1.Cid) {
  // If we pass in a runner state, then it needs to be returned every time
  let operation = client.get_module(cid)
  // TODO configure origin
  let request = operation.to_request(operation, origin.https("eyg.run"))
  // Do we want to look up if already looking

  // This is a browser action
  browser.Fetch(request, fn(result) {
    case result {
      Ok(response) ->
        case client.get_module_response(response) {
          Ok(Some(source)) -> todo as "has to return just source"
          // state arrives but then we need to work with it. update somehting internaly
          // pure_loop(
          //   expression.execute(
          //     source |> tree.map_annotation(fn(_) { [] }),
          //     [],
          //   ),
          // )
          Ok(None) -> todo
          Error(_) -> todo
        }
      Error(reason) -> Error(NetworkError(string.inspect(reason)))
    }
    |> ModuleFetched(cid, _)
  })
}

fn pure_loop(return: Return) -> #(Status, List(browser.Effect(Message))) {
  case return {
    Ok(value) -> #(Concluded(value), [])

    Error(#(break.UndefinedReference(cid), _meta, env, k)) -> {
      let refs = todo
      case dict.get(refs, cid) {
        Ok(value) -> pure_loop(expression.resume(value, env, k))
        Error(Nil) -> #(Fetching(env, k), [get_module(cid)])
      }
    }
    Error(#(break, _, _, _)) -> #(Failed(simple_debug.describe(break)), [])
  }
}

fn is_editing(state: State, then) {
  case state.mode {
    Editing(id:, failure: _) -> then(id, get_example(state, id))
    UnFocused -> #(state, [])
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
