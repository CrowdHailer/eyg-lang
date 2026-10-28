import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug as analysis_debug
import eyg/hub/cache
import eyg/hub/client
import eyg/hub/schema
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser as _
import glasshouse/archive
import glasshouse/run as glasshouse_run
import glasshouse/session
import glasshouse/sha256
import glasshouse/usage
import gleam/bit_array
import gleam/http/request.{type Request}
import gleam/http/response.{Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import midas/continuation
import oas/generator/utils
import ogre/operation
import ogre/origin
import overlay/agent
import overlay/export
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/policy
import overlay/web/artifact
import overlay/web/artifact/session as artifact_session
import overlay/web/context
import overlay/web/provider_setup
import overlay/web/puppet
import overlay/web/tools
import overlay/web/trace
import overlay/web/workspace
import pal/system
import plinth/browser/file
import touch_grass/download
import touch_grass/now
import untethered/ledger/client as ledger

pub type Config {
  Config(origin: origin.Origin, context: context.Source)
}

// The system prompt and tools are not part of the state as they are built from readme and always one tool
pub type State {
  State(
    llm: provider.Llm,
    provider_setup: provider_setup.State,
    context_source: context.Source,
    context: context.Status,
    status: AgentStatus,
    history: List(chat.Message(tool.Call)),
    runs: List(tools.Progress),
    workspace: Option(workspace.Workspace),
    input: String,
    input_error: Option(String),
    origin: origin.Origin,
    cache: cache.Cache(tools.Meta),
    counter: Int,
    expanded: set.Set(Int),
    artifacts: artifact.Store,
    artifact_storage: artifact_session.Status,
    artifacts_dirty: Bool,
    artifact_save_revision: Int,
    artifact_import_error: Option(String),
    /// Rounds of tool calls since the last prompt.
    steps: Int,
    /// The policy as written by the user, applied with `UserAppliedPolicy`.
    policy_source: String,
    policy: Option(policy.Policy(Nil, tools.Meta)),
    policy_error: Option(String),
    /// The session recorded so far, it can be downloaded and opened in the Glasshouse debugger.
    trace: trace.Trace,
    /// The completion request in flight and when it was sent.
    asked: Option(#(Request(BitArray), Int)),
    /// The body of the streaming response so far.
    streamed: BitArray,
  )
}

pub type AgentStatus {
  Waiting
  Asking(messages: List(chat.Message(tool.Call)))
  Streaming(
    reader: system.Reader,
    completion: chat.Completion(tool.Call),
    remaining: BitArray,
  )
  Executing(calls: tools.Calls)
}

pub fn new(config: Config) -> State {
  let Config(origin:, context:) = config
  let started = trace.now()
  let llm =
    provider.Llm(
      provider: provider.Ollama(ollama.Config(origin:, api_key: None)),
      model: "",
    )
  let cache = cache.ready()
  let #(status, cache) = context.load(context, cache)
  State(
    llm:,
    provider_setup: provider_setup.new(),
    context_source: context,
    context: status,
    status: Waiting,
    history: [],
    runs: [],
    workspace: None,
    input: "",
    input_error: None,
    origin: origin,
    cache:,
    counter: 0,
    expanded: set.new(),
    artifacts: artifact.new(),
    artifact_storage: artifact_session.Saved,
    artifacts_dirty: False,
    artifact_save_revision: 0,
    artifact_import_error: None,
    steps: 0,
    policy_source: "",
    policy: None,
    policy_error: None,
    trace: trace.new_session(started),
    asked: None,
    streamed: <<>>,
  )
}

pub fn init(config) {
  let state = new(config)
  let #(_, provider_effects) = provider_setup.init()
  let #(state, effects) = flush(state)
  let provider_effects =
    list.map(provider_effects, system.map(_, ProviderSetupMessage))
  #(
    state,
    list.flatten([provider_effects, effects, [load_history(), load_artifacts()]]),
  )
}

const artifacts_key = "overlay.artifacts"

fn load_artifacts() {
  use stored <- system.GetSessionStorageItem(artifacts_key)
  system.Done(ArtifactsLoaded(stored))
}

fn save_artifacts(store, revision) {
  use result <- system.SetSessionStorageItem(
    artifacts_key,
    artifact_session.encode(store),
  )
  system.Done(ArtifactsSaved(revision, result))
}

const history_key = "overlay.history"

fn load_history() {
  use stored <- system.GetSessionStorageItem(history_key)
  system.Done(HistoryLoaded(stored))
}

fn save_history(history) {
  let encoded = chat.history_to_json(history) |> json.to_string
  use _ <- system.SetSessionStorageItem(history_key, encoded)
  system.Done(Ignore)
}

pub type Effect(t) {
  Browser(system.Effect(Message))
  Done(t)
}

fn flush(state: State) {
  let State(cache:, ..) = state
  let #(cache, effects) = cache.flush(cache)
  let effects =
    list.map(effects, fn(effect) {
      {
        use message <- continuation.then(cache.compute(
          effect,
          state.origin,
          system.fetch,
          system.hash,
        ))
        continuation.return(CacheMessage(message))
      }(system.Done)
    })
  #(State(..state, cache:), effects)
}

pub type Message {
  ProviderSetupMessage(provider_setup.Message)
  UserUpdatedInput(String)
  UserSubmittedPrompt
  LlmStartedStreaming(reader: system.Reader)
  LlmStreamedCompletion(
    completions: List(chat.Completion(tool.Call)),
    remaining: BitArray,
    chunk: BitArray,
  )
  LlmStreamFinished(Result(Nil, String))
  /// The provider rejected the API token.
  LlmTokenRejected(reason: String)
  UserClickedExpand(Int)
  UserClickedShrink(Int)
  UserClickedDownloadTrace
  UserClosedArtifact(artifact.Item)
  UserShowedArtifact(artifact.Placement)
  ArtifactsLoaded(Result(Option(String), String))
  ArtifactsSaved(revision: Int, result: Result(Nil, String))
  UserRetriedArtifactSave
  UserExportedArtifacts
  UserSelectedArtifactFile(file.File)
  ArtifactFileRead(Result(String, String))
  UserClickedShare(artifact.Item)
  ArtifactShared(
    name: String,
    version: Int,
    result: Result(schema.SharedArtifact, String),
  )
  // run messages
  EffectHandled(task_id: Int, value: istate.Value(tools.Meta))
  CacheMessage(cache.ActionCompleted)
  UserClickedStop
  UserClickedNewChat
  UserClickedExport
  HistoryLoaded(Result(Option(String), String))
  UserUpdatedPolicy(String)
  UserAppliedPolicy
  Ignore
}

/// The most rounds of tool calls for one prompt, an agent that keeps failing is stopped.
pub const max_steps = 25

/// The history is saved for the tab whenever the agent finishes, so a reload keeps the conversation.
pub fn update(
  state: State,
  message: Message,
) -> #(State, List(system.Effect(Message))) {
  let #(next, effects) = do_update(state, message)
  let dirty = case message {
    ArtifactsLoaded(_) -> next.artifacts_dirty
    _ -> next.artifacts_dirty || next.artifacts != state.artifacts
  }
  let next = State(..next, artifacts_dirty: dirty)
  // Save a completed turn once, rather than serializing every tool result.
  // A returned share secret must survive a refresh even while the agent is busy.
  let persist = case next.status, message {
    Waiting, _ -> True
    _, ArtifactShared(..) -> True
    _, UserRetriedArtifactSave -> True
    _, _ -> False
  }
  let #(next, effects) = case persist, dirty {
    True, True -> {
      let revision = next.artifact_save_revision + 1
      #(
        State(
          ..next,
          artifacts_dirty: False,
          artifact_storage: artifact_session.Saving,
          artifact_save_revision: revision,
        ),
        [save_artifacts(next.artifacts, revision), ..effects],
      )
    }
    _, _ -> #(next, effects)
  }
  case next.status, next.history != state.history {
    Waiting, True -> #(next, [save_history(next.history), ..effects])
    _, _ -> #(next, effects)
  }
}

