//// A workspace routes the events of every connected platform.
////
//// Each conversation has a session with an agent.
//// A plugin's native input goes to the channel's checked handler. Its work requests
//// choose sessions, observations, invocations and policy-controlled posts.
////
//// The workspace holds no EYG values, configuration is evaluated by the processes
//// that run programs, see `notes/cloud-process-boundaries.md`.

import cloud/agent
import cloud/beam/execute
import cloud/channel.{type Conversation}
import cloud/config
import cloud/data
import cloud/files
import cloud/handler
import cloud/invocation
import cloud/session
import cloud/shell
import cloud/work
import eyg/interpreter/simple_debug
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type Message {
  /// A platform plugin has started, outbound operations for the platform are now available.
  Connect(platform: String, outbound: channel.Outbound)
  Inbound(channel.Event)
  /// A file in the workspace's file system changed.
  FileChanged(files.Change)
}

type State {
  State(
    load: config.Loader,
    platforms: Dict(String, channel.Outbound),
    sessions: Dict(String, Subject(session.Message)),
    files: Subject(files.Message),
    complete: agent.Completer,
  )
}

pub fn start(load: config.Loader) -> Result(Subject(Message), String) {
  start_with(load, agent.complete)
}

pub fn start_with(
  load: config.Loader,
  complete: agent.Completer,
) -> Result(Subject(Message), String) {
  // Only the seed directory, a string, leaves this process.
  use seed <- result.try(load() |> result.map(fn(config) { config.files }))
  use files <- result.try(files.start(seed))
  actor.new_with_initialiser(1000, fn(self) {
    let changes = process.new_subject()
    process.send(files, files.Subscribe(changes))
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_map(changes, FileChanged)
    State(load:, platforms: dict.new(), sessions: dict.new(), files:, complete:)
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Connect(platform:, outbound:) ->
      State(
        ..state,
        platforms: dict.insert(state.platforms, platform, outbound),
      )
    Inbound(event) -> inbound(state, event)
    FileChanged(change) -> {
      dict.each(state.sessions, fn(_key, session) {
        process.send(session, session.Changed(change))
      })
      state
    }
  }
  |> actor.continue
}

fn inbound(state: State, event: channel.Event) -> State {
  let channel.Incoming(conversation, value) = event
  case dict.get(state.platforms, conversation.platform) {
    Error(Nil) -> {
      io.println_error(channel.key(conversation) <> ": not connected")
      state
    }
    Ok(outbound) -> {
      let info = channel_info(outbound, conversation)
      let requests = {
        use workspace <- result.try(state.load())
        use configured <- result.try(config.channel(workspace, info))
        handler.run(configured.handle, value, workspace.state)
      }
      case requests {
        Error(reason) -> {
          io.println_error("#" <> info.name <> " handle: " <> reason)
          state
        }
        Ok(requests) -> {
          list.fold(requests, state, fn(state, request) {
            perform_work(state, request, event, outbound, info)
          })
        }
      }
    }
  }
}

fn perform_work(
  state: State,
  request: work.Work,
  event: channel.Event,
  outbound,
  info,
) -> State {
  let channel.Incoming(origin, _) = event
  case request {
    work.Submit(session, reply, text, description) -> {
      let requests = case string.trim(text), invocation.parse(text) {
        "/new", _ -> [
          work.Reset(session),
          work.Post(
            session,
            "Started a new conversation, earlier messages are forgotten.",
          ),
        ]
        _, Ok(code) -> [work.Run(session, reply, code, description)]
        _, Error(Nil) -> [work.Input(session, description)]
      }
      list.fold(requests, state, fn(state, request) {
        perform_work(state, request, event, outbound, info)
      })
    }
    work.Post(thread, text) -> {
      let conversation = channel.Conversation(..origin, thread:)
      let host = host(state, outbound, conversation, info)
      case
        shell.prepare(
          state.load,
          info,
          host,
          location(info, conversation),
          state.complete,
        )
      {
        Ok(shell) -> {
          let _ =
            shell.run(shell, "perform Post(text)", [
              #("text", data.string(text)),
            ])
          Nil
        }
        Error(reason) ->
          io.println_error("#" <> info.name <> " post: " <> reason)
      }
      state
    }
    work.Input(thread, text) -> {
      let #(session, state) =
        session_for(
          state,
          channel.Conversation(..origin, thread:),
          outbound,
          info,
        )
      process.send(session, session.Input(text))
      state
    }
    work.Observe(thread, text) -> {
      let #(session, state) =
        session_for(
          state,
          channel.Conversation(..origin, thread:),
          outbound,
          info,
        )
      process.send(session, session.Observe(text))
      state
    }
    work.Reset(thread) -> {
      let #(session, state) =
        session_for(
          state,
          channel.Conversation(..origin, thread:),
          outbound,
          info,
        )
      process.send(session, session.Reset)
      state
    }
    work.Run(thread, reply, code, description) -> {
      let conversation = channel.Conversation(..origin, thread:)
      let #(session, state) = session_for(state, conversation, outbound, info)
      let reply = channel.Conversation(..origin, thread: reply)
      let host = host(state, outbound, reply, info)
      let #(load, complete) = #(state.load, state.complete)
      // Only plain data and host operations cross this boundary, never the handler closure.
      process.spawn(fn() {
        let observed = case
          shell.prepare(load, info, host, location(info, reply), complete)
        {
          Ok(shell) -> invoke(shell, code, description)
          Error(reason) -> description <> "\nError: " <> reason
        }
        process.send(session, session.Observe(observed))
      })
      state
    }
  }
}

fn channel_info(outbound: channel.Outbound, conversation: Conversation) {
  let channel.Conversation(platform:, channel: id, ..) = conversation
  config.ChannelInfo(
    platform:,
    id:,
    name: outbound.channel_name(id),
    input_type: outbound.input_type,
  )
}

fn session_for(
  state: State,
  conversation: Conversation,
  outbound: channel.Outbound,
  info: config.ChannelInfo,
) -> #(Subject(session.Message), State) {
  let key = channel.key(conversation)
  case dict.get(state.sessions, key) {
    Ok(session) -> #(session, state)
    Error(Nil) -> {
      let setup =
        session.Setup(
          name: key,
          channel: info,
          location: location(info, conversation),
          load: state.load,
          complete: state.complete,
          host: host(state, outbound, conversation, info),
        )
      let assert Ok(session) = session.start(setup)
      let sessions = dict.insert(state.sessions, key, session)
      #(session, State(..state, sessions:))
    }
  }
}

