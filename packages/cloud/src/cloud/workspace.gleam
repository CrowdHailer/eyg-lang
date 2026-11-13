//// A workspace routes the events of every connected platform.
////
//// Each conversation has a session with an agent.
//// A plugin's native input goes to the channel's checked handler. Its work requests
//// choose sessions, observations, invocations and policy-controlled posts.
////
//// Connections that are not chats, such as GitHub or RSS, report events that are logged
//// and given to the triggers of the channel the connection names, see `cloud/connection`.
////
//// The workspace holds no EYG closures, configuration is evaluated by the processes
//// that run programs and events are plain data, see `notes/cloud-process-boundaries.md`.

import cloud/agent
import cloud/artifacts
import cloud/beam/execute
import cloud/channel.{type Conversation}
import cloud/config
import cloud/connection
import cloud/connections/bsky
import cloud/connections/github
import cloud/connections/hacker_news
import cloud/connections/lobsters
import cloud/connections/rss
import cloud/cron
import cloud/data
import cloud/files
import cloud/handler
import cloud/invocation
import cloud/plugins/discord
import cloud/plugins/example_chat
import cloud/plugins/slack
import cloud/session
import cloud/shell
import cloud/trigger.{type Trigger}
import cloud/work
import eyg/interpreter/simple_debug
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/time/timestamp

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
  /// Check cron schedules, sent every second.
  Tick
  AddSchedule(
    session: String,
    name: String,
    timing: Timing,
    message: String,
    reply: Subject(Result(Nil, String)),
  )
  CancelSchedule(
    session: String,
    name: String,
    reply: Subject(Result(Nil, String)),
  )
  /// A timeout has elapsed.
  Fire(session: String, name: String)
  /// A connection that is not a chat reported an event.
  Observed(connection.Event)
  ReadEvents(
    connection: String,
    reply: Subject(Result(List(data.Value), String)),
  )
  /// A webhook delivery for a connection.
  Webhook(delivery: github.Delivery, reply: Subject(Result(Nil, String)))
}

/// The most events kept per connection.
const max_log = 500

pub type Timing {
  Repeating(cron.Schedule)
  /// Send once after the milliseconds.
  Once(Int)
}

/// Who a scheduled message is sent to.
type Target {
  /// The session with this key.
  Session(String)
  /// The session of the channel with this name, if it has one.
  ChannelNamed(String)
}

type Scheduled {
  Scheduled(target: Target, timing: Timing, message: String)
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
    /// Scheduled messages, keyed by the session that scheduled them and a name.
    schedules: Dict(#(String, String), Scheduled),
    /// The session key of each channel's top level conversation, by channel name.
    channels: Dict(String, String),
    artifacts: Subject(artifacts.Message),
    complete: agent.Completer,
    connections: List(connection.Connection),
    /// The latest events of each connection, newest first.
    log: Dict(String, List(connection.Event)),
  )
}

pub fn start(
  load: config.Loader,
  artifacts: Subject(artifacts.Message),
) -> Result(Subject(Message), String) {
  start_with(load, artifacts, agent.complete)
}

pub fn start_with(
  load: config.Loader,
  artifacts: Subject(artifacts.Message),
  complete: agent.Completer,
) -> Result(Subject(Message), String) {
  // Only Gleam data, not EYG values, leaves this process.
  use #(seed, crons, connections) <- result.try(
    load()
    |> result.map(fn(config) {
      #(config.files, config.crons, config.connections)
    }),
  )
  use schedules <- result.try(
    list.try_map(crons, fn(c) {
      use schedule <- result.map(cron.parse(c.schedule))
      let scheduled =
        Scheduled(ChannelNamed(c.channel), Repeating(schedule), c.message)
      #(#("workspace", c.name), scheduled)
    }),
  )
  use files <- result.try(files.start(seed))
  actor.new_with_initialiser(1000, fn(self) {
    let changes = process.new_subject()
    process.send(files, files.Subscribe(changes))
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_map(changes, FileChanged)
    process.send_after(self, until_next_second(), Tick)
    State(
      self:,
      load:,
      platforms: dict.new(),
      sessions: dict.new(),
      files:,
      triggers: dict.new(),
      schedules: dict.from_list(schedules),
      channels: dict.new(),
      artifacts:,
      complete:,
      connections:,
      log: dict.new(),
    )
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) {
    list.each(connections, start_connection(started.data, _))
    started.data
  })
  |> result.map_error(string.inspect)
}

