import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/hub/schema
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/option.{type Option}
import morph/buffer
import multiformats/cid/v1
import ogre/origin
import spotless/oauth_2_1/token
import touch_grass/harness/browser as harness
import website/config

pub type State {
  State(
    previous: List(Previous),
    scope: List(state.Value(Meta)),
    buffer: buffer.Buffer,
    cache: cache.Cache(Meta),
    origin: origin.Origin,
    display_help: Bool,
  )
}

type Meta =
  List(Int)

pub fn init(config) {
  let config.Config(origin:) = config

  let cache = cache.ready()
  let buffer = buffer.from_source(ir.vacant(), infer.pure(), cache.types(cache))
  let state =
    State(
      previous: [],
      scope: [],
      buffer:,
      cache:,
      origin:,
      display_help: False,
    )
  #(state, [])
}

pub type Message {
  ToggleHelp
  ToggleFullscreen
  ShareCurrent
  EffectHandled(task_id: Int, value: state.Value(Meta))
  SpotlessConnectCompleted(harness.Service, Result(token.Response, String))
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

pub type Previous {
  Previous(
    value: Option(state.Value(List(Int))),
    effects: List(Effect),
    buffer: buffer.Buffer,
  )
}

pub type Effect =
  #(String, #(state.Value(List(Int)), state.Value(List(Int))))