fn do_update(
  state: State,
  message: Message,
) -> #(State, List(system.Effect(Message))) {
  case message {
    UserExportedArtifacts -> {
      let content = artifact_session.export(state.artifacts)
      let action =
        system.Download(
          download.Input("eyg-artifacts.json", <<content:utf8>>),
          fn() { system.Done(Ignore) },
        )
      #(state, [action])
    }
    UserSelectedArtifactFile(file) ->
      case can_import_artifacts(state), file.size(file) <= 33_554_432 {
        False, _ -> #(
          State(
            ..state,
            artifact_import_error: Some(
              "Open an empty, idle tab to import artifacts",
            ),
          ),
          [],
        )
        True, False -> #(
          State(
            ..state,
            artifact_import_error: Some(
              "Choose a workspace file no larger than 32 MiB",
            ),
          ),
          [],
        )
        True, True -> {
          let action =
            system.ReadTextFile(file, fn(result) {
              system.Done(ArtifactFileRead(result))
            })
          #(State(..state, artifact_import_error: None), [action])
        }
      }
    ArtifactFileRead(result) -> {
      let restored = case can_import_artifacts(state) {
        False ->
          Error("Work has started in this tab. Import into a new, empty tab")
        True -> result.try(result, artifact_session.import_copy)
      }
      case restored {
        Ok(artifacts) -> #(
          State(..state, artifacts:, artifact_import_error: None),
          [],
        )
        Error(reason) -> #(
          State(..state, artifact_import_error: Some(reason)),
          [],
        )
      }
    }
    ArtifactsLoaded(stored) -> {
      // A late storage read must not replace work already created this session.
      case state.artifacts == artifact.new(), stored {
        False, _ -> #(state, [])
        True, Ok(Some(stored)) ->
          case artifact_session.restore(stored) {
            Ok(artifacts) -> #(State(..state, artifacts:), [])
            Error(reason) -> #(
              State(
                ..state,
                artifact_storage: artifact_session.RestoreFailed(reason),
              ),
              [],
            )
          }
        True, Error(reason) -> #(
          State(
            ..state,
            artifact_storage: artifact_session.RestoreFailed(reason),
          ),
          [],
        )
        True, Ok(None) -> #(state, [])
      }
    }
    ArtifactsSaved(revision, result) ->
      case revision == state.artifact_save_revision {
        False -> #(state, [])
        True -> {
          let status = case result {
            Ok(Nil) -> artifact_session.Saved
            Error(reason) -> artifact_session.SaveFailed(reason)
          }
          #(State(..state, artifact_storage: status), [])
        }
      }
    UserRetriedArtifactSave -> #(State(..state, artifacts_dirty: True), [])
    UserClosedArtifact(item) -> #(
      State(..state, artifacts: artifact.close(state.artifacts, item)),
      [],
    )
    UserShowedArtifact(placement) -> {
      case artifact.show(state.artifacts, placement) {
        Ok(artifacts) -> #(State(..state, artifacts:), [])
        Error(_) -> #(state, [])
      }
    }
    UserClickedShare(item) ->
      case artifact.version(state.artifacts, item) {
        Ok(#(name, version, bundle)) -> {
          let previous =
            artifact.previous_share(state.artifacts, name, version)
            |> option.from_result
          let share = artifact.Sharing
          let artifacts = artifact.share(state.artifacts, name, version, share)
          let action =
            share_artifact(state.origin, name, version, bundle, previous)
          #(State(..state, artifacts:), [action])
        }
        Error(Nil) -> #(state, [])
      }
    ArtifactShared(name:, version:, result:) -> {
      let share = case result {
        Ok(schema.SharedArtifact(id:, secret:)) -> artifact.Shared(id:, secret:)
        Error(reason) -> artifact.ShareFailed(reason)
      }
      let artifacts = artifact.share(state.artifacts, name, version, share)
      #(State(..state, artifacts:), [])
    }
    ProviderSetupMessage(message) -> {
      let can_save = case state.status {
        Waiting -> True
        _ -> False
      }
      let #(setup, actions, llm) =
        provider_setup.update(
          state.provider_setup,
          message,
          state.origin,
          can_save,
        )
      let state = State(..state, provider_setup: setup)
      let state = case llm {
        Some(llm) -> State(..state, llm:)
        None -> state
      }
      let actions = list.map(actions, system.map(_, ProviderSetupMessage))
      #(state, actions)
    }
    UserUpdatedInput(input) -> {
      let state = State(..state, input:)
      #(state, [])
    }
    UserSubmittedPrompt ->
      case
        state.provider_setup.configured,
        state.status,
        context.loading(state.context)
      {
        False, _, _ -> {
          let provider_setup =
            provider_setup.require_configuration(state.provider_setup)
          #(State(..state, provider_setup:), [])
        }
        // The readme is part of the system prompt, so a session cannot start
        // before the context it is for has arrived.
        True, Waiting, True -> {
          let state =
            State(..state, input_error: Some("Context is still loading"))
          #(state, [])
        }
        True, Waiting, False -> {
          case string.trim(state.input) {
            "" -> #(State(..state, input_error: Some("")), [])
            input -> {
              let at = trace.now()
              let recorded =
                state.trace
                |> trace.configure(
                  context.describe(state.context_source),
                  context.module(state.context).value,
                  at,
                )
                |> trace.prompt(at, input)
              let message = chat.UserMessage(text: input, images: [])
              let state = State(..state, trace: recorded)
              let #(state, action) = ask(state, [message])
              let state =
                State(..state, status: Asking([message]), input: "", steps: 0)
              #(state, [action])
            }
          }
        }
        True, _, _ -> {
          let state =
            State(..state, input_error: Some("Cant send another message"))
          #(state, [])
        }
      }
    LlmStartedStreaming(reader) -> {
      case state.status {
        Asking(messages) -> {
          let history = list.append(messages, state.history)

          let state =
            State(
              ..state,
              status: Streaming(reader, chat.fresh(), <<>>),
              history:,
              streamed: <<>>,
            )
          let action = stream_next_chunk(state.llm.provider, reader, <<>>)
          #(state, [action])
        }
        _ -> #(state, [])
      }
    }
    LlmStreamedCompletion(new, remaining, chunk) -> {
      case state.status {
        Streaming(reader:, completion:, remaining: _) -> {
          let completion = chat.append_chunks(completion, new)
          let state =
            State(
              ..state,
              status: Streaming(reader:, completion:, remaining:),
              streamed: <<state.streamed:bits, chunk:bits>>,
            )
          let action = stream_next_chunk(state.llm.provider, reader, remaining)
          #(state, [action])
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Ok(Nil)) -> {
      case state.status {
        Streaming(reader: _, completion:, remaining: _) -> {
          let message = chat.from_completion(completion)
          let history = [message, ..state.history]

          let state =
            State(..record_generation(state, Ok(completion)), history:)
          case completion.tool_calls {
            [] -> #(State(..state, status: Waiting), [])
            calls -> {
              current_context(state)
              |> tools.execute_all(calls)
              |> run_effects_if_any_remain_to_do(state)
            }
          }
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Error(reason)) -> {
      let state = record_generation(state, Error(reason))
      // A prompt that was never answered is returned to the input to try again.
      let input = case state.status, state.input {
        Asking([chat.UserMessage(text:, ..)]), "" -> text
        _, input -> input
      }
      let state =
        State(..state, status: Waiting, input:, input_error: Some(reason))
      #(state, [])
    }
    LlmTokenRejected(reason) -> {
      let provider_setup = provider_setup.token_rejected(state.provider_setup)
      update(State(..state, provider_setup:), LlmStreamFinished(Error(reason)))
    }
    UserClickedExpand(index) -> {
      let expanded = set.insert(state.expanded, index)
      #(State(..state, expanded:), [])
    }
    UserClickedShrink(index) -> {
      let expanded = set.delete(state.expanded, index)
      #(State(..state, expanded:), [])
    }
    EffectHandled(task_id:, value:) -> {
      case state.status {
        // executing is always a non empty list
        Executing(calls) -> {
          current_context(state)
          |> tools.effect_handled(calls, task_id, value)
          |> run_effects_if_any_remain_to_do(state)
        }
        _ -> #(state, [])
      }
    }
    CacheMessage(message) -> {
      let #(cache, _done) = cache.update(state.cache, message, fn(_) { [] })
      let previous = state.cache.cursor_status
      let was_pulling =
        previous == cache.Pulling || previous == cache.ReadyToPull
      let not_pulling =
        cache.cursor_status != cache.Pulling
        && cache.cursor_status != cache.ReadyToPull
      let stopped_pulling = was_pulling && not_pulling

      let #(context, cache) = case stopped_pulling {
        True -> context.pulled(state.context, cache)
        False -> #(state.context, cache)
      }
      let context = context.check_fetching(context, cache)

      let state = State(..state, cache:, context:)
      case state.status {
        Executing(calls) -> {
          let ctx = current_context(state)

          let #(ctx, calls) = case stopped_pulling {
            True -> list.map_fold(calls, ctx, tools.pulled)
            False -> #(ctx, calls)
          }
          list.map_fold(calls, ctx, tools.check_fetching)
          |> run_effects_if_any_remain_to_do(state)
        }
        _ -> flush(state)
      }
    }

    UserClickedStop -> #(stop(state, "Stopped."), [])
    UserClickedNewChat ->
      case state.status {
        Waiting -> #(
          State(
            ..state,
            history: [],
            runs: [],
            steps: 0,
            input_error: None,
            expanded: set.new(),
            trace: trace.new_session(trace.now()),
            asked: None,
            streamed: <<>>,
          ),
          [],
        )
        _ -> #(state, [])
      }
    HistoryLoaded(Ok(Some(stored))) ->
      case state.history, json.parse(stored, chat.history_decoder()) {
        [], Ok(history) -> #(State(..state, history:), [])
        _, _ -> #(state, [])
      }
    HistoryLoaded(_) -> #(state, [])
    UserClickedExport -> #(state, [export_history(state)])
    UserUpdatedPolicy(policy_source) -> #(State(..state, policy_source:), [])
    UserAppliedPolicy ->
      case
        load_workspace_policy(state.policy_source, state.cache, state.workspace)
      {
        Ok(policy) -> #(State(..state, policy:, policy_error: None), [])
        Error(reason) -> #(State(..state, policy_error: Some(reason)), [])
      }
    UserClickedDownloadTrace -> {
      let archive = trace.archive(state.trace, agent(state), trace.now())
      let input =
        download.Input(name: state.trace.id <> ".json", content: <<
          archive.to_string(archive):utf8,
        >>)
      #(state, [system.Download(input, fn() { system.Done(Ignore) })])
    }
    Ignore -> #(state, [])
  }
}

