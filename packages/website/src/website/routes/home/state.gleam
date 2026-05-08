import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/hub/publisher
import eyg/hub/release
import eyg/hub/schema
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import morph/buffer
import morph/editable as e
import morph/input
import morph/picker
import multiformats/cid/v1
import website/command
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation as m
import website/routes/documentation/state as doc
import website/routes/home/examples
import website/run

pub type Meta =
  List(Int)

pub type State {
  State(
    mode: doc.Mode,
    examples: Dict(String, buffer.Buffer),
    context: run.Context(Message),
  )
}

pub fn init(config) {
  let config.Config(origin:) = config
  let context =
    run.empty(
      origin,
      EffectHandled,
      SpotlessConnectCompleted,
      ModuleLookupCompleted,
      PullPackagesCompleted,
    )
    |> run.pull()

  let #(examples, context) = doc.init_collection(examples.all(), context)
  let #(context, effects) = run.flush(context)

  // TODO move to a reload_buffer.create 
  // typing should be able to do a typecheck against, that would show the actual required type
  // let assert Ok(buffer) = dict.get(examples, examples.hot_reload_key)

  // let #(run, context, _effects) =
  //   expression.execute(buffer.source(buffer), [])
  //   |> run.loop(context, expression.resume)
  // case run {
  //   run.Concluded(mod) -> {
  //     case expression.call_field(mod, "init", [], []) {
  //       Ok(app_state) -> todo
  //       Error(_) -> todo
  //     }
  //   }
  //   run.Exception(_) -> todo
  //   run.Aborted(_) -> todo
  //   run.Handling(task_id:, env:, k:) -> todo
  //   run.Fetching(module:, env:, k:) -> todo
  // }

  let state = State(doc.UnFocused, examples:, context:)
  #(state, effects)
}

// Dont abstact as is useful because it uses the specific page State
pub fn get_example(state: State, id) {
  let assert Ok(buffer) = dict.get(state.examples, id)
  buffer
}

pub fn set_example(state: State, id, buffer) {
  State(..state, examples: dict.insert(state.examples, id, buffer))
}

fn continue(state, id, gen) {
  let State(context:, ..) = state
  let buffer = gen(infer_context(context))
  let state = set_example(state, id, buffer)
  // reload key or type in the example or metadata 
  let missing_references = infer.missing_references(buffer.analysis)
  let context = run.fetch_all(missing_references, context)
  let #(context, effects) = run.flush(context)
  let state = State(..state, mode: doc.Navigating(id:, failure: None), context:)
  #(state, effects)
}

