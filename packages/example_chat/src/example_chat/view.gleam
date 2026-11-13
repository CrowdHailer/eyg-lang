//// Chat interactions are a Lustre server component. The browser only runs the
//// standard howdy/Lustre transport; application events and rendering live here.

import example_chat/store
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import lustre/server_component

pub type Args {
  Args(store: Subject(store.Request), name: String, channel: String)
}

pub type Model {
  Model(
    store: Subject(store.Request),
    channels: List(store.Channel),
    channel: String,
    messages: List(store.Message),
    thread: Option(String),
    name: String,
    input: String,
    reply: String,
    sent: Int,
    replied: Int,
    error: String,
  )
}

pub type Msg {
  Poll
  ChooseChannel(String)
  Name(String)
  Typed(thread: Bool, text: String)
  Send(thread: Bool, text: String)
  OpenThread(String)
  CloseThread
  React(message: String, emoji: String)
}

pub fn app() {
  lustre.application(init, update, view)
}

pub fn init(args: Args) {
  let channels = store.call(args.store, store.Channels)
  let channel =
    list.find(channels, fn(channel) { channel.name == args.channel })
    |> result.or(list.first(channels))
    |> result.map(fn(channel) { channel.id })
    |> result.unwrap("")
  let model =
    Model(
      store: args.store,
      channels:,
      channel:,
      messages: [],
      thread: None,
      name: args.name,
      input: "",
      reply: "",
      sent: 0,
      replied: 0,
      error: "",
    )
  #(refresh(model), tick())
}

fn tick() {
  effect.from(fn(dispatch) {
    process.spawn(fn() {
      process.sleep(600)
      dispatch(Poll)
    })
    Nil
  })
}

fn refresh(model: Model) {
  Model(
    ..model,
    channels: store.call(model.store, store.Channels),
    messages: store.call(model.store, store.Messages(model.channel, _)),
  )
}

fn author(model: Model) {
  let name = case string.trim(model.name) {
    "" -> "anonymous"
    name -> name
  }
  store.Author(id: "U-" <> name, name:, bot: False)
}