/// Stop the agent, responses that arrive later are ignored as the status is waiting.
/// Tool calls without results are given one, so the history is valid for the next request.
fn stop(state: State, reason: String) -> State {
  let state = record_generation(state, Error(reason))
  let history = case state.status {
    Waiting -> state.history
    Asking(messages) -> list.append(messages, state.history)
    Streaming(completion:, ..) -> [
      chat.from_completion(chat.Completion(..completion, tool_calls: [])),
      ..state.history
    ]
    Executing(calls) ->
      list.fold(calls, state.history, fn(history, progress: tools.Progress) {
        [
          chat.ToolResultMessage(progress.id, "stopped by the user", []),
          ..history
        ]
      })
  }
  State(..state, status: Waiting, history:, input_error: Some(reason))
}

pub fn can_save_provider(state: State) {
  case state.provider_setup.restoring, state.status {
    False, Waiting -> True
    _, _ -> False
  }
}

// cache state doesn't update during the eval but needs to resume later if everything fetched at the beginning

fn current_context(state: State) {
  let State(cache:, counter:, context:, trace:, ..) = state
  tools.Context(
    cache:,
    counter:,
    effects: [],
    context: context.module(context),
    artifacts: state.artifacts,
    workspace: state.workspace,
    policy: state.policy,
    trace:,
  )
}

