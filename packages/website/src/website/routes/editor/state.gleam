import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/schema
import eyg/interpreter/state
import eyg/ir/tree as ir
import morph/buffer
import multiformats/cid/v1
import website/config
import website/harness/harness
import website/run

pub type State {
  State(
    previous: List(run.Previous),
    scope: List(state.Value(Meta)),
    buffer: buffer.Buffer,
    context: run.Context(Message),
    display_help: Bool,
  )
}

type Meta =
  List(Int)

pub fn init(config) {
  let config.Config(origin:) = config

  let buffer = buffer.from_source(ir.vacant(), infer.pure())
  let context =
    run.empty(
      origin,
      EffectHandled,
      SpotlessConnectCompleted,
      ModuleLookupCompleted,
      PullPackagesCompleted,
    )
    |> run.pull()
  let state =
    State(previous: [], scope: [], buffer:, context:, display_help: False)
  #(state, [])
}

pub type Message {
  ToggleHelp
  ToggleFullscreen
  ShareCurrent
  EffectHandled(task_id: Int, value: state.Value(Meta))
  SpotlessConnectCompleted(harness.Service, Result(String, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
  PullPackagesCompleted(Result(List(schema.ArchivedEntry), String))
}

pub fn update(state: State, message) -> #(State, List(_)) {
  case message {
    ToggleHelp -> #(State(..state, display_help: !state.display_help), [])
    ToggleFullscreen -> panic
    //  #(state, [DoToggleFullScreen])
    ShareCurrent -> panic
    EffectHandled(task_id: _, value: _) -> panic
    SpotlessConnectCompleted(_, _) -> panic
    ModuleLookupCompleted(_, _) -> panic
    PullPackagesCompleted(_) -> panic
    // ShareCurrent -> {
    //   let State(sync:, ..) = state
    //   let editable = snippet.source(state.shell.source)
    //   let source =
    //     e.to_annotated(editable, [])
    //     |> ir.clear_annotation()
    //   let #(sync, actions) = client.share(sync, source)
    //   let state = State(..state, sync:)
    //   // Error action is response possible
    //   #(state, list.map(actions, SyncAction))
    // }
  }
}
