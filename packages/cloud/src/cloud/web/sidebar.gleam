//// The list of sessions beside the terminal, as a Lustre server component.
//// It follows the registry so new sessions and commands show up at once.

import cloud/sessions.{type Session, type Sessions}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import howdy/ui/sidebar
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/server_component

pub type Model {
  Model(current: String, sessions: List(Session))
}

pub type Msg {
  SessionChanged(Session)
}

pub fn app() -> lustre.App(#(Sessions, String), Model, Msg) {
  lustre.application(init, update, view)
}

fn init(args: #(Sessions, String)) -> #(Model, Effect(Msg)) {
  let #(registry, current) = args
  let effect = {
    use _dispatch, subject <- server_component.select
    sessions.subscribe(registry, subject)
    process.new_selector()
    |> process.select_map(subject, fn(event) {
      let sessions.Changed(session) = event
      SessionChanged(session)
    })
  }
  #(Model(current:, sessions: sessions.all(registry)), effect)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SessionChanged(session) -> {
      let others = list.filter(model.sessions, fn(s) { s.id != session.id })
      let sessions = case list.length(others) == list.length(model.sessions) {
        // A new session goes first, the list is newest first.
        True -> [session, ..others]
        False ->
          list.map(model.sessions, fn(s) {
            case s.id == session.id {
              True -> session
              False -> s
            }
          })
      }
      #(Model(..model, sessions:), effect.none())
    }
  }
}

/// Sessions that have run nothing are hidden, apart from the open one.
pub fn visible(model: Model) -> List(Session) {
  list.filter(model.sessions, fn(session) {
    session.id == model.current || sessions.commands(session) > 0
  })
}

pub fn view(model: Model) -> Element(Msg) {
  sidebar.group(
    "Sessions",
    list.map(visible(model), fn(session) {
      sidebar.link(
        "/sessions/" <> session.id,
        active: session.id == model.current,
        attributes: [attribute.title(sessions.title(session))],
        children: [
          html.span([attribute.class("session-item")], [
            html.span([attribute.class("session-title")], [
              html.text(truncate(sessions.title(session), 32)),
            ]),
            html.span([attribute.class("session-meta")], [
              html.text(meta(session)),
            ]),
          ]),
        ],
      )
    }),
  )
}

fn meta(session: Session) -> String {
  let commands = case sessions.commands(session) {
    1 -> "1 command"
    n -> int.to_string(n) <> " commands"
  }
  let title = sessions.title(session)
  case session.origin {
    // A fork with no commands of its own is already titled as a fork.
    Some(origin) ->
      case string.starts_with(title, "fork of ") {
        True -> commands
        False -> commands <> " · fork of " <> origin.session
      }
    None -> commands
  }
}

fn truncate(text, length) {
  case string.length(text) > length {
    True -> string.slice(text, 0, length - 1) <> "…"
    False -> text
  }
}
