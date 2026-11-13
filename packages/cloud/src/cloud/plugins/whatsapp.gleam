//// Channel plugin for WhatsApp, using the WhatsApp Business Platform Cloud API.
////
//// WhatsApp pushes messages to a webhook, there is nothing to poll.
//// The plugin answers requests to its connection's webhook, `/connections/<name>/webhook`:
//// a `GET` verifies the subscription with `verify_token`,
//// a `POST` is a delivery signed with the app secret.
//// Messages are sent with the Graph API as the business phone number `phone_number_id`.
////
//// Each person who messages the number is a channel, its id and name is their WhatsApp id, their phone number.
//// WhatsApp has no threads, posting to the thread of a message replies to, and quotes, that message.
//// Reaction events retain the original message and include its native referenced message when known.

import cloud/channel
import cloud/data
import cloud/jsonx
import cloud/webhook
import eyg/analysis/type_/isomorphic as t
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub const platform = "whatsapp"

const graph_version = "v23.0"

/// The longest text message WhatsApp accepts, longer posts are sent in parts.
const max_text = 4096

/// How many messages are remembered, to report reactions and ignore redeliveries.
const remembered = 1000

pub type Config {
  Config(
    /// A system user access token with the `whatsapp_business_messaging` permission.
    token: String,
    /// The id of the business phone number messages are sent from and to.
    phone_number_id: String,
    /// The app secret that signs webhook deliveries.
    app_secret: String,
    /// The token entered when subscribing the webhook in the app dashboard.
    verify_token: String,
  )
}

/// A message, or reaction, in a webhook delivery.
pub type Incoming {
  Incoming(
    id: String,
    from: String,
    /// The sender's profile name, when the delivery includes it.
    name: Option(String),
    content: Content,
    timestamp: String,
    context: Option(String),
    /// Original message JSON, including fields not yet described by this plugin.
    data: String,
  )
}

pub type Content {
  Text(text: String)
  Button(text: String, payload: String)
  Interactive(
    kind: String,
    id: String,
    title: String,
    description: Option(String),
  )
  Media(
    kind: String,
    id: Option(String),
    caption: String,
    mime_type: Option(String),
  )
  Other(kind: String)
  /// An emoji reaction to a message, an empty emoji removes a reaction.
  Reaction(message: String, emoji: String)
}

/// Messages the plugin has seen, oldest last.
pub opaque type Store {
  Store(messages: Dict(String, Incoming), order: List(String))
}

pub fn new_store() -> Store {
  Store(messages: dict.new(), order: [])
}