/// If a stream message is completed, and effect is handled or a cache message received then resolve calls sees what stage tool calls are in.
/// 
fn run_effects_if_any_remain_to_do(return, state: State) {
  let #(ctx, calls) = return

  let tools.Context(
    cache:,
    counter:,
    effects: inner,
    context: _,
    trace:,
    artifacts:,
    workspace:,
    ..,
  ) = ctx
  let effects =
    list.map(
      inner,
      system.map(_, fn(return) {
        let #(id, value) = return
        EffectHandled(task_id: id, value:)
      }),
    )

  let state = State(..state, cache:, counter:, trace:, artifacts:, workspace:)
  let #(state, cache_effects) = flush(state)
  let effects = list.append(cache_effects, effects)

  // I think here we do the switch on pulling. 
  case tools.all_returns(calls) {
    Error(Nil) -> #(State(..state, status: Executing(calls)), effects)
    Ok(messages) -> {
      let state = record_tool_calls(state, calls, messages)
      let runs = list.fold(calls, state.runs, fn(runs, call) { [call, ..runs] })
      let state = State(..state, runs:)
      case state.steps >= max_steps {
        True -> {
          let reason =
            "Stopped after "
            <> int.to_string(max_steps)
            <> " rounds of tool calls, send a message to continue."
          #(stop(State(..state, status: Asking(messages)), reason), effects)
        }
        False -> {
          let state =
            State(..state, status: Asking(messages), steps: state.steps + 1)
          let #(state, action) = ask(state, messages)
          #(state, [action, ..effects])
        }
      }
    }
  }
}

