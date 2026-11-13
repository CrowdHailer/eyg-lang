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
import cloud/trigger.{type Trigger}
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
  AddTrigger(
    channel: config.ChannelInfo,
    trigger: Trigger,
    reply: Subject(Result(Nil, String)),
  )
  UpdateTrigger(
    channel: config.ChannelInfo,
    name: String,
    update: execute.TriggerUpdate,
    reply: Subject(Result(Nil, String)),
  )
  ListTriggers(channel: config.ChannelInfo, reply: Subject(List(Trigger)))
}

type State {
  State(
    self: Subject(Message),
    load: config.Loader,
    platforms: Dict(String, channel.Outbound),
    sessions: Dict(String, Subject(session.Message)),
    files: Subject(files.Message),
    /// Triggers per channel, keyed by `platform:channel`.
    /// A channel's configured triggers are installed when its first event arrives.
    triggers: Dict(String, List(Trigger)),
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
    State(
      self:,
      load:,
      platforms: dict.new(),
      sessions: dict.new(),
      files:,
      triggers: dict.new(),
      complete:,
    )
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
    AddTrigger(channel: info, trigger:, reply:) -> {
      // Configured triggers are installed first, so they are not lost.
      let state = install(state, info)
      let channel = trigger_key(info)
      let triggers = channel_triggers(state, channel)
      case list.any(triggers, fn(t) { t.name == trigger.name }) {
        True -> {
          process.send(
            reply,
            Error("a trigger named " <> trigger.name <> " exists"),
          )
          state
        }
        False -> {
          process.send(reply, Ok(Nil))
          set_triggers(state, channel, list.append(triggers, [trigger]))
        }
      }
    }
    UpdateTrigger(channel: info, name:, update:, reply:) -> {
      let state = install(state, info)
      let channel = trigger_key(info)
      let triggers = channel_triggers(state, channel)
      case list.any(triggers, fn(t) { t.name == name }) {
        False -> {
          process.send(reply, Error("no trigger named " <> name))
          state
        }
        True -> {
          process.send(reply, Ok(Nil))
          let triggers = case update {
            execute.Delete -> list.filter(triggers, fn(t) { t.name != name })
            execute.Stop -> set_active(triggers, name, False)
            execute.Start -> set_active(triggers, name, True)
          }
          set_triggers(state, channel, triggers)
        }
      }
    }
    ListTriggers(channel: info, reply:) -> {
      let state = install(state, info)
      process.send(reply, channel_triggers(state, trigger_key(info)))
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
          let state = install(state, info)
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
  let channel.Incoming(origin, value) = event
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
    work.Trigger(thread) -> {
      let conversation = channel.Conversation(..origin, thread:)
      run_triggers(state, value, conversation, outbound, info)
      state
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

fn trigger_key(info: config.ChannelInfo) {
  info.platform <> ":" <> info.id
}

/// Install a channel's configured triggers the first time the channel is seen.
fn install(state: State, info: config.ChannelInfo) -> State {
  let key = trigger_key(info)
  case dict.has_key(state.triggers, key) {
    True -> state
    False -> {
      let configured = {
        use workspace <- result.try(state.load())
        use channel <- result.map(config.channel(workspace, info))
        channel.triggers
      }
      case configured {
        Ok(triggers) -> set_triggers(state, key, triggers)
        Error(reason) -> {
          io.println_error("#" <> info.name <> " configuration: " <> reason)
          state
        }
      }
    }
  }
}

fn channel_triggers(state: State, key) {
  dict.get(state.triggers, key) |> result.unwrap([])
}

fn set_triggers(state: State, key, triggers) {
  State(..state, triggers: dict.insert(state.triggers, key, triggers))
}

fn set_active(triggers: List(Trigger), name, active) {
  list.map(triggers, fn(t) {
    case t.name == name {
      True -> trigger.Trigger(..t, active:)
      False -> t
    }
  })
}

/// Run the script of each active trigger whose pattern matches the event, in the event message's thread.
/// Each trigger is matched and run in its own process.
fn run_triggers(state: State, event, conversation, outbound, info) -> Nil {
  channel_triggers(state, trigger_key(info))
  |> list.filter(fn(t) { t.active })
  |> list.each(fn(t) {
    let host = host(state, outbound, conversation, info)
    let #(load, complete) = #(state.load, state.complete)
    process.spawn(fn() {
      let location =
        location(info, conversation)
        <> "\nYou were started by the trigger "
        <> t.name
        <> "."
      let outcome = {
        use shell <- result.try(shell.prepare(
          load,
          info,
          host,
          location,
          complete,
        ))
        use matched <- result.try(
          shell.matches(shell, t.pattern, event)
          |> result.map_error(fn(reason) { "pattern: " <> reason }),
        )
        case matched {
          True -> {
            let execute.Run(result:, ..) =
              shell.run_script(shell, t.script, event)
            result.replace(result, True)
          }
          False -> Ok(False)
        }
      }
      case outcome {
        Ok(True) -> io.println("trigger " <> t.name <> " ran in #" <> info.name)
        Ok(False) -> Nil
        Error(reason) ->
          io.println_error("trigger " <> t.name <> " failed: " <> reason)
      }
    })
  })
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

/// The host for programs run from a conversation.
/// File changes are made as the channel and triggers are added to the channel.
fn host(state: State, outbound: channel.Outbound, conversation, info) {
  let config.ChannelInfo(name:, ..) = info
  let self = state.self
  let triggers =
    execute.Triggers(
      add: fn(t) { process.call(self, 5000, AddTrigger(info, t, _)) },
      update: fn(name, update) {
        process.call(self, 5000, UpdateTrigger(info, name, update, _))
      },
      list: fn() { process.call(self, 5000, ListTriggers(info, _)) },
    )
  execute.channel_host(
    outbound.post(conversation, _),
    execute.files(state.files, "#" <> name),
    triggers,
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