pub type Message {
  Received(List(Incoming))
  Sent(Incoming)
  Channels(reply: Subject(List(#(String, String))))
}

type State {
  State(
    store: Store,
    people: Dict(String, String),
    emit: fn(channel.Event) -> Nil,
  )
}

/// Start the plugin, returning the outbound operations and the listener for the connection's webhook.
pub fn start(
  config: Config,
  emit: fn(channel.Event) -> Nil,
) -> Result(#(channel.Outbound, webhook.Listener), String) {
  use started <- result.try(
    actor.new(State(store: new_store(), people: dict.new(), emit:))
    |> actor.on_message(handle)
    |> actor.start
    |> result.map_error(string.inspect),
  )
  let plugin = started.data
  let outbound =
    channel.Outbound(
      input_type: input_type(),
      post: fn(channel, reply, text) {
        use id <- result.map(post(config, channel, reply, text))
        process.send(
          plugin,
          Sent(Incoming(id, channel, Some("cloud"), Text(text), "", None, "{}")),
        )
        id
      },
      channel_name: fn(id) { id },
      channels: fn() { Ok(process.call(plugin, 5000, Channels)) },
    )
  let listener = fn(request) {
    case listen(config, request) {
      Ok(incoming) -> {
        process.send(plugin, Received(incoming))
        webhook.accepted()
      }
      Error(response) -> response
    }
  }
  Ok(#(outbound, listener))
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Received(incoming) -> {
      let #(events, store) = receive(state.store, incoming)
      list.each(events, state.emit)
      let people =
        list.fold(incoming, state.people, fn(people, i) {
          dict.insert(people, i.from, i.from)
        })
      actor.continue(State(..state, store:, people:))
    }
    Sent(message) ->
      actor.continue(State(..state, store: remember(state.store, message)))
    Channels(reply) -> {
      process.send(reply, dict.to_list(state.people))
      actor.continue(state)
    }
  }
}

/// Answer a webhook request, returning the messages of a valid delivery.
pub fn listen(
  config: Config,
  request: webhook.Request,
) -> Result(List(Incoming), webhook.Response) {
  case request.method {
    http.Get -> Error(verify_subscription(config, request))
    http.Post -> {
      let signature = webhook.header(request, "x-hub-signature-256")
      case webhook.verify_sha256(config.app_secret, request.body, signature) {
        False -> Error(webhook.Response(401, "invalid signature"))
        True ->
          parse(request.body, config.phone_number_id)
          |> result.map_error(webhook.Response(400, _))
      }
    }
    _ -> Error(webhook.Response(405, "method not allowed"))
  }
}

/// Meta checks a webhook URL with a `GET` before sending deliveries to it.
pub fn verify_subscription(
  config: Config,
  request: webhook.Request,
) -> webhook.Response {
  let mode = webhook.query(request, "hub.mode")
  let token = webhook.query(request, "hub.verify_token")
  case mode == "subscribe" && token == config.verify_token {
    True -> webhook.Response(200, webhook.query(request, "hub.challenge"))
    False -> webhook.Response(403, "verification failed")
  }
}

/// The messages and reactions sent to the phone number in a delivery.
/// Status updates of sent messages and other phone numbers' messages are ignored.
pub fn parse(
  body: String,
  phone_number_id: String,
) -> Result(List(Incoming), String) {
  json.parse(body, decode.at(["entry"], decode.list(entry_decoder())))
  |> result.map(fn(entries) {
    entries
    |> list.flatten
    |> list.filter(fn(change) { change.0 == phone_number_id })
    |> list.flat_map(fn(change) { change.1 })
  })
  |> result.map_error(fn(reason) {
    "invalid delivery " <> string.inspect(reason)
  })
}

fn entry_decoder() {
  decode.at(["changes"], decode.list(change_decoder()))
}

fn change_decoder() {
  use field <- decode.field("field", decode.string)
  case field {
    "messages" ->
      decode.at(["value"], {
        use phone_number_id <- decode.subfield(
          ["metadata", "phone_number_id"],
          decode.string,
        )
        use contacts <- decode.optional_field(
          "contacts",
          [],
          decode.list(contact_decoder()),
        )
        use messages <- decode.optional_field(
          "messages",
          [],
          decode.list(message_decoder()),
        )
        let messages =
          list.filter_map(messages, fn(message) {
            let #(id, from, content, timestamp, context, data) = message
            use content <- result.map(option.to_result(content, Nil))
            let name = list.key_find(contacts, from) |> option.from_result
            Incoming(id:, from:, name:, content:, timestamp:, context:, data:)
          })
        decode.success(#(phone_number_id, messages))
      })
    _ -> decode.success(#("", []))
  }
}

fn contact_decoder() {
  use wa_id <- decode.field("wa_id", decode.string)
  use name <- decode.subfield(["profile", "name"], decode.string)
  decode.success(#(wa_id, name))
}

fn message_decoder() {
  use id <- decode.field("id", decode.string)
  use from <- decode.field("from", decode.string)
  use kind <- decode.field("type", decode.string)
  use content <- decode.then(content_decoder(kind))
  use timestamp <- decode.optional_field("timestamp", "", decode.string)
  use context <- decode.optional_field(
    "context",
    None,
    decode.at(["id"], decode.string) |> decode.map(Some),
  )
  use raw <- decode.then(jsonx.decoder())
  decode.success(#(id, from, content, timestamp, context, json.to_string(raw)))
}

fn content_decoder(kind) -> decode.Decoder(Option(Content)) {
  let text = fn(path) {
    decode.at(path, decode.string) |> decode.map(fn(t) { Some(Text(t)) })
  }
  case kind {
    "text" -> text(["text", "body"])
    "reaction" ->
      decode.at(["reaction"], {
        use message <- decode.field("message_id", decode.string)
        use emoji <- decode.optional_field("emoji", "", decode.string)
        decode.success(Some(Reaction(message:, emoji:)))
      })
    "button" ->
      decode.at(["button"], {
        use text <- decode.field("text", decode.string)
        use payload <- decode.optional_field("payload", "", decode.string)
        decode.success(Some(Button(text, payload)))
      })
    "interactive" ->
      decode.at(["interactive"], {
        use kind <- decode.field("type", decode.string)
        decode.at([kind], {
          use id <- decode.field("id", decode.string)
          use title <- decode.field("title", decode.string)
          use description <- decode.optional_field(
            "description",
            None,
            decode.optional(decode.string),
          )
          decode.success(Some(Interactive(kind, id, title, description)))
        })
      })
    "image" | "video" | "document" | "sticker" | "audio" ->
      decode.at([kind], {
        use id <- decode.optional_field(
          "id",
          None,
          decode.optional(decode.string),
        )
        use caption <- decode.optional_field("caption", "", decode.string)
        use mime_type <- decode.optional_field(
          "mime_type",
          None,
          decode.optional(decode.string),
        )
        decode.success(Some(Media(kind, id, caption, mime_type)))
      })
    // Errors and system messages are not chat messages.
    "unsupported" | "system" | "errors" -> decode.success(None)
    other -> decode.success(Some(Other(other)))
  }
}

/// Turn incoming messages into channel events, ignoring redelivered messages.
pub fn receive(
  store: Store,
  incoming: List(Incoming),
) -> #(List(channel.Event), Store) {
  let #(events, store) =
    list.fold(incoming, #([], store), fn(acc, incoming) {
      let #(events, store) = acc
      let Incoming(id:, from:, content:, ..) = incoming
      case dict.has_key(store.messages, id) {
        True -> acc
        False -> {
          let referenced = case content {
            Reaction(message: target, ..) ->
              dict.get(store.messages, target) |> option.from_result
            _ -> None
          }
          let value =
            data.tagged(
              "WhatsAppMessage",
              data.record([
                #("message", incoming_value(incoming)),
                #("referenced", data.option(referenced, incoming_value)),
              ]),
            )
          let events = case content {
            Reaction(emoji: "", ..) -> events
            _ -> [channel.Incoming(platform, from, None, value), ..events]
          }
          #(events, remember(store, incoming))
        }
      }
    })
  #(list.reverse(events), store)
}

fn remember(store: Store, message: Incoming) -> Store {
  let messages = dict.insert(store.messages, message.id, message)
  let order = [message.id, ..store.order]
  case list.length(order) > remembered {
    False -> Store(messages:, order:)
    True -> {
      let #(order, forgotten) = list.split(order, remembered)
      Store(messages: dict.drop(messages, forgotten), order:)
    }
  }
}

fn post(config: Config, to: String, thread, text: String) {
  chunks(text, max_text)
  |> list.try_fold("", fn(_, part) {
    send(message_request(config, to, part, thread))
  })
}

/// Split text into parts of at most `size` characters.
pub fn chunks(text: String, size: Int) -> List(String) {
  case string.length(text) > size {
    False -> [text]
    True -> [
      string.slice(text, 0, size),
      ..chunks(string.drop_start(text, size), size)
    ]
  }
}

/// The Graph API request that sends text to a person, replying to a message when `reply_to` is set.
pub fn message_request(
  config: Config,
  to: String,
  text: String,
  reply_to: Option(String),
) -> request.Request(String) {
  let context = case reply_to {
    Some(id) -> [#("context", json.object([#("message_id", json.string(id))]))]
    None -> []
  }
  let body =
    json.object([
      #("messaging_product", json.string("whatsapp")),
      #("recipient_type", json.string("individual")),
      #("to", json.string(to)),
      #("type", json.string("text")),
      #("text", json.object([#("body", json.string(text))])),
      ..context
    ])
  request.new()
  |> request.set_method(http.Post)
  |> request.set_host("graph.facebook.com")
  |> request.set_path(
    "/" <> graph_version <> "/" <> config.phone_number_id <> "/messages",
  )
  |> request.set_header("authorization", "Bearer " <> config.token)
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(body))
}

fn send(request) -> Result(String, String) {
  case httpc.send(request) {
    Ok(response) if response.status == 200 ->
      json.parse(
        response.body,
        decode.at(["messages"], decode.list(decode.at(["id"], decode.string))),
      )
      |> result.map_error(string.inspect)
      |> result.try(fn(ids) {
        list.first(ids) |> result.replace_error("no message id in response")
      })
    Ok(response) -> {
      let reason =
        json.parse(
          response.body,
          decode.at(["error", "message"], decode.string),
        )
        |> result.unwrap(response.body)
      io.println_error(
        "WhatsApp " <> int.to_string(response.status) <> ": " <> reason,
      )
      Error(reason)
    }
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn message_type() {
  t.record([
    #("id", t.String),
    #("from", t.String),
    #("name", t.option(t.String)),
    #("timestamp", t.String),
    #("context", t.option(t.String)),
    #("data", t.String),
    #(
      "content",
      t.union([
        #("Text", t.String),
        #("Button", t.record([#("text", t.String), #("payload", t.String)])),
        #(
          "Interactive",
          t.record([
            #("type", t.String),
            #("id", t.String),
            #("title", t.String),
            #("description", t.option(t.String)),
          ]),
        ),
        #(
          "Media",
          t.record([
            #("type", t.String),
            #("id", t.option(t.String)),
            #("caption", t.String),
            #("mime_type", t.option(t.String)),
          ]),
        ),
        #("Other", t.String),
        #(
          "Reaction",
          t.record([#("message_id", t.String), #("emoji", t.String)]),
        ),
      ]),
    ),
  ])
}

pub fn event_types() {
  [
    #(
      "WhatsAppMessage",
      t.record([
        #("message", message_type()),
        #("referenced", t.option(message_type())),
      ]),
    ),
  ]
}

pub fn input_type() {
  t.union(event_types())
}

pub fn incoming_value(incoming: Incoming) {
  let content = case incoming.content {
    Text(text) -> data.tagged("Text", data.string(text))
    Button(text, payload) ->
      data.tagged(
        "Button",
        data.record([
          #("text", data.string(text)),
          #("payload", data.string(payload)),
        ]),
      )
    Interactive(kind, id, title, description) ->
      data.tagged(
        "Interactive",
        data.record([
          #("type", data.string(kind)),
          #("id", data.string(id)),
          #("title", data.string(title)),
          #("description", data.option(description, data.string)),
        ]),
      )
    Media(kind, id, caption, mime_type) ->
      data.tagged(
        "Media",
        data.record([
          #("type", data.string(kind)),
          #("id", data.option(id, data.string)),
          #("caption", data.string(caption)),
          #("mime_type", data.option(mime_type, data.string)),
        ]),
      )
    Other(kind) -> data.tagged("Other", data.string(kind))
    Reaction(message, emoji) ->
      data.tagged(
        "Reaction",
        data.record([
          #("message_id", data.string(message)),
          #("emoji", data.string(emoji)),
        ]),
      )
  }
  data.record([
    #("id", data.string(incoming.id)),
    #("from", data.string(incoming.from)),
    #("name", data.option(incoming.name, data.string)),
    #("timestamp", data.string(incoming.timestamp)),
    #("context", data.option(incoming.context, data.string)),
    #("data", data.string(incoming.data)),
    #("content", content),
  ])
}
