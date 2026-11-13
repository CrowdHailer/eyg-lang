//// Configured chat connections. Adapter implementations land after deployment.

import cloud/data
import eyg/interpreter/cast
import gleam/result

pub type Source {
  ExampleChat(origin: String)
  Slack(token: String)
  Discord(token: String, guild: String)
  WhatsApp(
    token: String,
    phone_number_id: String,
    app_secret: String,
    verify_token: String,
  )
}

pub type Connection {
  Connection(name: String, source: Source)
}

pub fn kind(source) {
  case source {
    ExampleChat(..) -> "ExampleChat"
    Slack(..) -> "Slack"
    Discord(..) -> "Discord"
    WhatsApp(..) -> "WhatsApp"
  }
}

pub fn decode(value) {
  use name <- result.try(cast.field("name", cast.as_string, value))
  use source <- result.map(cast.field("source", decode_source, value))
  Connection(name, source)
}

fn decode_source(value) {
  cast.as_variant(value, [
    #("ExampleChat", fn(c) {
      use origin <- result.map(cast.field("origin", cast.as_string, c))
      ExampleChat(origin)
    }),
    #("Slack", fn(c) {
      use token <- result.map(cast.field("token", cast.as_string, c))
      Slack(token)
    }),
    #("Discord", fn(c) {
      use token <- result.try(cast.field("token", cast.as_string, c))
      use guild <- result.map(cast.field("guild", cast.as_string, c))
      Discord(token, guild)
    }),
    #("WhatsApp", fn(c) {
      use token <- result.try(cast.field("token", cast.as_string, c))
      use phone <- result.try(cast.field("phone_number_id", cast.as_string, c))
      use secret <- result.try(cast.field("app_secret", cast.as_string, c))
      use verify <- result.map(cast.field("verify_token", cast.as_string, c))
      WhatsApp(token, phone, secret, verify)
    }),
  ])
}

pub fn to_value(connection: Connection) {
  data.record([
    #("name", data.string(connection.name)),
    #("kind", data.string(kind(connection.source))),
  ])
}