/// Start a connection in its own process, its events are sent to the workspace.
fn start_connection(
  workspace: Subject(Message),
  connection: connection.Connection,
) -> Nil {
  let connection.Connection(name:, source:, ..) = connection
  let observe = fn(event) { process.send(workspace, Observed(event)) }
  let inbound = fn(event) { process.send(workspace, Inbound(event)) }
  process.spawn(fn() {
    let started = case source {
      connection.ExampleChat(origin) -> {
        let config = example_chat.Config(origin:, poll_interval: 500)
        use outbound <- result.map(example_chat.start(config, inbound))
        process.send(workspace, Connect(example_chat.platform, outbound))
      }
      connection.Slack(token) -> {
        use outbound <- result.map(slack.start(token, inbound))
        process.send(workspace, Connect(slack.platform, outbound))
      }
      connection.Discord(token:, guild:) -> {
        use outbound <- result.map(discord.start(token, guild, inbound))
        process.send(workspace, Connect(discord.platform, outbound))
      }
      connection.GitHub(repositories:, every:, ..) ->
        Ok(github.start(name, repositories, every, observe))
      connection.Bsky(actors:, feeds:, every:) ->
        Ok(bsky.start(name, actors, feeds, every, observe))
      connection.Rss(feeds:, every:) ->
        Ok(rss.start(name, feeds, every, observe))
      connection.HackerNews(lists:, every:) ->
        Ok(hacker_news.start(name, lists, every, observe))
      connection.Lobsters(lists:, every:) ->
        Ok(lobsters.start(name, lists, every, observe))
    }
    case started {
      Ok(Nil) ->
        io.println(
          "Connected " <> name <> " (" <> connection.kind(source) <> ")",
        )
      Error(reason) -> io.println_error(name <> ": " <> reason)
    }
  })
  Nil
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
    Tick -> {
      process.send_after(state.self, until_next_second(), Tick)
      let now = timestamp.system_time()
      dict.each(state.schedules, fn(key, scheduled) {
        case scheduled.timing {
          Repeating(schedule) ->
            case cron.matches(schedule, now) {
              True -> deliver(state, key.1, scheduled)
              False -> Nil
            }
          Once(_) -> Nil
        }
      })
      state
    }
    AddSchedule(session:, name:, timing:, message:, reply:) -> {
      process.send(reply, Ok(Nil))
      case timing {
        Once(after) ->
          process.send_after(state.self, int.max(after, 0), Fire(session, name))
        Repeating(_) -> process.send_after(state.self, 0, Tick)
      }
      let scheduled = Scheduled(Session(session), timing, message)
      State(
        ..state,
        schedules: dict.insert(state.schedules, #(session, name), scheduled),
      )
    }
    CancelSchedule(session:, name:, reply:) ->
      case dict.has_key(state.schedules, #(session, name)) {
        True -> {
          process.send(reply, Ok(Nil))
          State(
            ..state,
            schedules: dict.delete(state.schedules, #(session, name)),
          )
        }
        False -> {
          process.send(reply, Error("no schedule named " <> name))
          state
        }
      }
    Fire(session:, name:) ->
      case dict.get(state.schedules, #(session, name)) {
        Ok(Scheduled(timing: Once(_), ..) as scheduled) -> {
          deliver(state, name, scheduled)
          State(
            ..state,
            schedules: dict.delete(state.schedules, #(session, name)),
          )
        }
        // Cancelled, or replaced by a repeating schedule.
        _ -> state
      }
    Observed(event) -> {
      let log =
        dict.upsert(state.log, event.connection, fn(log) {
          connection.append_log(option.unwrap(log, []), event, max_log)
        })
      let state = State(..state, log:)
      case event.live {
        True -> observed(state, event)
        False -> state
      }
    }
    Webhook(delivery:, reply:) -> {
      let event = webhook(state, delivery)
      process.send(reply, result.replace(event, Nil))
      case event {
        Ok(event) -> {
          let log =
            dict.upsert(state.log, event.connection, fn(log) {
              connection.append_log(option.unwrap(log, []), event, max_log)
            })
          observed(State(..state, log:), event)
        }
        Error(_) -> state
      }
    }
    ReadEvents(connection: name, reply:) -> {
      case list.any(state.connections, fn(c) { c.name == name }) {
        True -> {
          let events = dict.get(state.log, name) |> result.unwrap([])
          Ok(list.map(events, fn(event) { event.value }))
        }
        False -> Error("no connection named " <> name)
      }
      |> process.send(reply, _)
      state
    }
  }
  |> actor.continue
}

/// Check and convert a webhook delivery, only GitHub connections with a secret accept webhooks.
fn webhook(
  state: State,
  delivery: github.Delivery,
) -> Result(connection.Event, String) {
  let github.Delivery(connection: name, kind:, delivery: id, signature:, body:) =
    delivery
  let found = list.find(state.connections, fn(c) { c.name == name })
  case found {
    Ok(connection.Connection(
      source: connection.GitHub(secret: Some(secret), ..),
      ..,
    )) ->
      case github.verify(secret, body, signature) {
        True -> github.from_webhook(name, kind, id, body)
        False -> Error("invalid signature")
      }
    Ok(_) -> Error(name <> " does not accept webhooks")
    Error(Nil) -> Error("no connection named " <> name)
  }
}

/// Give a live event to the triggers of the channel its connection names.
fn observed(state: State, event: connection.Event) -> State {
  let target =
    list.find_map(state.connections, fn(c) {
      case c.name == event.connection, c.channel {
        True, Some(channel) -> Ok(channel)
        _, _ -> Error(Nil)
      }
    })
  case result.try(target, find_channel(state, _)) {
    Ok(#(outbound, info)) -> {
      let state = install(state, info)
      let conversation = channel.Conversation(info.platform, info.id, None)
      let started = "a " <> event.connection <> " event, " <> event.summary
      run_triggers(state, event.value, started, conversation, outbound, info)
      state
    }
    Error(Nil) -> {
      io.println_error(
        event.connection <> ": no channel to send " <> event.summary <> " to",
      )
      state
    }
  }
}

/// Find a channel by name on any connected chat.
fn find_channel(state: State, name: String) {
  dict.to_list(state.platforms)
  |> list.find_map(fn(platform) {
    let #(platform, outbound) = platform
    use channels <- result.try(outbound.channels() |> result.replace_error(Nil))
    use #(id, _) <- result.map(list.find(channels, fn(c) { c.1 == name }))
    #(
      outbound,
      config.ChannelInfo(platform:, id:, name:, input_type: outbound.input_type),
    )
  })
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
      run_triggers(
        state,
        value,
        "a native channel event",
        conversation,
        outbound,
        info,
      )
      state
    }
    work.Post(thread, text) -> {
      let conversation = channel.Conversation(..origin, thread:)
      let host =
        host(state, outbound, conversation, info, channel.key(conversation))
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
      let host = host(state, outbound, reply, info, channel.key(conversation))
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

fn until_next_second() {
  let #(_, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  1000 - nanoseconds / 1_000_000
}

/// Send a scheduled message to its session, if the session exists.
fn deliver(state: State, name, scheduled: Scheduled) -> Nil {
  let key = case scheduled.target {
    Session(key) -> Ok(key)
    ChannelNamed(channel) -> dict.get(state.channels, channel)
  }
  case result.try(key, dict.get(state.sessions, _)) {
    Ok(session) -> {
      let kind = case scheduled.timing {
        Repeating(_) -> "cron"
        Once(_) -> "timeout"
      }
      let text = "[" <> kind <> " " <> name <> "] " <> scheduled.message
      process.send(session, session.Input(text))
    }
    Error(Nil) ->
      io.println_error("schedule " <> name <> " has no session to send to")
  }
}

/// Run the script of each active trigger whose pattern matches the event.
/// Scripts post to `conversation`, the thread of a chat message or the channel.
/// Each trigger is matched and run in its own process.
fn run_triggers(
  state: State,
  event: data.Value,
  started: String,
  conversation: Conversation,
  outbound: channel.Outbound,
  info: config.ChannelInfo,
) -> Nil {
  let key = channel.key(conversation)
  channel_triggers(state, trigger_key(info))
  |> list.filter(fn(t) { t.active })
  |> list.each(fn(t) {
    let host = host(state, outbound, conversation, info, key)
    let #(load, complete) = #(state.load, state.complete)
    process.spawn(fn() {
      let location =
        location(info, conversation)
        <> "\nYou were started by the trigger "
        <> t.name
        <> " for "
        <> started
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
          host: host(state, outbound, conversation, info, key),
        )
      let assert Ok(session) = session.start(setup)
      let sessions = dict.insert(state.sessions, key, session)
      let channels = case conversation.thread {
        None -> dict.insert(state.channels, info.name, key)
        Some(_) -> state.channels
      }
      #(session, State(..state, sessions:, channels:))
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

/// The host for programs run from a conversation, posts go to `conversation`.
/// File changes are made as the channel, triggers are added to the channel
/// and scheduled messages are sent to the session with key `session`.
fn host(state: State, outbound: channel.Outbound, conversation, info, session) {
  let config.ChannelInfo(name:, ..) = info
  let key = trigger_key(info)
  let self = state.self
  let triggers =
    execute.Triggers(
      add: fn(t) { process.call(self, 5000, AddTrigger(info, t, _)) },
      update: fn(name, update) {
        process.call(self, 5000, UpdateTrigger(info, name, update, _))
      },
      list: fn() { process.call(self, 5000, ListTriggers(info, _)) },
    )
  let schedules =
    execute.Schedules(
      cron: fn(name, spec, message) {
        use schedule <- result.try(cron.parse(spec))
        let timing = Repeating(schedule)
        process.call(self, 5000, AddSchedule(session, name, timing, message, _))
      },
      timeout: fn(name, after, message) {
        let timing = Once(after)
        process.call(self, 5000, AddSchedule(session, name, timing, message, _))
      },
      cancel: fn(name) {
        process.call(self, 5000, CancelSchedule(session, name, _))
      },
    )
  let host =
    execute.channel_host(
      outbound.post(conversation, _),
      execute.files(state.files, "#" <> name),
      triggers,
      schedules,
      execute.artifacts(state.artifacts, artifacts.Channel(key, name)),
    )
  execute.Host(..host, events: fn(connection) {
    process.call(self, 5000, ReadEvents(connection, _))
  })
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
