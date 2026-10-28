//// Run an Overlay session under eval.
////
//// The session is the real Overlay state machine, the one the browser runs.
//// Overlay returns every input and output as a `pal/system` effect value, the
//// runner performs each one against the environment instead of a browser,
//// and asks the model for completions. Nothing else changes, so an eval
//// measures the agent people use.

import gleam/crypto
import gleam/fetch
import gleam/http/request.{type Request}
import gleam/http/response.{Response}
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import javascript/mutable_reference
import midas/effect as midas
import overlay/eval/agent
import overlay/eval/environment.{type Environment}
import overlay/eval/fixture/hub
import overlay/eval/model
import overlay/eval/module
import overlay/eval/transcript.{type Transcript, Transcript}
import overlay/llm/provider
import overlay/web/context
import overlay/web/state
import overlay/web/workspace
import pal/system

pub type Config {
  Config(
    environment: Environment,
    context: Context,
    model: model.Model,
    // Files of the workspace, sessions without one cannot use file effects.
    workspace: Option(List(#(String, BitArray))),
    // Each prompt is sent once the agent has finished with the one before.
    prompts: List(String),
    max_model_calls: Int,
  )
}

pub type Context {
  // Overlay's default context.
  NoContext
  // A module, served by the environment's hub and loaded by reference.
  Module(module.Loaded)
}

type Session {
  Session(
    state: state.State,
    environment: Environment,
    model: model.Model,
    effects: List(transcript.Effect),
    model_calls: Int,
    max_model_calls: Int,
    stop: Option(transcript.Stop),
  )
}

/// Run every prompt of a session and return its transcript.
pub fn run(config: Config) -> Promise(Transcript) {
  let Config(
    environment:,
    context:,
    model:,
    workspace:,
    prompts:,
    max_model_calls:,
  ) = config
  let #(environment, source) = case context {
    NoContext -> #(environment, context.Default)
    Module(loaded) -> #(
      environment.Environment(
        ..environment,
        hub: hub.add(environment.hub, loaded),
      ),
      context.Reference(loaded.cid),
    )
  }
  let #(initial, effects) =
    state.init(state.Config(origin: environment.origin, context: source))
  let session =
    Session(
      state: initial,
      environment:,
      model:,
      effects: [],
      model_calls: 0,
      max_model_calls:,
      stop: None,
    )
  // Settings load from session storage, the session answers with the model's.
  use session <- promise.await(drain(session, effects))
  let session = configure(session, workspace)
  let session = case session.state.context {
    context.Errored(reason:) -> stop(session, transcript.ContextFailed(reason))
    _ -> session
  }
  use session <- promise.await(prompt_all(session, prompts))
  let state.State(history:, runs:, workspace:, ..) = session.state
  Transcript(
    turns: transcript.turns(history, runs),
    effects: list.reverse(session.effects),
    workspace: option.map(workspace, workspace.files),
    model_calls: session.model_calls,
    stop: option.unwrap(session.stop, transcript.Finished),
  )
  |> promise.resolve
}

fn configure(session: Session, files) {
  let state = session.state
  let state = case session.model {
    model.Provider(llm:, ..) -> state.State(..state, llm:)
    model.Scripted(_) -> state
  }
  let workspace = option.map(files, workspace.from_files)
  Session(..session, state: state.State(..state, workspace:))
}

fn prompt_all(session: Session, prompts) {
  case session.stop, prompts {
    Some(_), _ | None, [] -> promise.resolve(session)
    None, [prompt, ..rest] -> {
      let #(state, _) =
        state.update(session.state, state.UserUpdatedInput(prompt))
      let #(state, effects) = state.update(state, state.UserSubmittedPrompt)
      let session = Session(..session, state:)
      use session <- promise.await(drain(session, effects))
      let session = case session.stop, session.state {
        Some(_), _ -> session
        None, state.State(input_error: Some(reason), ..) ->
          stop(session, transcript.ModelFailed(reason))
        None, state.State(status: state.Waiting, ..) -> session
        None, _ -> stop(session, transcript.Stuck)
      }
      prompt_all(session, rest)
    }
  }
}