pub fn update(model: Model, message: Msg) {
  case message {
    Poll -> #(refresh(model), tick())
    ChooseChannel(channel) -> #(
      refresh(Model(..model, channel:, thread: None)),
      effect.none(),
    )
    Name(name) -> #(Model(..model, name:), effect.none())
    Typed(False, input) -> #(Model(..model, input:), effect.none())
    Typed(True, reply) -> #(Model(..model, reply:), effect.none())
    OpenThread(id) -> #(Model(..model, thread: Some(id)), effect.none())
    CloseThread -> #(Model(..model, thread: None), effect.none())
    Send(in_thread, text) -> {
      case string.trim(text), model.channel, in_thread && model.thread == None {
        "", _, _ | _, "", _ | _, _, True -> #(model, effect.none())
        _, _, False -> {
          let thread = case in_thread {
            True -> model.thread
            False -> None
          }
          let result =
            store.call(model.store, store.Post(
              model.channel,
              thread,
              author(model),
              text,
              _,
            ))
          let model = case result {
            Error(reason) -> Model(..model, error: reason)
            Ok(_) ->
              case in_thread {
                True ->
                  Model(
                    ..model,
                    reply: "",
                    replied: model.replied + 1,
                    error: "",
                  )
                False ->
                  Model(..model, input: "", sent: model.sent + 1, error: "")
              }
          }
          #(refresh(model), effect.none())
        }
      }
    }
    React(message, emoji) -> {
      let result =
        store.call(model.store, store.React(message, emoji, author(model), _))
      let error = case result {
        Ok(_) -> ""
        Error(reason) -> reason
      }
      #(refresh(Model(..model, error:)), effect.none())
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  let channel =
    list.find(model.channels, fn(channel) { channel.id == model.channel })
    |> result.map(fn(channel) { "# " <> channel.name })
    |> result.unwrap("")
  let messages =
    list.filter(model.messages, fn(message) { message.thread == None })
  h.div([a.id("chat")], [
    h.nav([], [
      h.h1([], [h.text("Example chat")]),
      h.div(
        [a.id("channels")],
        list.map(model.channels, fn(channel) {
          h.button(
            [
              a.class(case channel.id == model.channel {
                True -> "active"
                False -> ""
              }),
              event.on_click(ChooseChannel(channel.id)),
            ],
            [h.text("# " <> channel.name)],
          )
        }),
      ),
      h.label([a.for("name")], [h.text("Posting as")]),
      h.input([a.id("name"), a.value(model.name), on_input(Name)]),
    ]),
    h.main([], [
      h.header([], [h.span([a.id("title")], [h.text(channel)])]),
      message_list("messages", messages, model, False),
      case model.error {
        "" -> h.text("")
        error -> h.p([a.class("error"), a.role("alert")], [h.text(error)])
      },
      composer(model, False),
    ]),
    case model.thread {
      None -> h.text("")
      Some(root) ->
        h.aside([a.id("thread")], [
          h.header([], [
            h.span([], [h.text("Thread")]),
            h.button(
              [
                a.id("close"),
                a.title("Close thread"),
                event.on_click(CloseThread),
              ],
              [h.text("✕")],
            ),
          ]),
          message_list(
            "replies",
            list.filter(model.messages, fn(message) {
              message.id == root || message.thread == Some(root)
            }),
            model,
            True,
          ),
          composer(model, True),
        ])
    },
  ])
}

fn on_input(message) {
  event.on("input", {
    use text <- decode.subfield(["target", "value"], decode.string)
    decode.success(message(text))
  })
  |> server_component.include(["target.value"])
}

fn composer(model: Model, thread) {
  let #(id, input, version) = case thread {
    True -> #("reply-text", model.reply, model.replied)
    False -> #("text", model.input, model.sent)
  }
  let textarea =
    h.textarea(
      [
        a.id(id),
        a.name("text"),
        a.rows(2),
        a.value(input),
        a.placeholder(case thread {
          True -> "Reply…"
          False -> "Message"
        }),
        on_input(Typed(thread, _)),
        event.advanced("keydown", {
          use key <- decode.field("key", decode.string)
          use shift <- decode.field("shiftKey", decode.bool)
          use composing <- decode.field("isComposing", decode.bool)
          use text <- decode.subfield(["target", "value"], decode.string)
          case key == "Enter" && !shift && !composing {
            True ->
              decode.success(event.handler(
                Send(thread, text),
                prevent_default: True,
                stop_propagation: False,
              ))
            False ->
              decode.failure(
                event.handler(
                  Typed(thread, text),
                  prevent_default: False,
                  stop_propagation: False,
                ),
                "not a send shortcut",
              )
          }
        })
          |> server_component.include([
            "key",
            "shiftKey",
            "isComposing",
            "target.value",
          ]),
      ],
      input,
    )
  h.form(
    [
      a.id(case thread {
        True -> "reply"
        False -> "compose"
      }),
      event.on("submit", decode.success(Send(thread, input)))
        |> event.prevent_default,
    ],
    [
      keyed.div([], [#(int.to_string(version), textarea)]),
      h.button([a.type_("submit"), a.class("send")], [h.text("Send")]),
      h.div([a.class("hint")], [
        h.text(
          "Enter to send, Shift+Enter for a new line. An eyg code block runs as a script.",
        ),
      ]),
    ],
  )
}

fn message_list(id, messages: List(store.Message), model, thread) {
  keyed.div(
    [a.id(id), a.class("messages")],
    list.map(list.reverse(messages), fn(message) {
      #(message.id, message_view(message, model, thread))
    }),
  )
}

fn message_view(message: store.Message, model: Model, thread) {
  let replies =
    list.filter(model.messages, fn(reply) { reply.thread == Some(message.id) })
    |> list.length
  let tools =
    list.map(["thumbsup", "books", "eyes", "white_check_mark"], fn(name) {
      h.button(
        [
          a.type_("button"),
          a.title("React " <> name),
          a.attribute("data-emoji", name),
          event.on_click(React(message.id, name)),
        ],
        [h.text(emoji(name))],
      )
    })
  h.div([a.class("message"), a.attribute("data-id", message.id)], [
    h.div([], [
      h.span([a.class("author")], [h.text(message.author.name)]),
      case message.author.bot {
        True -> h.span([a.class("badge")], [h.text("APP")])
        False -> h.text("")
      },
    ]),
    h.div([a.class("text")], rich_text(message.text)),
    h.div(
      [a.class("reactions")],
      list.map(message.reactions, fn(reaction) {
        h.span([a.class("reaction"), a.title(string.join(reaction.by, ", "))], [
          h.text(
            emoji(reaction.emoji)
            <> " "
            <> int.to_string(list.length(reaction.by)),
          ),
        ])
      }),
    ),
    case !thread && replies > 0 {
      True ->
        h.button(
          [
            a.type_("button"),
            a.class("replies"),
            event.on_click(OpenThread(message.id)),
          ],
          [
            h.text(
              int.to_string(replies)
              <> case replies {
                1 -> " reply"
                _ -> " replies"
              },
            ),
          ],
        )
      False -> h.text("")
    },
    h.div(
      [a.class("tools")],
      list.append(tools, case thread {
        True -> []
        False -> [
          h.button(
            [
              a.type_("button"),
              a.title("Reply in thread"),
              event.on_click(OpenThread(message.id)),
            ],
            [h.text("💬")],
          ),
        ]
      }),
    ),
  ])
}

fn emoji(name) {
  case name {
    "thumbsup" -> "👍"
    "books" -> "📚"
    "eyes" -> "👀"
    "white_check_mark" -> "✅"
    "tada" -> "🎉"
    _ -> ":" <> name <> ":"
  }
}

fn rich_text(text) {
  string.split(text, "```")
  |> list.index_map(fn(part, index) {
    case index % 2 {
      0 -> h.span([], inline(part))
      _ -> {
        let code = case string.split_once(part, "\n") {
          Ok(#(language, code)) if language == "eyg" || language == "" -> code
          _ -> part
        }
        h.pre([], [h.code([], [h.text(code)])])
      }
    }
  })
}

fn inline(text) {
  string.split(text, "`")
  |> list.index_map(fn(part, index) {
    case index % 2 {
      1 -> h.code([], [h.text(part)])
      _ ->
        h.span(
          [],
          string.split(part, "**")
            |> list.index_map(fn(part, index) {
              case index % 2 {
                1 -> h.b([], [h.text(part)])
                _ ->
                  h.span(
                    [],
                    string.split(part, " ")
                      |> list.index_map(fn(word, index) {
                        let prefix = case index {
                          0 -> ""
                          _ -> " "
                        }
                        h.span([], [
                          h.text(prefix),
                          case
                            string.starts_with(word, "https://")
                            || string.starts_with(word, "http://")
                          {
                            True ->
                              h.a(
                                [
                                  a.href(word),
                                  a.target("_blank"),
                                  a.rel("noopener noreferrer"),
                                ],
                                [h.text(word)],
                              )
                            False -> h.text(word)
                          },
                        ])
                      }),
                  )
              }
            }),
        )
    }
  })
}
