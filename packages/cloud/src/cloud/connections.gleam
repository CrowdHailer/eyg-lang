//// Existing Slack/Discord transports route into box-owned configurations.

import cloud/access
import cloud/api
import cloud/beam/execute
import cloud/box
import cloud/box/check
import cloud/catalog
import cloud/session
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string

pub fn key(id) {
  id |> string.lowercase |> string.replace(":", "-")
}

pub fn start(service: api.Service) {
  actor.new(service)
  |> actor.on_message(fn(service, message) {
    dispatch(service, message)
    actor.continue(service)
  })
  |> actor.start
}

pub fn dispatch(service: api.Service, message: session.Message) {
  case message {
    session.Trigger(_, _) -> Nil
    session.Incoming(id, input) -> {
      let path = "/system/events/" <> key(id) <> ".eyg"
      each_config(service, path, fn(owner) {
        let _ = box.invoke(owner, path, input)
        Nil
      })
    }
    session.Message(id, payload, print) -> {
      let path = "/system/connections/" <> key(id) <> ".eyg"
      let text = case payload {
        session.Code(code) -> code
        session.UserPrompt(text) -> text
      }
      each_config(service, path, fn(owner) {
        case
          box.connect(owner, path, access.token_id(id), text, service.agent)
        {
          Ok(text) -> print(execute.StandardOut(text))
          Error(reason) -> print(execute.StandardError(reason))
        }
      })
    }
  }
}

fn each_config(service: api.Service, path, then) {
  list.each(catalog.names(service.catalog), fn(name) {
    case catalog.get(service.catalog, name) {
      Error(_) -> Nil
      Ok(owner) -> {
        let files = box.inspect(owner).files
        case check.paths(files, "") |> result.map(list.contains(_, path)) {
          Ok(True) -> then(owner)
          _ -> Nil
        }
      }
    }
  })
}