fn stop(session, reason) {
  Session(..session, stop: Some(reason))
}

/// Perform effects in order until none are left.
fn drain(
  session: Session,
  queue: List(system.Effect(state.Message)),
) -> Promise(Session) {
  case session.stop, queue {
    Some(_), _ | None, [] -> promise.resolve(session)
    None, [effect, ..rest] -> {
      let logged = list.length(session.effects)
      use #(session, message) <- promise.await(perform(session, effect))
      case message {
        None -> drain(session, rest)
        Some(message) -> {
          let session = attribute(session, logged, message)
          let #(state, effects) = state.update(session.state, message)
          drain(Session(..session, state:), list.append(rest, effects))
        }
      }
    }
  }
}

fn perform(
  session: Session,
  effect: system.Effect(state.Message),
) -> Promise(#(Session, Option(state.Message))) {
  case effect {
    system.Done(message) -> promise.resolve(#(session, Some(message)))
    system.Fetch(request:, resume:) -> {
      use #(session, result) <- promise.await(fetch(session, request))
      perform(session, resume(result))
    }
    system.FetchStreamResponse(request:, resume:) ->
      case session.model_calls >= session.max_model_calls {
        True -> {
          let limit = session.max_model_calls
          promise.resolve(#(
            stop(session, transcript.ModelCallLimit(limit)),
            None,
          ))
        }
        False -> {
          let session = Session(..session, model_calls: session.model_calls + 1)
          use result <- promise.await(complete(session.model, request))
          perform(session, resume(result))
        }
      }
    system.ReadChunk(reader:, resume:) -> {
      use chunk <- promise.await(reader())
      perform(session, resume(chunk))
    }
    system.Hash(algorithm:, bytes:, resume:) ->
      perform(session, resume(hash(algorithm, bytes)))
    system.GetSessionStorageItem(key:, resume:) ->
      perform(session, resume(Ok(setting(session.model, key))))
    system.SetSessionStorageItem(resume:, ..) ->
      perform(session, resume(Ok(Nil)))
    system.GetLocalStorageItem(resume:, ..) ->
      perform(session, resume(Ok(None)))
    system.SetLocalStorageItem(resume:, ..) -> perform(session, resume(Ok(Nil)))
    system.Wait(resume:, ..) -> perform(session, resume())
    system.Alert(message:, resume:) ->
      perform(log(session, transcript.Alert(message)), resume())
    system.Prompt(question:, resume:) ->
      // There is no person to answer.
      perform(log(session, transcript.Prompt(question)), resume(Error(Nil)))
    system.Visit(uri:, resume:) ->
      perform(
        log(session, transcript.Visit(uri.to_string(uri))),
        resume(Error("there is no browser window in an eval")),
      )
    system.OpenPopup(location:, resume:) ->
      perform(
        log(session, transcript.Visit(location)),
        resume(Error("there is no browser window in an eval")),
      )
    system.Download(input:, resume:) ->
      perform(log(session, transcript.Download(input.name)), resume())
    system.WriteToClipboard(text:, resume:) ->
      perform(log(session, transcript.Copy(text)), resume(Ok(Nil)))
    system.ReadFromClipboard(resume:) ->
      perform(session, resume(Error("the clipboard is empty in an eval")))
    system.ReadTextFile(resume:, ..) ->
      perform(
        session,
        resume(Error("there is no browser file picker in an eval")),
      )
    system.RequestFrame(resume:, ..) ->
      perform(session, resume(Error("there is no artifact preview in an eval")))
    system.PostMessage(resume:, ..) -> perform(session, resume(Nil))
    system.SaveFile(resume:, ..) ->
      perform(
        session,
        resume(Error("saving files is not available in an eval")),
      )
    system.ShowDirectoryPicker(resume:) ->
      perform(session, resume(Error("there is no directory picker in an eval")))
    system.Spotless(service:, resume:, ..) ->
      perform(
        log(session, transcript.Service(string.inspect(service))),
        resume(Error("services are not available in an eval")),
      )
  }
}