pub type Message {
  UserClickedCode(id: String, path: List(Int))
  UserPressedKey(key: String)
  InputMessage(input.Message)
  PickerMessage(picker.Message)

  ClipboardReadCompleted(Result(String, String))
  Ignore
  EffectHandled(task_id: Int, value: state.Value(Meta))
  SpotlessConnectCompleted(harness.Service, Result(String, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
  PullPackagesCompleted(Result(List(schema.ArchivedEntry), String))
}

pub fn update(state: State, message) {
  let State(mode:, ..) = state
  case message, mode {
    UserClickedCode(id:, path:), _ -> {
      let buffer = get_example(state, id)
      let buffer = buffer.focus_at(buffer, path) |> result.unwrap(buffer)
      let state = set_example(state, id, buffer)
      let state = State(..state, mode: doc.Navigating(id:, failure: None))
      #(state, [])
    }
    UserPressedKey(key:), doc.Navigating(id, _)
    | UserPressedKey(key:), doc.Running(id, run.Concluded(_))
    | UserPressedKey(key:), doc.Running(id, run.Aborted(_))
    | UserPressedKey(key:), doc.Running(id, run.Exception(_))
    ->
      // don't wrap this up in shared behaviour taking (context, buffer) as the top level key commands will change
      user_pressed_key(state, id, key)
    UserPressedKey(_), _ -> #(state, [])
    InputMessage(message), doc.Manipulating(id, m.EnterInteger(value, rebuild)) ->
      case input.update_number(value, message) {
        input.Continue(new) -> {
          let mode = doc.Manipulating(id, m.EnterInteger(new, rebuild))
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) -> continue(state, id, rebuild(value, _))
        input.Cancelled -> {
          let state = State(..state, mode: doc.Navigating(id:, failure: None))
          #(state, [])
        }
      }
    InputMessage(message), doc.Manipulating(id, m.EnterText(value, rebuild)) ->
      case input.update_text(value, message) {
        input.Continue(new) -> {
          let mode = doc.Manipulating(id, m.EnterText(new, rebuild))
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) -> continue(state, id, rebuild(value, _))
        input.Cancelled -> {
          let state = State(..state, mode: doc.Navigating(id:, failure: None))
          #(state, [])
        }
      }

    InputMessage(_), _ -> #(state, [])
    PickerMessage(message), doc.Manipulating(id, m.PickSingle(_picker, rebuild))
    ->
      case message {
        picker.Updated(picker:) -> {
          let mode = doc.Manipulating(id, m.PickSingle(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(label) -> continue(state, id, rebuild(label, _))
        picker.Dismissed -> #(
          State(..state, mode: doc.Navigating(id:, failure: None)),
          [],
        )
      }
    PickerMessage(message), doc.Manipulating(id, m.PickCid(_picker, rebuild)) ->
      case message {
        picker.Updated(picker:) -> {
          let mode = doc.Manipulating(id, m.PickCid(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(text) -> {
          case v1.from_string(text) {
            Ok(#(cid, _)) -> continue(state, id, rebuild(cid, _))
            Error(_) -> {
              echo "need error message for bad cid"
              #(state, [])
            }
          }
        }
        picker.Dismissed -> #(
          State(..state, mode: doc.Navigating(id:, failure: None)),
          [],
        )
      }
    PickerMessage(message),
      doc.Manipulating(id, m.PickRelease(_picker, rebuild))
    ->
      case message {
        picker.Updated(picker:) -> {
          let mode = doc.Manipulating(id, m.PickRelease(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(text) -> {
          case cache.package(state.context.cache, text) {
            Ok(#(v, m)) -> continue(state, id, rebuild(#(text, v, m), _))
            Error(_) -> {
              echo "need error message for bad cid"
              #(state, [])
            }
          }
        }
        picker.Dismissed -> #(
          State(..state, mode: doc.Navigating(id:, failure: None)),
          [],
        )
      }
    PickerMessage(_), _ -> #(state, [])
    ClipboardReadCompleted(return), doc.ReadingFromClipboard(id, rebuild) ->
      case return {
        Ok(text) ->
          case json.parse(text, dag_json.decoder(Nil)) {
            Ok(expression) ->
              continue(state, id, rebuild(e.from_annotated(expression), _))
            Error(_) -> action_failed(state, id, "paste")
          }
        Error(_) -> action_failed(state, id, "paste")
      }
    ClipboardReadCompleted(_), _ -> #(state, [])
    Ignore, _ -> #(state, [])
    EffectHandled(task_id: tid, value:),
      doc.Running(id:, status: run.Handling(task_id:, env:, k:))
      if tid == task_id
    -> {
      let #(mode, context, effects) =
        expression.resume(value, env, k)
        |> run.loop(state.context, expression.resume)
      let mode = doc.Running(id, mode)
      #(State(..state, mode:, context:), effects)
    }
    EffectHandled(_, _), _ -> #(state, [])
    SpotlessConnectCompleted(service, result), _ -> {
      let #(context, effects) =
        run.connect_completed(state.context, service, result)
      #(State(..state, context:), effects)
    }
    ModuleLookupCompleted(cid, result), _ -> {
      let #(context, done) =
        run.get_module_completed(state.context, cid, result)
      let examples = doc.reanalyse_examples(state.examples, done, context)
      let state = State(..state, examples:)
      // use the completed cid not the looked up cid as dependencies might have resolved
      let #(context, effects) = run.flush(context)
      case state.mode {
        doc.Running(id, run.Pending(cache.Content(module), env:, k:)) -> {
          case list.key_find(done, module) {
            Ok(Ok(value)) -> {
              let #(run, context, inner_effects) =
                expression.resume(value, env, k)
                |> run.loop(context, expression.resume)
              let mode = doc.Running(id, run)
              #(
                State(..state, context:, mode:),
                list.append(effects, inner_effects),
              )
            }
            // If the module is a bad one the running state stays the same. it's up for the view to render the status
            Ok(Error(_)) -> #(State(..state, context:), effects)
            Error(Nil) -> #(State(..state, context:), effects)
          }
        }
        _ -> #(State(..state, context:), effects)
      }
    }
    PullPackagesCompleted(result), _ -> {
      let cache = state.context.cache
      let cache = case result {
        Ok(entries) -> {
          list.fold(entries, cache, fn(cache, entry) {
            let assert Ok(payload) =
              json.parse(entry.payload, publisher.decoder())

            let publisher.Release(package:, version:, module:) = payload.content
            let release = release.Release(package:, version:, module:)
            let #(cache, _done) = cache.pulled(cache, entry.cursor, release)
            cache
          })
        }
        Error(_reason) -> {
          cache.Cache(..cache, cursor_status: cache.Pulled)
        }
      }
      let context = run.Context(..state.context, cache:)
      let #(context, effects) = run.flush(context)
      #(State(..state, context:), effects)
    }
  }
}

fn user_pressed_key(state, id, key) {
  case key {
    "Escape" -> #(State(..state, mode: doc.UnFocused), [])
    "ArrowRight" -> navigate(state, "move right", buffer.next)
    "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    "ArrowUp" -> navigate(state, "move up", buffer.up)
    "ArrowDown" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)  Not supported in documentation
    // "q" -> choose_module(state) Not supported in documentation
    "w" -> edit(state, m.call_with())
    "E" -> edit(state, m.assign_before())
    "e" -> edit(state, m.assign())
    "R" -> edit(state, m.create_empty_record())
    "r" -> edit(state, m.create_record())
    "t" -> edit(state, m.insert_tag())
    "y" -> copy(state)
    "Y" -> paste(state)
    // // TODO mode is authenticating
    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    "i" -> edit(state, m.insert())
    "o" -> edit(state, m.overwrite())
    "p" -> edit(state, m.perform())
    "a" -> navigate(state, "increase selection", buffer.increase)
    "s" -> edit(state, m.insert_string())
    "d" -> edit(state, m.delete())
    "f" -> edit(state, m.insert_function())
    "g" -> edit(state, m.select_field())
    "h" -> edit(state, m.insert_handle())
    "j" -> edit(state, m.insert_builtin())
    "k" -> navigate(state, "toggle", buffer.toggle_open)
    "L" -> edit(state, m.create_empty_list())
    "l" -> edit(state, m.create_list())
    "@" -> edit(state, m.choose_release(state.context.cache))
    "#" -> edit(state, m.insert_reference())
    "Z" -> edit(state, m.redo())
    "z" -> edit(state, m.undo())
    "x" -> edit(state, m.spread())
    "c" -> edit(state, m.call_function())
    "C" -> edit(state, m.call_once())
    "b" -> edit(state, m.insert_binary())
    "n" -> edit(state, m.insert_integer())
    "m" -> edit(state, m.insert_case())
    "v" -> edit(state, m.insert_variable())
    "<" -> edit(state, m.insert_before())
    ">" -> edit(state, m.insert_after())
    "Enter" -> confirm(state)
    " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    _ -> {
      let mode = doc.Navigating(id, Some(command.NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
  }
}

fn navigate(state: State, name, func) {
  use id, buffer <- is_editing(state)

  case func(buffer) {
    Ok(buffer) -> {
      let state = set_example(state, id, buffer)
      let state = State(..state, mode: doc.Navigating(id:, failure: None))
      #(state, [])
    }
    Error(_reason) -> action_failed(state, id, name)
  }
}

// can't 1 for 1 map over a working state for the buffer because of the gen -> buffer step in resolved
fn edit(state, manipulation) {
  use id, buffer <- is_editing(state)
  let m.Operation(name:, apply:) = manipulation
  case apply(buffer) {
    Ok(m.Resolved(gen)) -> continue(state, id, gen)
    Ok(m.UserInput(input)) -> {
      #(State(..state, mode: doc.Manipulating(id, input)), [])
    }
    Error(Nil) -> action_failed(state, id, name)
  }
}

/// don't do key press under a mode switch
fn copy(state: State) {
  use id, buffer <- is_editing(state)
  case buffer.copy_source(buffer) {
    Ok(text) -> #(state, [
      browser.WriteToClipboard(text:, resume: fn(_) { Ignore }),
    ])
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn paste(state: State) {
  use id, buffer <- is_editing(state)
  case buffer.set_expression(buffer) {
    Ok(rebuild) -> {
      let state = State(..state, mode: doc.ReadingFromClipboard(id:, rebuild:))
      #(state, [browser.ReadFromClipboard(ClipboardReadCompleted)])
    }
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn confirm(state: State) {
  use id, buffer <- is_editing(state)
  let #(mode, context, effects) =
    expression.execute(buffer.source(buffer), [])
    |> run.loop(state.context, expression.resume)
  let mode = doc.Running(id, mode)
  #(State(..state, mode:, context:), effects)
}

/// is_editing or concluded
fn is_editing(state: State, then) {
  case state.mode {
    doc.Navigating(id:, failure: _) -> then(id, get_example(state, id))
    doc.Running(id:, status: _) -> then(id, get_example(state, id))
    _ -> #(state, [])
  }
}

fn action_failed(state, id, name) {
  let state =
    State(
      ..state,
      mode: doc.Navigating(id:, failure: Some(command.ActionFailed(name))),
    )
  #(state, [])
}

fn infer_context(context: run.Context(_)) {
  harness.infer_context(run.module_types(context))
}