fn location(info: config.ChannelInfo, conversation) {
  "You are in the channel #" <> info.name <> option_thread(conversation) <> "."
}

fn option_thread(conversation: Conversation) {
  case conversation.thread {
    Some(thread) -> ", in the thread started by message " <> thread
    None -> ""
  }
}

/// The host for programs run from a conversation, file changes are made as the channel.
fn host(state: State, outbound: channel.Outbound, conversation, info) {
  let config.ChannelInfo(name:, ..) = info
  execute.channel_host(
    outbound.post(conversation, _),
    execute.files(state.files, "#" <> name),
  )
}

/// Run a direct invocation, post its output and return a description for the agent.
fn invoke(shell: shell.Shell, code, description: String) -> String {
  let execute.Run(result:, output:) = shell.run(shell, code, [])
  let printed = list.reverse(output) |> list.map(execute.output_text)
  let returned = case result {
    Ok(value) -> value |> option.map(simple_debug.inspect) |> option.unwrap("")
    Error(reason) -> "Error: " <> reason
  }
  [printed, [returned]]
  |> list.flatten
  |> list.filter(fn(text) { string.trim(text) != "" })
  |> list.each(fn(text) { shell.host.post(text) })
  let output = case string.concat(printed) {
    "" -> ""
    printed -> "\nIt printed:\n" <> printed
  }
  description <> output <> "\nIt returned: " <> returned
}
