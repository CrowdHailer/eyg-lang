//// A workspace routes the events of every connected platform.
////
//// Each conversation has a session with an agent.
//// A plugin's native input goes to the channel's checked handler. Its work requests
//// choose sessions, observations, invocations and policy-controlled posts.
////
//// The workspace holds no EYG closures, configuration is evaluated by the processes
//// that run programs and events are plain data, see `notes/cloud-process-boundaries.md`.

import clockwork
import cloud/artifacts
import cloud/beam/execute
import cloud/channel
import cloud/config
import cloud/connection
import cloud/data
import cloud/discord/channel as discord
import cloud/discord/client as discord_client
import cloud/discord/input as discord_input
import cloud/handler
import cloud/invocation
import cloud/operation
import cloud/overlay as agent
import cloud/plugins/example_chat
import cloud/plugins/whatsapp
import cloud/schedule as cron_schedule
import cloud/session
import cloud/shell
import cloud/slack/channel as slack
import cloud/slack/client as slack_client
import cloud/slack/input as slack_input
import cloud/tracing
import cloud/trigger/configured.{type Trigger} as trigger
import cloud/webhook
import cloud/work
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp

pub type Message {
  /// A platform plugin has started, outbound operations for the platform are now available.
  Connect(platform: String, outbound: channel.Outbound)
  Inbound(channel.Event)
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
  Tick(timestamp.Timestamp)
  AddSchedule(
    delivery: Delivery,
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
  /// A plugin answers the webhook requests of the connection `name`.
  Listen(connection: String, listener: webhook.Listener)
  /// A request to the webhook of the connection `connection`,
  /// replies with an error when there is no such connection.
  /// The reply is a function the caller runs for the response, so a webhook's
  /// `respond` function is evaluated in the caller's process, not the workspace's.
  Webhook(
    connection: String,
    request: webhook.Request,
    reply: Subject(Result(fn() -> webhook.Response, String)),
  )
  /// Give programs in this workspace the configuration API, gated by their channel shells.
  SetApi(api: fn(operation.Operation) -> Result(data.Value, String))
  /// Every channel of every connected chat.
  ListChannels(reply: Subject(List(config.ChannelInfo)))
  /// The connections the workspace started with.
  GetConnections(reply: Subject(List(connection.Connection)))
  /// The triggers of a channel by name.
  ChannelTriggers(
    channel: String,
    reply: Subject(Result(List(Trigger), String)),
  )
  /// The host for a program run as a channel, for binding a web shell to it.
  ChannelHost(
    channel: String,
    reply: Subject(Result(#(config.ChannelInfo, execute.Host), String)),
  )
  /// Bind a user's private session to a channel, including scheduled work.
  WebHost(
    user: String,
    channel: String,
    reply: Subject(Result(#(config.ChannelInfo, execute.Host), String)),
  )
}

pub type Timing {
  Repeating(clockwork.Cron, next: timestamp.Timestamp)
  /// Send once after the milliseconds.
  Once(Int)
}

/// Who a scheduled message is sent to.
type Target {
  /// The session with this key.
  Session(Delivery)
  /// The session of the channel with this name, if it has one.
  ChannelNamed(String)
}

type Scheduled {
  Scheduled(target: Target, timing: Timing, message: String)
}

/// A timer retains its policy context and reply destination even if the user
/// later binds their session elsewhere. This is schedule data, not session state.
pub type Delivery {
  Delivery(
    id: String,
    channel: config.ChannelInfo,
    reply: option.Option(String),
  )
}

type State {
  State(
    self: Subject(Message),
    load: config.Loader,
    platforms: Dict(String, channel.Outbound),
    namespace: String,
    /// Plugins that answer webhook requests, by connection name.
    listeners: Dict(String, webhook.Listener),
    executor: Subject(session.Message),
    seed: option.Option(String),
    /// Triggers per channel, keyed by `platform:channel`.
    /// A channel's configured triggers are installed when its first event arrives.
    triggers: Dict(String, List(Trigger)),
    /// Scheduled messages, keyed by the session that scheduled them and a name.
    schedules: Dict(#(String, String), Scheduled),
    artifacts: Subject(artifacts.Message),
    complete: agent.Completer,
    connections: List(connection.Connection),
    api: fn(operation.Operation) -> Result(data.Value, String),
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
  use executor <- result.try(session.start_configured())
  start_on(load, artifacts, complete, executor, "standalone")
}

/// All production workspaces share the registry's executor.
pub fn start_on(
  load: config.Loader,
  artifacts: Subject(artifacts.Message),
  complete: agent.Completer,
  executor: Subject(session.Message),
  namespace: String,
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
      use timing <- result.map(repeating(c.schedule))
      let scheduled = Scheduled(ChannelNamed(c.channel), timing, c.message)
      #(#("workspace", c.name), scheduled)
    }),
  )
  actor.new_with_initialiser(1000, fn(self) {
    schedule_tick(self)
    State(
      self:,
      load:,
      platforms: dict.new(),
      namespace:,
      listeners: dict.new(),
      executor:,
      seed:,
      triggers: dict.new(),
      schedules: dict.from_list(schedules),
      artifacts:,
      complete:,
      connections:,
      api: fn(_) { Error("The configuration API is not available") },
    )
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) {
    list.each(connections, start_connection(started.data, executor, _))
    started.data
  })
  |> result.map_error(string.inspect)
}

/// Start a connection in its own process, its events are sent to the workspace.
fn start_connection(
  workspace: Subject(Message),
  executor: Subject(session.Message),
  connection: connection.Connection,
) -> Nil {
  let connection.Connection(name:, source:) = connection
  let inbound = fn(event) { process.send(workspace, Inbound(event)) }
  process.spawn(fn() {
    let started = case source {
      connection.ExampleChat(origin) -> {
        let config = example_chat.Config(origin:, poll_interval: 500)
        use outbound <- result.map(example_chat.start(config, inbound))
        process.send(workspace, Connect(example_chat.platform, outbound))
      }
      connection.WhatsApp(token:, phone_number_id:, app_secret:, verify_token:) -> {
        let config =
          whatsapp.Config(token:, phone_number_id:, app_secret:, verify_token:)
        use #(outbound, listener) <- result.map(whatsapp.start(config, inbound))
        process.send(workspace, Listen(name, listener))
        process.send(workspace, Connect(whatsapp.platform, outbound))
      }
      connection.Slack(token) -> {
        use identity <- result.try(
          slack_client.auth_test(token) |> result.map_error(string.inspect),
        )
        let installation = channel.installation("slack", identity.team_id)
        let hook = fn(event) { inbound(channel.at(event, installation)) }
        use poller <- result.map(
          slack.start_with_hook(token, identity, executor, Some(hook))
          |> result.map_error(string.inspect),
        )
        let outbound =
          channel.Outbound(
            input_type: slack_input.input_type(),
            post: fn(id, reply, text) {
              slack_client.chat_post_message(token, id, reply, text, None)
              |> result.map_error(string.inspect)
            },
            channel_name: fn(id) {
              process.call(poller.data, 5000, slack.Name(id, _))
            },
            channels: fn() {
              Ok(process.call(poller.data, 5000, slack.Channels))
            },
          )
        process.send(workspace, Connect(installation, outbound))
      }
      connection.Discord(token:, guild:) -> {
        use identity <- result.try(
          discord_client.current_user(token) |> result.map_error(string.inspect),
        )
        use guild <- result.try(
          discord_client.guild(token, guild) |> result.map_error(string.inspect),
        )
        let installation = channel.installation("discord", guild.id)
        let hook = fn(event) { inbound(channel.at(event, installation)) }
        use poller <- result.map(
          discord.start_with_hook(
            token,
            guild,
            identity.id,
            executor,
            Some(hook),
          )
          |> result.map_error(string.inspect),
        )
        let outbound =
          channel.Outbound(
            input_type: discord_input.input_type(),
            post: fn(id, reply, text) { discord.post(token, id, reply, text) },
            channel_name: fn(id) {
              process.call(poller.data, 5000, discord.Name(id, _))
            },
            channels: fn() {
              Ok(process.call(poller.data, 5000, discord.Channels))
            },
          )
        process.send(workspace, Connect(installation, outbound))
      }
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
    Tick(now) -> {
      schedule_tick(state.self)
      let schedules =
        dict.map_values(state.schedules, fn(key, scheduled) {
          case scheduled.timing {
            Repeating(schedule, next) ->
              case timestamp.compare(now, next) {
                order.Lt -> scheduled
                _ -> {
                  deliver(state, key.1, scheduled)
                  let next = cron_schedule.next_occurrence(schedule, now)
                  Scheduled(..scheduled, timing: Repeating(schedule, next))
                }
              }
            Once(_) -> scheduled
          }
        })
      State(..state, schedules:)
    }
    AddSchedule(delivery:, name:, timing:, message:, reply:) -> {
      let session = delivery.id
      process.send(reply, Ok(Nil))
      case timing {
        Once(after) -> {
          let _ =
            process.send_after(
              state.self,
              int.max(after, 0),
              Fire(session, name),
            )
          Nil
        }
        Repeating(..) -> Nil
      }
      let scheduled = Scheduled(Session(delivery), timing, message)
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
    Listen(connection:, listener:) ->
      State(
        ..state,
        listeners: dict.insert(state.listeners, connection, listener),
      )
    Webhook(connection: name, request:, reply:) -> {
      let response =
        dict.get(state.listeners, name)
        |> result.map(fn(listener) { fn() { listener(request) } })
        |> result.replace_error("no connection named " <> name)
      process.send(reply, response)
      state
    }
    SetApi(api:) -> State(..state, api:)
    ListChannels(reply:) -> {
      dict.to_list(state.platforms)
      |> list.flat_map(fn(platform) {
        let #(platform, outbound) = platform
        outbound.channels()
        |> result.unwrap([])
        |> list.map(fn(c) {
          config.ChannelInfo(
            platform:,
            id: c.0,
            name: c.1,
            input_type: outbound.input_type,
          )
        })
      })
      |> process.send(reply, _)
      state
    }
    GetConnections(reply:) -> {
      process.send(reply, state.connections)
      state
    }
    ChannelTriggers(channel: name, reply:) ->
      case find_channel(state, name) {
        Ok(#(_outbound, info)) -> {
          let state = install(state, info)
          process.send(reply, Ok(channel_triggers(state, trigger_key(info))))
          state
        }
        Error(Nil) -> {
          process.send(reply, Error("no channel named " <> name))
          state
        }
      }
    ChannelHost(channel: name, reply:) -> {
      case find_channel(state, name) {
        Ok(#(outbound, info)) -> {
          let id = session_id(state, info, None)
          Ok(#(info, host(state, outbound, info, None, id)))
        }
        Error(Nil) -> Error("no channel named " <> name)
      }
      |> process.send(reply, _)
      state
    }
    WebHost(user:, channel: name, reply:) -> {
      case find_channel(state, name) {
        Error(Nil) -> {
          process.send(reply, Error("no unique channel named " <> name))
          state
        }
        Ok(#(outbound, info)) -> {
          let id = "web:" <> user
          let host = host(state, outbound, info, None, id)
          process.send(reply, Ok(#(info, host)))
          state
        }
      }
    }
  }
  |> actor.continue
}

/// Find a channel by name on any connected chat.
fn find_channel(state: State, name: String) {
  let matches =
    dict.to_list(state.platforms)
    |> list.flat_map(fn(platform) {
      let #(platform, outbound) = platform
      outbound.channels()
      |> result.unwrap([])
      |> list.filter(fn(c) { c.1 == name || platform <> ":" <> c.0 == name })
      |> list.map(fn(c) {
        #(
          outbound,
          config.ChannelInfo(
            platform:,
            id: c.0,
            name: c.1,
            input_type: outbound.input_type,
          ),
        )
      })
    })
  case matches {
    [found] -> Ok(found)
    _ -> Error(Nil)
  }
}

fn inbound(state: State, event: channel.Event) -> State {
  let channel.Incoming(platform, channel_id, _, value) = event
  case dict.get(state.platforms, platform) {
    Error(Nil) -> {
      io.println_error(platform <> ":" <> channel_id <> ": not connected")
      state
    }
    Ok(outbound) -> {
      let info =
        config.ChannelInfo(
          platform,
          channel_id,
          outbound.channel_name(channel_id),
          outbound.input_type,
        )
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
          list.each(requests, fn(request) {
            perform_work(state, request, event, outbound, info)
          })
          state
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
) -> Nil {
  let channel.Incoming(_, _, default_reply, value) = event
  case request {
    work.Submit(session, reply, text, description) -> {
      let requests = case string.trim(text), invocation.parse(text) {
        "/new", _ -> [
          work.Reset(session),
          work.Post(
            reply,
            "Started a new conversation, earlier messages are forgotten.",
          ),
        ]
        _, Ok(code) -> [work.Run(session, reply, code, description)]
        _, Error(Nil) -> [work.Input(session, description)]
      }
      list.each(requests, fn(request) {
        perform_work(state, request, event, outbound, info)
      })
    }
    work.Trigger(thread) -> {
      run_triggers(
        state,
        value,
        "a native channel event",
        thread,
        outbound,
        info,
      )
    }
    work.Post(thread, text) -> {
      let #(id, setup) = setup_for(state, info, None, outbound, default_reply)
      let #(load, complete) = #(state.load, state.complete)
      process.send(
        state.executor,
        session.Dispatch(
          id,
          Some(setup),
          session.Run(fn(host, execution) {
            case
              shell.prepare(load, info, host, location(info, None), complete)
            {
              Ok(shell) -> {
                let #(_, execution) =
                  shell.run(
                    shell,
                    "perform Post(text)",
                    [
                      #("text", data.string(text)),
                    ],
                    execute.State(..shell.state, files: execution.files),
                  )
                #(None, execution)
              }
              Error(reason) -> {
                io.println_error("#" <> info.name <> " post: " <> reason)
                #(None, execution)
              }
            }
          }),
          Some(outbound.post(info.id, thread, _)),
        ),
      )
    }
    work.Input(selected, text) -> {
      let #(id, setup) =
        setup_for(state, info, selected, outbound, default_reply)
      session.submit(state.executor, id, setup, session.Input(text), None)
    }
    work.Observe(selected, text) -> {
      let #(id, setup) =
        setup_for(state, info, selected, outbound, default_reply)
      session.submit(state.executor, id, setup, session.Observe(text), None)
    }
    work.Reset(selected) -> {
      let #(id, setup) =
        setup_for(state, info, selected, outbound, default_reply)
      session.submit(state.executor, id, setup, session.Reset, None)
    }
    work.Run(selected, reply, code, description) -> {
      let #(id, setup) =
        setup_for(state, info, selected, outbound, default_reply)
      let #(load, complete) = #(state.load, state.complete)
      // Only plain data and host operations cross this boundary, never the handler closure.
      process.send(
        state.executor,
        session.Dispatch(
          id,
          Some(setup),
          session.Run(fn(host, execution) {
            let #(observed, execution) = case
              shell.prepare(
                load,
                info,
                host,
                location(info, selected),
                complete,
              )
            {
              Ok(shell) -> {
                let attributes = [
                  #("eyg.cloud.channel", tracing.text(info.name)),
                ]
                use trace <-
                  tracing.span(
                    "eyg.cloud.invocation",
                    None,
                    attributes,
                    _,
                    fn(_) { None },
                  )
                let host = execute.Host(..shell.host, trace: Some(trace))
                invoke(
                  shell.Shell(..shell, host:),
                  code,
                  description,
                  execute.State(..shell.state, files: execution.files),
                )
              }
              Error(reason) -> #(
                description <> "\nError: " <> reason,
                execution,
              )
            }
            #(Some(observed), execution)
          }),
          Some(outbound.post(info.id, reply, _)),
        ),
      )
    }
  }
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

fn schedule_tick(self) {
  let now = timestamp.system_time()
  let #(_, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(now)
  let delay = 1000 - nanoseconds / 1_000_000
  process.send_after(
    self,
    delay,
    Tick(timestamp.add(now, duration.milliseconds(delay))),
  )
}

fn repeating(spec) {
  use schedule <- result.map(
    clockwork.from_string(spec)
    |> result.replace_error("Invalid five-field cron schedule: " <> spec),
  )
  Repeating(
    schedule,
    cron_schedule.next_occurrence(schedule, timestamp.system_time()),
  )
}

/// Send a scheduled message to its session, if the session exists.
fn deliver(state: State, name, scheduled: Scheduled) -> Nil {
  let kind = case scheduled.timing {
    Repeating(..) -> "cron"
    Once(_) -> "timeout"
  }
  let text = "[" <> kind <> " " <> name <> "] " <> scheduled.message
  let sent = case scheduled.target {
    Session(Delivery(id, info, reply)) -> {
      use outbound <- result.map(dict.get(state.platforms, info.platform))
      let host = host(state, outbound, info, reply, id)
      let setup =
        session.Setup(
          name: id,
          channel: info,
          location: location(info, None),
          load: state.load,
          complete: state.complete,
          host:,
          seed: None,
        )
      session.submit(state.executor, id, setup, session.Input(text), None)
    }
    ChannelNamed(channel) -> {
      use #(outbound, info) <- result.map(find_channel(state, channel))
      let id = session_id(state, info, None)
      process.send(
        state.executor,
        session.Dispatch(
          id,
          None,
          session.Input(text),
          Some(outbound.post(info.id, None, _)),
        ),
      )
    }
  }
  case sent {
    Ok(_) -> Nil
    Error(Nil) ->
      io.println_error("schedule " <> name <> " has no channel to send to")
  }
}

/// Run the script of each active trigger whose pattern matches the event.
/// The plugin's reply callback is independent of the selected session's state.
/// Matching and execution use the same central queue as agent turns.
fn run_triggers(
  state: State,
  event: data.Value,
  started: String,
  selected: option.Option(String),
  outbound: channel.Outbound,
  info: config.ChannelInfo,
) -> Nil {
  let #(id, setup) = setup_for(state, info, selected, outbound, selected)
  channel_triggers(state, trigger_key(info))
  |> list.filter(fn(t) { t.active })
  |> list.each(fn(t) {
    let #(load, complete) = #(state.load, state.complete)
    session.submit(
      state.executor,
      id,
      setup,
      session.Run(fn(host, execution) {
        let location =
          location(info, selected)
          <> "\nYou were started by the trigger "
          <> t.name
          <> " for "
          <> started
          <> "."
        let prepared = {
          use shell <- result.try(shell.prepare(
            load,
            info,
            host,
            location,
            complete,
          ))
          use matched <- result.map(
            shell.matches(shell, t.pattern, event)
            |> result.map_error(fn(reason) { "pattern: " <> reason }),
          )
          #(shell, matched)
        }
        let #(outcome, execution) = case prepared {
          Error(reason) -> #(Error(reason), execution)
          Ok(#(shell, matched)) ->
            case matched {
              True -> {
                let attributes = [
                  #("eyg.trigger.name", tracing.text(t.name)),
                  #("eyg.cloud.channel", tracing.text(info.name)),
                  #("eyg.trigger.event", tracing.text(event_tag(event))),
                ]
                use trace <-
                  tracing.span(
                    "eyg.cloud.trigger",
                    None,
                    attributes,
                    _,
                    fn(result) {
                      case result.0 {
                        Ok(_) -> None
                        Error(reason) -> Some(reason)
                      }
                    },
                  )
                let host = execute.Host(..shell.host, trace: Some(trace))
                let #(execute.Run(result:, ..), execution) =
                  shell.run_script(
                    shell.Shell(..shell, host:),
                    t.script,
                    event,
                    execute.State(..shell.state, files: execution.files),
                  )
                #(result.replace(result, True), execution)
              }
              False -> #(Ok(False), execution)
            }
        }
        case outcome {
          Ok(True) ->
            io.println("trigger " <> t.name <> " ran in #" <> info.name)
          Ok(False) -> Nil
          Error(reason) ->
            io.println_error("trigger " <> t.name <> " failed: " <> reason)
        }
        #(None, execution)
      }),
      None,
    )
  })
}

fn event_tag(event: data.Value) -> String {
  case event {
    v.Tagged(tag, _) -> tag
    _ -> "Event"
  }
}

fn session_name(info: config.ChannelInfo, selected) {
  let base = info.platform <> ":" <> info.id
  case selected {
    None -> base
    Some(name) -> base <> ":" <> name
  }
}

fn session_id(state: State, info, selected) {
  // Session identity is independent of the reply address.
  json.array([state.namespace, session_name(info, selected)], json.string)
  |> json.to_string
}

fn setup_for(state: State, info, selected, outbound, reply) {
  let id = session_id(state, info, selected)
  let key = session_name(info, selected)
  let setup =
    session.Setup(
      name: key,
      channel: info,
      location: location(info, selected),
      load: state.load,
      complete: state.complete,
      host: host(state, outbound, info, reply, id),
      seed: state.seed,
    )
  #(id, setup)
}

fn location(info: config.ChannelInfo, selected) {
  let selected = case selected {
    Some(name) -> ", using session " <> name
    None -> ""
  }
  "You are in the channel #" <> info.name <> selected <> "."
}

/// Bind channel services to an explicit session ID and a separate reply target.
fn host(state: State, outbound: channel.Outbound, info, reply, session) {
  let config.ChannelInfo(name:, ..) = info
  let key = trigger_key(info)
  let self = state.self
  let delivery = Delivery(session, info, reply)
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
        use timing <- result.try(repeating(spec))
        process.call(self, 5000, AddSchedule(delivery, name, timing, message, _))
      },
      timeout: fn(name, after, message) {
        let timing = Once(after)
        process.call(self, 5000, AddSchedule(delivery, name, timing, message, _))
      },
      cancel: fn(name) {
        process.call(self, 5000, CancelSchedule(session, name, _))
      },
    )
  let host =
    execute.channel_host(
      outbound.post(info.id, reply, _),
      execute.no_files(),
      triggers,
      schedules,
      execute.artifacts(state.artifacts, artifacts.Channel(key, name)),
    )
  execute.Host(..host, api: state.api)
}

/// Run a direct invocation, post its output and return a description for the agent.
fn invoke(shell: shell.Shell, code, description: String, execution) {
  let #(execute.Run(result:, output:), execution) =
    shell.run(shell, code, [], execution)
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
  #(description <> output <> "\nIt returned: " <> returned, execution)
}