/// Sharing moves one version of an artifact to the hub, the session keeps its copy.
/// Shared after an earlier version, it becomes the newer version of that share.
fn share_artifact(origin, name, version, bundle: artifact.Bundle, previous) {
  let files =
    list.map(bundle, fn(file) {
      schema.ArtifactFile(file.path, file.media_type, file.content)
    })
  let request =
    client.share_artifact(name, files, previous)
    |> operation.to_request(origin)
  use response <- system.Fetch(request)
  let result = case response {
    Ok(response) ->
      case client.share_artifact_response(response) {
        Ok(result) -> result
        Error(failure) -> Error(ledger.describe_failure(failure))
      }
    Error(_) -> Error("Unable to reach the hub")
  }
  system.Done(ArtifactShared(name:, version:, result:))
}

fn fetch_completion(request) {
  use response <- system.FetchStreamResponse(request)

  case response {
    Ok(Response(200, body:, ..)) -> system.Done(LlmStartedStreaming(body))
    Ok(Response(status:, body:, ..)) -> read_error(body, status, <<>>)
    Error(reason) ->
      system.Done(LlmStreamFinished(Error(string.inspect(reason))))
  }
}

/// Read the body of a failed response, it explains the failure.
fn read_error(reader, status, acc) {
  use chunk <- system.ReadChunk(reader)
  case chunk {
    Ok(Some(bits)) -> read_error(reader, status, <<acc:bits, bits:bits>>)
    _ ->
      case status {
        401 -> system.Done(LlmTokenRejected(http_error(status, acc)))
        _ -> system.Done(LlmStreamFinished(Error(http_error(status, acc))))
      }
  }
}

