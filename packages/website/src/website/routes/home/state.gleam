import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/javascript/promise
import gleam/option.{type Option, None, Some}
import lustre/effect
import multiformats/cid/v1
import website/components/example
import website/components/reload
import website/components/runner
import website/components/snippet
import website/config
import website/harness/harness
import website/routes/home/examples
import website/routes/workspace/buffer
import website/run
import website/sync/client

pub type Meta =
  List(Int)

pub type Example {
  Simple(buffer.Buffer)
  // reload is parameterised by meta, Simple is not
  Reload(reload.Reload(List(Int)))
}

pub type State {
  State(
    active: Active,
    examples: Dict(String, Example),
    context: run.Context(Message),
  )
}

pub type Active {
  Editing(String, Option(snippet.Failure))
  Nothing
}

pub fn init(config) {
  let config.Config(origin:) = config
  let context =
    run.empty(EffectHandled, SpotlessConnectCompleted, ModuleLookupCompleted)
  let examples =
    examples.all()
    |> dict.from_list

  let state = State(Nothing, examples:, context:)
  #(state, [])
}

// Dont abstact as is useful because it uses the specific page State
pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

pub type Message {
  EffectHandled(task_id: Int, value: state.Value(Meta))
  SpotlessConnectCompleted(harness.Service, Result(String, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
}

// ReloadMessage(String, reload.Message(List(Int)))

pub fn update(state: State, message: Message) {
  let State(mode:, ..) = state
  case message {
    EffectHandled(task_id:, value:) -> todo
    SpotlessConnectCompleted(service, result) -> {
      let #(context, effects) =
        run.connect_completed(state.context, service, result)
      #(State(..state, context:), effects)
    }
    ModuleLookupCompleted(cid, result) -> {
      let #(context, done, effects) =
        run.get_module_completed(state.context, cid, result)
      #(State(..state, context:), effects)
    }
  }
  // ReloadMessage(id, message) -> {
  //   let state = close_other_examples(state, id)
  //   let example = get_example(state, id)
  //   case example {
  //     Reload(example) -> {
  //       let #(example, action) = reload.update(example, message)
  //       let state = set_example(state, id, Reload(example))
  //       let #(failure, action) = case action {
  //         reload.Nothing -> #(None, effect.none())
  //         reload.Failed(failure) -> #(Some(failure), effect.none())
  //         reload.ReturnToCode -> #(
  //           None,
  //           dispatch_nothing(snippet.focus_on_buffer()),
  //         )
  //         reload.FocusOnInput -> #(
  //           None,
  //           dispatch_nothing(snippet.focus_on_input()),
  //         )
  //         reload.ReadFromClipboard -> #(
  //           None,
  //           dispatch_to_snippet(id, snippet.read_from_clipboard()),
  //         )
  //         reload.WriteToClipboard(text) -> #(
  //           None,
  //           dispatch_to_snippet(id, snippet.write_to_clipboard(text)),
  //         )
  //       }
  //       let state = State(..state, active: Editing(id, failure))
  //       #(state, action)
  //     }
  //     _ ->
  //       panic as "SimpleMessage should not be sent to other kinds of example"
  //   }
  // }
}
// fn close_other_examples(state, id) {
//   let State(active:, ..) = state
//   case active {
//     Editing(current, _) if current != id -> {
//       let example = get_example(state, current)
//       let example = case example {
//         Simple(example) -> example.finish_editing(example) |> Simple
//         Reload(example) -> reload.finish_editing(example) |> Reload
//       }
//       set_example(state, current, example)
//     }
//     _ -> state
//   }
// }