/// Fetches made while loading modules end with a cache message.
fn attribute(session: Session, logged, message) {
  case message {
    state.CacheMessage(_) -> {
      let new = list.length(session.effects) - logged
      let #(recent, older) = list.split(session.effects, new)
      let recent =
        list.map(recent, fn(effect) {
          case effect {
            transcript.Fetch(..) ->
              transcript.Fetch(..effect, by: transcript.ModuleCache)
            _ -> effect
          }
        })
      Session(..session, effects: list.append(recent, older))
    }
    _ -> session
  }
}

fn log(session: Session, effect) {
  Session(..session, effects: [effect, ..session.effects])
}

fn fetch(session: Session, request: Request(BitArray)) {
  let url = request.to_uri(request) |> uri.to_string
  case environment.answer(session.environment, request) {
    environment.Answered(response) -> {
      let effect =
        transcript.Fetch(
          transcript.Program,
          request.method,
          url,
          Ok(response.status),
        )
      promise.resolve(#(log(session, effect), Ok(response)))
    }
    environment.Refused(reason) -> {
      let effect =
        transcript.Fetch(transcript.Program, request.method, url, Error(reason))
      promise.resolve(#(log(session, effect), Error(midas.NetworkError(reason))))
    }
    environment.Unanswered -> {
      use result <- promise.map(send(request))
      let status = case result {
        Ok(response) -> Ok(response.status)
        Error(midas.NetworkError(reason)) -> Error(reason)
        Error(reason) -> Error(string.inspect(reason))
      }
      let effect =
        transcript.Fetch(transcript.Program, request.method, url, status)
      #(log(session, effect), result)
    }
  }
}

fn send(request) {
  use result <- promise.map(
    fetch.send_bits(request)
    |> promise.try_await(fetch.read_bytes_body),
  )
  result.map_error(result, fn(reason) {
    case reason {
      fetch.NetworkError(detail) -> midas.NetworkError(detail)
      _ -> midas.UnableToReadBody
    }
  })
}

fn complete(model, request: Request(BitArray)) {
  case model {
    model.Scripted(agent) ->
      case agent.conversation(request.body) {
        Ok(conversation) -> {
          let chunks = agent.stream(agent(conversation))
          promise.resolve(Ok(Response(200, [], reader(chunks))))
        }
        Error(reason) ->
          promise.resolve(
            Error(fetch.NetworkError(
              "scripted agents read the Ollama format: "
              <> string.inspect(reason),
            )),
          )
      }
    model.Provider(transport:, ..) -> transport(request)
  }
}

/// A reader that yields each chunk in turn.
pub fn reader(chunks: List(BitArray)) -> system.Reader {
  let remaining = mutable_reference.new(chunks)
  fn() {
    case mutable_reference.get(remaining) {
      [chunk, ..rest] -> {
        mutable_reference.set(remaining, rest)
        Ok(Some(chunk))
      }
      [] -> Ok(None)
    }
    |> promise.resolve
  }
}

fn hash(algorithm, bytes) {
  let algorithm = case algorithm {
    midas.Sha1 -> crypto.Sha1
    midas.Sha256 -> crypto.Sha256
    midas.Sha384 -> crypto.Sha384
    midas.Sha512 -> crypto.Sha512
  }
  crypto.hash(algorithm, bytes)
}

/// The settings a person would have saved for this model.
fn setting(model, key) {
  let #(provider, name, api_key) = case model {
    model.Scripted(_) -> #("ollama", "scripted", "scripted")
    model.Provider(
      llm: provider.Llm(provider: provider.Ollama(config), model:),
      ..,
    ) -> #("ollama", model, option.unwrap(config.api_key, "none"))
    model.Provider(
      llm: provider.Llm(provider: provider.Mistral(config), model:),
      ..,
    ) -> #("mistral", model, config.api_key)
    // The browser setup supports these two providers; configure installs the
    // supplied LLM directly after startup for other provider transports.
    model.Provider(llm: provider.Llm(model:, ..), ..) -> #(
      "ollama",
      model,
      "external",
    )
  }
  case key {
    "overlay.llm.provider" -> Some(provider)
    "overlay.llm.model" -> Some(name)
    "overlay.llm.api_key" -> Some(api_key)
    _ -> None
  }
}