fn http_error(status, body) {
  let summary = case status {
    401 -> "Provider rejected the API token (401)."
    _ -> "Provider returned HTTP " <> int.to_string(status) <> "."
  }
  case bit_array.to_string(body) {
    Ok("") | Error(Nil) -> summary
    Ok(body) -> summary <> " " <> body
  }
}

fn stream_next_chunk(provider, reader, remaining) {
  use chunk <- system.ReadChunk(reader)
  case chunk {
    Ok(Some(chunk)) -> {
      let #(completions, remaining) =
        provider.completion_chunk_parse(provider, remaining, chunk)
      LlmStreamedCompletion(completions, remaining, chunk)
    }
    Ok(None) -> LlmStreamFinished(Ok(Nil))
    Error(reason) -> LlmStreamFinished(Error(string.inspect(reason)))
  }
  |> system.Done
}

fn system_prompt(state: State) {
  agent.system_prompt(
    state.origin,
    tools.session_effects(state.workspace),
    context.instructions(state.context_source, state.context)
      <> workspace_instructions(state.workspace)
      <> artifact.instructions
      <> puppet.instructions,
    option.is_some(state.policy),
  )
}

fn completion_request(state: State, messages: List(chat.Message(tool.Call))) {
  let context =
    provider.Context(system_prompt: system_prompt(state), tools: agent.tools())
  let history = list.append(messages, state.history) |> list.reverse
  provider.stream_completion_request(state.llm, context, history)
}

/// Parse, type check and evaluate a policy written by the user.
/// An empty policy removes the policy so every effect is performed.
pub fn load_policy(
  source: String,
  cache: cache.Cache(tools.Meta),
) -> Result(Option(policy.Policy(Nil, tools.Meta)), String) {
  load_workspace_policy(source, cache, None)
}

fn load_workspace_policy(source, cache, workspace) {
  case string.trim(source) {
    "" -> Ok(None)
    code -> {
      use source <- result.try(
        parser.all_from_string(code)
        |> result.map_error(fn(reason) { parser.format_error(reason, code) }),
      )
      let source = ir.map_annotation(source, fn(_) { [] })
      // Each gate must accept its browser effect's input and decide Pass or Mock.
      let analysis =
        infer.pure()
        |> infer.with_expected_type(
          policy.type_(tools.policy_rules_for(workspace)),
        )
        |> infer.check(source)
        |> cache.infer_sync(cache)
      use Nil <- result.try(case infer.all_errors(analysis) {
        [] -> Ok(Nil)
        errors ->
          list.map(errors, fn(error) { analysis_debug.reason(error.1) })
          |> string.join("\n")
          |> Error
      })
      use value <- result.try(
        expression.execute(source, [])
        |> cache.static_loop(cache, expression.resume)
        |> result.map_error(fn(debug) { simple_debug.describe(debug.0) }),
      )
      policy.decode_policy(tools.policy_rules_for(workspace), value)
      |> result.map(Some)
      |> result.map_error(simple_debug.describe)
    }
  }
}

/// Download the chat in the opencode session export format.
fn export_history(state: State) {
  let time = now.sync()
  let session =
    export.Session(
      id: "ses_" <> int.to_string(time),
      directory: "browser",
      provider_id: provider.id(state.llm.provider),
      model_id: state.llm.model,
      time:,
    )
  let content =
    export.encode(session, list.reverse(state.history)) |> json.to_string
  let input =
    download.Input(
      name: "overlay-session-" <> int.to_string(time) <> ".json",
      content: <<content:utf8>>,
    )
  use <- system.Download(input)
  system.Done(Ignore)
}

// Every call has finished, each is recorded as a run with the result the model reads.
fn record_tool_calls(state: State, calls: tools.Calls, messages) {
  let generation = "g" <> int.to_string(state.trace.generations)
  let recorded =
    list.zip(calls, messages)
    |> list.index_fold(state.trace, fn(recorded, pair, index) {
      let #(progress, message) = pair
      let result = chat.text(message)
      let #(recorded, outcome) = case progress.call {
        tools.Successful(value) -> trace.returned(recorded, value)
        // Programs that did not parse or type check never ran.
        tools.UnknownTool(..)
        | tools.BadArguments(..)
        | tools.InvalidCode(..)
        | tools.Errored(..) -> #(recorded, glasshouse_run.Rejected(result))
        _ -> #(recorded, glasshouse_run.Failed(result))
      }
      trace.tool_call(
        recorded,
        trace.call_id(generation, index),
        progress.code,
        progress.program,
        list.reverse(progress.journal),
        outcome,
        progress.started,
        trace.now(),
        result,
      )
    })
  State(..state, trace: recorded)
}

fn record_generation(state: State, result) {
  case state.asked {
    Some(#(request, started)) -> {
      let id = trace.next_generation(state.trace)
      let key =
        sha256.hash(<<request.path:utf8, "\n":utf8, request.body:bits>>)
        |> bit_array.base16_encode
        |> string.lowercase
      let #(recorded, request_cid) = trace.store_body(state.trace, request.body)
      let #(recorded, response, status) = case result, state.streamed {
        Error(_), <<>> -> #(recorded, None, 0)
        _, body -> {
          let #(recorded, cid) = trace.store_body(recorded, body)
          #(recorded, Some(cid), 200)
        }
      }
      let #(thinking, content, calls, error) = case result {
        Ok(chat.Completion(thinking:, content:, tool_calls:)) -> #(
          thinking,
          content,
          tool_calls,
          None,
        )
        Error(reason) -> #("", "", [], Some(reason))
      }
      let generation =
        session.Generation(
          id:,
          started:,
          ended: trace.now(),
          key:,
          request: request_cid,
          response:,
          status:,
          thinking:,
          content:,
          tool_calls: list.index_map(calls, fn(call, index) {
            let tool.Call(function: tool.FunctionCall(name:, arguments:), ..) =
              call
            session.ToolCall(
              id: trace.call_id(id, index),
              name:,
              arguments: json.to_string(utils.fields_to_json(arguments)),
            )
          }),
          usage: usage.from_response(state.streamed),
          source: session.Live,
          error:,
        )
      State(..state, trace: trace.generated(recorded, generation), asked: None)
    }
    None -> state
  }
}

/// The agent the session is recorded for.
pub fn agent(state: State) -> session.Agent {
  let provider = case state.llm.provider {
    provider.Ollama(_) -> "ollama"
    provider.Mistral(_) -> "mistral"
  }
  session.Agent(
    provider:,
    model: state.llm.model,
    system_prompt: system_prompt(state),
  )
}

/// Ask for a completion, the request is kept to record the generation.
fn ask(state: State, messages) -> #(State, system.Effect(Message)) {
  let request = completion_request(state, messages)
  #(
    State(..state, asked: Some(#(request, trace.now()))),
    fetch_completion(request),
  )
}

fn workspace_instructions(files) {
  case files {
    Some(_) ->
      "
This session has a workspace file system. Use file effects to read and change it. Paths are relative to its root and cannot leave it.
"
    None -> ""
  }
}

fn can_import_artifacts(state: State) -> Bool {
  case state.status {
    Waiting -> state.artifacts == artifact.new()
    _ -> False
  }
}
